import Foundation
import AppKit
import IOKit.ps
import Dispatch
import CoreGraphics
@preconcurrency import VisionKit // FIXME probably shouldn't use this
@preconcurrency import ScreenCaptureKit // "
import AVFoundation
import SQLite

// TODO replayd is using 4.5gb of memory rn. that might be a problem.
// TODO use `throw` in more places
// FIXME doesn't seem to be checking similarity
// FIXME figure out why I ended up with a 1 frame mp4 one time
//       (relatedly, `subrecords` one time only had a length of 1)

// TODO graceful exit where a gentle quit request (e.g. ctrl+c, but
// also whatever macOS would give it e.g. when it wants to shut down)
// makes it process the remaining images (maybe), but a hard request
// (e.g. 2 ctrl+c's) makes it quit immediately.
// Also, need to think about what to do if there's already a file
// corresponding to the timeframe we're trying to write for (e.g. if
// the process were quit and then immediately restarted.)

func log(_ string: String) {
    print("\(Date())\t\(string)")
}

struct RecordInfo {
    var windowId: Int
    var rect: CGRect
    var windowName = ""
    var appId = ""
    var appName = ""
    var url = ""
}

struct Record {
    var image: CGImage
    var time: Int
    var info: RecordInfo
    var ocrText: String?
    var mp4LargeURL: URL?
    var mp4SmallURL: URL?
}

actor Data {
    // Might make more sense to just define this in Recorder and pass Recorder instance to Processor
    private var records: [Record] = [] // last 5-10 min of images

    func get() -> [Record] {
        return records
    }

    func get(at index: Int) -> Record {
        return records[index]
    }

    func add(record: Record) {
        records.append(record)
    }

    func remove(at index: Int) {
        records.remove(at: index)
    }
}


enum FilesError: Error {
    case nonexistentDirectory(String)
}

actor Files {
    let appSupportDir: URL
    let databaseFile: URL

    init() throws {
        let bundleIdentifier = "com.example.Rekal" // TODO bundle.main.bundleidentifier(?)
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw FilesError.nonexistentDirectory("Failed to get location of Application Support directory")
        }
        appSupportDir = dir.appending(path: bundleIdentifier)

        databaseFile = appSupportDir.appending(path: "sqlite3.db")
    }
}

enum DatabaseError: Error {
    case fileError(String)
    case error(String)
}

class Database {
    private let db: Connection
    private let records = Table("records")

    private let timestamp = SQLite.Expression<Int>("timestamp")
    private let windowId = SQLite.Expression<Int>("window_id")
    private let windowName = SQLite.Expression<String?>("window_name")
    private let appId = SQLite.Expression<String?>("app_id")
    private let appName = SQLite.Expression<String?>("app_name")
    private let url = SQLite.Expression<String?>("url")
    private let x = SQLite.Expression<Int>("x")
    private let y = SQLite.Expression<Int>("y")
    private let width = SQLite.Expression<Int>("width")
    private let height = SQLite.Expression<Int>("height")
    private let ocrText = SQLite.Expression<String>("ocr_text")
    private let mp4LargePath = SQLite.Expression<String>("mp4_large_path")
    private let mp4SmallPath = SQLite.Expression<String>("mp4_small_path")

    init(files: Files) throws {
        let dbPath = files.databaseFile.path
        let exists = FileManager.default.fileExists(atPath: dbPath)
        if !exists {
            guard FileManager.default.createFile(atPath: dbPath, contents: nil) else {
                throw DatabaseError.fileError("Failed to create '\(dbPath)'")
            }
        }

        db = try Connection(dbPath)

        if !exists {
            try create()
        }
    }

    func create() throws {
        try db.run(records.create { t in
            t.column(timestamp, primaryKey: true)
            t.column(windowId)
            t.column(windowName)
            t.column(appId)
            t.column(appName)
            t.column(url)
            t.column(x)
            t.column(y)
            t.column(width)
            t.column(height)
            t.column(ocrText)
            t.column(mp4LargePath)
            t.column(mp4SmallPath)
        })
    }

    func insert(record: Record) throws {
        guard let mp4LargeURL = record.mp4LargeURL,
                let mp4SmallURL = record.mp4SmallURL else {
            throw DatabaseError.error("MP4 URLs not present in record")
        }
        try db.run(records.insert(
            timestamp <- record.time,
            windowId <- record.info.windowId,
            windowName <- record.info.windowName,
            appId <- record.info.appId,
            appName <- record.info.appName,
            url <- record.info.url,
            x <- Int(record.info.rect.minX),
            y <- Int(record.info.rect.minY),
            width <- Int(record.info.rect.width),
            height <- Int(record.info.rect.height),
            ocrText <- record.ocrText ?? "",
            mp4LargePath <- mp4LargeURL.path,
            mp4SmallPath <- mp4SmallURL.path
        ))
    }
}

enum RecordingError: Error {
    case infoError(String)
}

actor Recorder {
    private let data: Data
    private let files: Files
    private let interval: TimeInterval
    private var lastRecord: Record? = nil

    init(data: Data, interval: TimeInterval, files: Files) {
        self.data = data
        self.interval = interval
        self.files = files
    }

    func record() async throws {
        if isIdle() {
            log("Skipping: idle")
            return
        }

        // XXX not sure this code runs the way I expect
        // Expect catch clause, but not guard-else clause, to be run if `capture` throws
        do {
            guard let record = try await capture() else {
                return
            }
            await data.add(record: record)
            log("Saved image")
        } catch {
            log("Did not save image: \(error)")
        }
    }

    private func capture() async throws -> Record? {
        let timestamp = Int(Date().timeIntervalSince1970)
        var info: RecordInfo? = nil

        guard let frontmostAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }

        // or SCShareableContent.current(?)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw RecordingError.infoError("No displays found")
        }

        for window in content.windows {
            if let app = window.owningApplication, app.processID == frontmostAppPID {
                info = await getWindowInfo(window: window)
                break
            }
        }
        guard let info = info else {
            throw RecordingError.infoError("Failed to get window info")
        }

        // TODO make these configurable via GUI (UserDefaults?)
        let excludedApps: [String] = ["com.apple.FaceTime", "com.apple.Passwords"]
        let excludedURLs: [String] = [] // TODO zoom.us, meet.jit.si, etc

        if info.appId != "" {
            for app in excludedApps {
                if app == info.appId {
                    log("Skipping: active application is on blacklist")
                    return nil
                }
            }
        }
        if info.url != "" {
            for url in excludedURLs {
                if url == info.url {
                    log("Skipping: active URL is on blacklist")
                    return nil
                }
            }
        }

        // TODO exclude apps, and exclude the browser if the active url is blacklisted
        // for the browser, get the specific window id containing blacklisted urls and exclude that window
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        if let lastRecord = lastRecord, isSimilar(image1: lastRecord.image, image2: image) {
            log("Images are similar; skipping")
            return nil
        }

        let record = Record(image: image, time: timestamp, info: info)
        lastRecord = record
        return record
    }

    private func getWindowInfo(window: SCWindow) async -> RecordInfo {
        var info = RecordInfo(windowId: Int(window.windowID), rect: window.frame)

        if let title = window.title {
            info.windowName = title
        }

        if let app = window.owningApplication {
            info.appName = app.applicationName
            info.appId = app.bundleIdentifier

            if app.bundleIdentifier == "com.google.Chrome" {
                if let lastRecord = lastRecord, window.title == lastRecord.info.windowName {
                    info.url = lastRecord.info.url
                    return info
                } else if let url = getBrowserURL() {
                    info.url = url
                }
            }
        }

        return info
    }

    private func isIdle() -> Bool {
        let events: [CGEventType] = [
            .keyDown,

            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,

            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,

            .scrollWheel
        ]

        for event in events {
            let time = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: event)
            if time < interval {
                return false
            }
        }
        return true
    }

    private func isSimilar(image1: CGImage, image2: CGImage) -> Bool {
        if let similarity = pHash(image1: image1, image2: image2) {
            return similarity > 0.9
        }
        return false
    }

    private func getBrowserURL() -> String? {
        let script = "tell application \"Google Chrome\" to get URL of active tab of front window"
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if error == nil {
                return output.stringValue
            }
            print("Error getting active URL via AppleScript")
        }
        return nil
    }

    private func pHash(image1: CGImage, image2: CGImage) -> Double? {
        // Size for DCT
        let size = 32
        let hashSize = 8
        
        // Create contexts for downsampling
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let context1 = CGContext(data: nil,
                                    width: size,
                                    height: size,
                                    bitsPerComponent: 8,
                                    bytesPerRow: size,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo.rawValue),
            let context2 = CGContext(data: nil,
                                    width: size,
                                    height: size,
                                    bitsPerComponent: 8,
                                    bytesPerRow: size,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }

        // Draw downsampled grayscale images
        context1.draw(image1, in: CGRect(x: 0, y: 0, width: size, height: size))
        context2.draw(image2, in: CGRect(x: 0, y: 0, width: size, height: size))
        
        guard let pixels1 = context1.data?.assumingMemoryBound(to: UInt8.self),
            let pixels2 = context2.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        // Convert to binary using median as threshold
        var values1 = [UInt8](repeating: 0, count: size * size)
        var values2 = [UInt8](repeating: 0, count: size * size)
        
        // Copy pixels to sort for median
        for i in 0..<(size * size) {
            values1[i] = pixels1[i]
            values2[i] = pixels2[i]
        }
        
        values1.sort()
        values2.sort()
        
        let threshold1 = values1[size * size / 2]
        let threshold2 = values2[size * size / 2]
        
        // Convert to binary
        var binaryPixels1 = [Float](repeating: 0, count: size * size)
        var binaryPixels2 = [Float](repeating: 0, count: size * size)
        
        for i in 0..<(size * size) {
            binaryPixels1[i] = pixels1[i] > threshold1 ? 255 : 0
            binaryPixels2[i] = pixels2[i] > threshold2 ? 255 : 0
        }
        
        // Apply DCT
        var dct1 = [Float](repeating: 0, count: hashSize * hashSize)
        var dct2 = [Float](repeating: 0, count: hashSize * hashSize)
        
        // Calculate DCT and take top-left 8x8
        for y in 0..<hashSize {
            for x in 0..<hashSize {
                var sum1: Float = 0
                var sum2: Float = 0
                
                for i in 0..<size {
                    for j in 0..<size {
                        let cos = cosf(Float.pi * Float(x) * Float(j) / Float(size)) *
                                cosf(Float.pi * Float(y) * Float(i) / Float(size))
                        sum1 += binaryPixels1[i * size + j] * cos
                        sum2 += binaryPixels2[i * size + j] * cos
                    }
                }
                
                dct1[y * hashSize + x] = sum1
                dct2[y * hashSize + x] = sum2
            }
        }
        
        // Calculate average values
        let avg1 = dct1.reduce(0, +) / Float(hashSize * hashSize)
        let avg2 = dct2.reduce(0, +) / Float(hashSize * hashSize)
        
        // Generate hash bits
        var hash1: UInt64 = 0
        var hash2: UInt64 = 0
        
        for i in 0..<(hashSize * hashSize) {
            if dct1[i] > avg1 {
                hash1 |= 1 << i
            }
            if dct2[i] > avg2 {
                hash2 |= 1 << i
            }
        }
        
        // Calculate Hamming distance
        let xorHash = hash1 ^ hash2
        let hammingDistance = xorHash.nonzeroBitCount
        
        // Convert to similarity percentage
        return 1.0 - (Double(hammingDistance) / Double(hashSize * hashSize))
    }
}

enum ProcessingError: Error {
    case imageDestinationCreationFailed(String)
    case error(String)
}

actor Processor {
    private let data: Data
    private let interval: Int
    private let database: Database
    private let files: Files

    init(data: Data, interval: Int, files: Files) throws {
        self.data = data
        self.interval = interval
        self.files = files
        self.database = try Database(files: files)
    }

    func process() async throws {
        try await saveRecords()
    }

    private func saveRecords() async throws {
        // TODO probably shouldn't copy the records since that's a lot of data.
        // references? indices? pointers?

        if !isDeviceOnPower() {
            log("Device is not on power; delaying processing")
            return
        }

        var recordList: [Int: [Record]] = [:]
        let now = Int(Date().timeIntervalSince1970)

        for record in await data.get() {
            if now - record.time > interval {
                break
            }
            let time = record.time / interval * interval
            recordList[time, default: []].append(record)
        }

        for (time, var subrecords) in recordList {
            if !isDeviceOnPower() {
                log("Device is not on power; delaying processing")
                break
            }

            let mp4LargeURL = files.appSupportDir.appending(path: "\(time)-large.mp4")
            let mp4SmallURL = files.appSupportDir.appending(path: "\(time)-small.mp4")

            for (index, _) in subrecords.enumerated() {
                subrecords[index].ocrText = try await performOCR(image: subrecords[index].image)
                subrecords[index].mp4LargeURL = mp4LargeURL
                subrecords[index].mp4SmallURL = mp4SmallURL
            }
            for record in subrecords {
                print("record:", record.mp4LargeURL ?? "no mp4 large url,", record.mp4SmallURL ?? "no mp4 small url")
            }

            let subrecordsSmall = subrecords
            for var record in subrecordsSmall {
                guard let image = resize480p(record.image) else {
                    throw ProcessingError.error("Resizing images failed")
                }
                record.image = image
            }

            try await encodeMP4(records: subrecords, outputURL: mp4LargeURL)
            try await encodeMP4(records: subrecordsSmall, outputURL: mp4SmallURL)

            for record in subrecords {
                try database.insert(record: record)
            }

            // TODO abomination
            for record in subrecords {
                for (index, _) in await data.get().enumerated() {
                    let time = await data.get(at: index).time
                    if time == record.time {
                        await data.remove(at: index)
                        break
                    }
                }
            }

            log("Created \(time).mp4")
        }
    }

    private func resize480p(_ image: CGImage) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let aspectRatio = width / height

        let newHeight: CGFloat = 480
        let newWidth = newHeight * aspectRatio
        let newSize = CGSize(width: newWidth, height: newHeight)

        guard let colorSpace = image.colorSpace,
                let context = CGContext(
                    data: nil,
                    width: Int(newWidth),
                    height: Int(newHeight),
                    bitsPerComponent: image.bitsPerComponent,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: image.bitmapInfo.rawValue
                ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: newSize))

        return context.makeImage()
    }

    // TODO: see if AVFoundation can be made faster / make smaller files; if not, use ffmpeg (ramdisk, tmpfs, or API)
    private func encodeMP4(records: [Record], outputURL: URL) async throws {
        guard let firstRecord = records.first else {
            throw ProcessingError.imageDestinationCreationFailed("No records to encode")
        }

        let width = firstRecord.image.width
        let height = firstRecord.image.height

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for (index, record) in records.enumerated() {
            let time = CMTime(value: CMTimeValue(index), timescale: 1)
            while !input.isReadyForMoreMediaData {
                await Task.yield()
            }

            var pixelBuffer: CVPixelBuffer?
            let options: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, options as CFDictionary, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                throw ProcessingError.imageDestinationCreationFailed("Failed to create pixel buffer")
            }

            let context = CIContext()
            let ciImage = CIImage(cgImage: record.image)
            context.render(ciImage, to: buffer)

            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()
        await writer.finishWriting()
    }

    private func performOCR(image: CGImage) async throws -> String? {
        let analyzer = ImageAnalyzer()
        let config = ImageAnalyzer.Configuration([.text])

        let analysis = try await analyzer.analyze(image, orientation: .right, configuration: config)
        return analysis.transcript
    }

    private func isDeviceOnPower() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(snapshot)
        guard let type = type else {
            return false // TODO maybe throw
        }
        let type2 = type.takeRetainedValue() as String
        return type2 == kIOPSACPowerValue
    }
}

func main() {
    let recordInterval = 1.0    // seconds
    // let processInterval = 300   // seconds
    let processInterval = 30

    print("Starting daemon...")

    do {
        let files = try Files()
        let data = Data()

        try FileManager.default.createDirectory(at: files.appSupportDir, withIntermediateDirectories: true, attributes: nil)

        let recorder = Recorder(data: data, interval: recordInterval, files: files)
        let processor = try Processor(data: data, interval: processInterval, files: files)

        Task {
            do {
                try await recorder.record()
            } catch {
                print("Error capturing snapshot: \(error)")
            }
        }
        Task { try await recorder.record() }
        Timer.scheduledTimer(withTimeInterval: recordInterval, repeats: true) { _ in
            Task {
                do {
                    try await recorder.record()
                } catch {
                    print("Error capturing snapshot: \(error)")
                }
            }
        }

        Timer.scheduledTimer(withTimeInterval: TimeInterval(processInterval), repeats: true) { _ in
            Task {
                do {
                    try await processor.process()
                } catch {
                    print("Error processing snapshots: \(error)")
                }
            }
        }
    } catch {
        log("Error: \(error)")
    }

    RunLoop.current.run()
}

main()
import Foundation
import CoreGraphics
import ScreenCaptureKit
import Accelerate // why is this here?

struct Record {
    var image: CGImage
    var time: Int
    var windowInfo: [String: Any]
}

public func getIdleTime() -> Double? {
    var iterator: io_iterator_t = 0
    defer { IOObjectRelease(iterator) }
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else { 
        return nil
    }    

    let entry: io_registry_entry_t = IOIteratorNext(iterator)
    defer { IOObjectRelease(entry) }
    guard entry != 0 else {
        return nil
    }

    var unmanagedDict: Unmanaged<CFMutableDictionary>?
    defer { unmanagedDict?.release() }
    guard IORegistryEntryCreateCFProperties(entry, &unmanagedDict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = unmanagedDict?.takeUnretainedValue() else {
        return nil
    }

    let key = "HIDIdleTime" as CFString
    guard let value = CFDictionaryGetValue(dict, Unmanaged.passUnretained(key).toOpaque()) else {
        return nil
    }
    let number = unsafeBitCast(value, to: CFNumber.self)
    var nanoseconds: Int64 = 0
    guard CFNumberGetValue(number, CFNumberType.sInt64Type, &nanoseconds) else {
        return nil
    }

    return Double(nanoseconds) / Double(NSEC_PER_SEC)
}

enum SaveRecordError: Error {
    case directoryCreationFailed(String)
    case imageDestinationCreationFailed(String)
    case imageFinalizationFailed(String)
    case jsonWriteFailed(String)
}

func saveRecord(_ record: Record) throws {
    // TODO think about the possibility of a race condition--two workers trying to write to the same timestamp directory
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let dir = homeDir.appendingPathComponent("ss/\(record.time)")
    let filePath = dir.appendingPathComponent("image.png")
    let jsonFilePath = dir.appendingPathComponent("info.json")

    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: nil)
    } catch {
        throw SaveRecordError.directoryCreationFailed("Cannot make directory \(dir): \(error)")
    }

    guard let dest = CGImageDestinationCreateWithURL(filePath as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw SaveRecordError.imageDestinationCreationFailed("Cannot create image destination")
    }

    CGImageDestinationAddImage(dest, record.image, nil)

    if !CGImageDestinationFinalize(dest) {
        throw SaveRecordError.imageFinalizationFailed("Cannot finalize image destination")
    }

    if let jsonData = try? JSONSerialization.data(withJSONObject: record.windowInfo) {
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            do {
                try jsonString.write(to: jsonFilePath, atomically: true, encoding: .utf8)
            } catch {
                throw SaveRecordError.jsonWriteFailed("Cannot write JSON data to file: \(error)")
            }
        }
    }
}

func pHash(image1: CGImage, image2: CGImage) -> Double? {
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

func isSimilar(image1: CGImage, image2: CGImage) -> Bool {
    if let similarity = pHash(image1: image1, image2: image2) {
        return similarity > 0.9
    }
    return false
}

func capture(lastRecord: Record? = nil) async -> Record? {
    let timestamp = Int(Date().timeIntervalSince1970)

    // Screenshot
    let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content?.displays.first else {
        return nil
    }

    // TODO exclude FaceTime, Passwords
    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

    let config = SCStreamConfiguration()
    config.width = display.width
    config.height = display.height

    guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
        return nil
    }

    if let lastRecord = lastRecord {
        if isSimilar(image1: lastRecord.image, image2: image) {
            return nil
        }
    }

    // Get window info
    var windowInfo: [String: Any] = [:]
    let windows = content?.windows ?? []

    guard let frontmostAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
        return nil
    }

    for window in windows {
        guard let app = window.owningApplication else {
            continue
        }
        if app.processID == frontmostAppPID {
            windowInfo["id"] = window.windowID
            windowInfo["bounds"] = ["x": window.frame.minX, "y": window.frame.minY, "width": window.frame.width, "height": window.frame.height]
            windowInfo["title"] = window.title ?? ""
            windowInfo["appName"] = app.applicationName
            windowInfo["url"] = ""

            // FIXME hideous
            if app.bundleIdentifier == "com.google.Chrome" {
                if let lastRecord = lastRecord, let lastTitle = lastRecord.windowInfo["title"] as? String {
                    if window.title != lastTitle {
                        if let url = getBrowserURL() {
                            windowInfo["url"] = url
                        }
                    }
                } else {
                    if let url = getBrowserURL() {
                        windowInfo["url"] = url
                    }
                }
            }
            break
        }
    }

    return Record(image: image, time: timestamp, windowInfo: windowInfo)
}

func getBrowserURL() -> String? {
    let script = """
    tell application "Google Chrome"
        get URL of active tab of front window
    end tell
    """
    var error: NSDictionary?
    if let scriptObject = NSAppleScript(source: script) {
        let output = scriptObject.executeAndReturnError(&error)
        if error == nil {
            return output.stringValue
        }
    }
    return nil
}

let interval = 1.0 // seconds

actor ScreenRecorder {
    private var lastRecord: Record
    private var count: Int

    init(record: Record) {
        self.lastRecord = record
        self.count = 1
    }

    func updateRecord(_ newRecord: Record) async throws {
        try saveRecord(newRecord)
        print("took screenshot \(count)")
        lastRecord = newRecord
        count += 1
    }

    func getLastRecord() -> Record {
        return lastRecord
    }
}

guard let initialRecord = await capture() else {
    print("Failed to capture initial screenshot")
    exit(1)
}

do {
    try saveRecord(initialRecord)
    print("took screenshot 0")
} catch {
    print("Failed to save initial record: \(error)")
    exit(1)
}

let recorder = ScreenRecorder(record: initialRecord)

Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
    Task {
        do {
            guard let idleTime = getIdleTime() else {
                print("Failed to get idle time")
                return
            }

            if idleTime >= interval {
                print("Idle; skipping")
                return
            }

            let lastRecord = await recorder.getLastRecord()
            guard let newRecord = await capture(lastRecord: lastRecord) else {
                print("Did not save image")
                return
            }

            try await recorder.updateRecord(newRecord)
        } catch {
            print("Failed to process screenshot: \(error)")
        }
    }
}

// FIXME this isn't the right method but it works
RunLoop.main.run()
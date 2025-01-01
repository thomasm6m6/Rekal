import Foundation
import VisionKit
import AppKit // included for NSImage. alternative? or is this the correct approach?
import IOKit.ps
import Dispatch

// XXX there might be a bug relating to the mp4s not being made in order. see: ~/ss/small/1735708500.mp4

let rootDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ss")

func log(_ string: String) {
    print(Date(), string)
}

enum OCRError: Error {
    case analysisFailed(String)
}

func performOCR(image: NSImage) async throws -> String? {
    log("performOCR(image)")
    let analyzer = ImageAnalyzer()
    let configuration = ImageAnalyzer.Configuration([.text])

    do {
        let analysis = try await analyzer.analyze(image, orientation: .right, configuration: configuration)
        return analysis.transcript
    } catch {
        throw OCRError.analysisFailed("Unable to analyze image")
    }
}

func makeList() throws -> [Int: [URL]] {
    var files: [Int: [URL]] = [:]
    let now = Int(Date().timeIntervalSince1970)
    let imageDir = rootDir.appendingPathComponent("img")

    let contents = try FileManager.default.contentsOfDirectory(
        at: imageDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
    )

    for dirURL in contents {
        let imageURL = dirURL.appendingPathComponent("image.png")
        guard let timestamp = Int(dirURL.lastPathComponent),
                FileManager.default.fileExists(atPath: imageURL.path),
                now - timestamp > 300 else {
            continue
        }

        let block = timestamp / 300 * 300
        files[block, default: []].append(dirURL)
    }

    files.keys.forEach { block in
        files[block]?.sort(by: {
            (Int($0.lastPathComponent) ?? 0) < (Int($1.lastPathComponent) ?? 0)
        })
    }

    return files
}

func removeDir(dir: URL) throws {
    log("removeDir(\(dir.path))")
    // TODO remove image instead once I'm confident
    let imageURL = dir.appendingPathComponent("image.png")
    let trashDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ss_rm")
    let destDir = trashDir.appendingPathComponent(dir.lastPathComponent)
    let destURL = destDir.appendingPathComponent("image.png")

    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
    // print("trying to move \(imageURL.path) to \(destURL.path)")
    try FileManager.default.moveItem(at: imageURL, to: destURL)
}

func makeMP4s() async throws {
    log("makeMP4s()")
    // TODO iterate through files in numeric order of keys
    let files = try makeList()

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    guard FileManager.default.createFile(atPath: tempFile.path, contents: nil, attributes: nil) else {
        return // TODO throw
    }
    let fileHandle = try FileHandle(forWritingTo: tempFile)

    for (block, dirs) in files {
        if !isOnPower {
            break
        }

        let mp4Full = rootDir.appendingPathComponent("full/\(block).mp4")
        let mp4Small = rootDir.appendingPathComponent("small/\(block).mp4")

        if FileManager.default.fileExists(atPath: mp4Full.path) {
            log("\(mp4Full.path) exists; skipping")
            continue
        }

        var concatContent = ""
        for dir in dirs {
            let ocrURL = dir.appendingPathComponent("ocr.txt")
            let imageURL = dir.appendingPathComponent("image.png")
            print("ocrURL = \(ocrURL.path)")
            print("imageURL = \(imageURL.path)")

            guard let image = NSImage(contentsOf: imageURL) else {
                log("Error: Cannot load image \(imageURL.path)")
                continue // TODO throw error?
            }

            do {
                guard let result = try await performOCR(image: image) else {
                    log("Error running performOCR")
                    continue // TODO throw error?
                }
                try result.write(to: ocrURL, atomically: false, encoding: .utf8)
            } catch {
                log("Error with OCR: \(error)")
            }

            concatContent += "file '\(imageURL.path)'\nduration 1.0\n"
        }

        if let data = concatContent.data(using: .utf8) {
            try fileHandle.write(contentsOf: data)
        } else {
            log("Cannot make data from string")
        }

        let processF = Process()
        processF.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        processF.arguments = [
            "-nostdin",
            "-v", "error",
            "-f", "concat",
            "-safe", "0",
            "-i", tempFile.path,
            "-c:v", "libaom-av1",
            "-cpu-used", "8",
            "-pix_fmt", "yuv420p",
            "-vf", "crop=iw:ih-1",
            mp4Full.path
        ]

        let processS = Process()
        processS.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        processS.arguments = [
            "-nostdin",
            "-v", "error",
            "-f", "concat",
            "-safe", "0",
            "-i", tempFile.path,
            "-c:v", "libaom-av1",
            "-cpu-used", "8",
            "-preset", "veryslow",
            "-crf", "30",
            "-pix_fmt", "yuv420p",
            "-vf", "crop=iw:ih-1,scale=(480*iw/ih+2):480",
            mp4Small.path
        ]

        do {
            log("running \(processF)")
            try processF.run()
            log("running \(processS)")
            try processS.run()
        } catch {
            log("Error: \(error)")
            continue
        }

        processF.waitUntilExit()
        processS.waitUntilExit()

        try fileHandle.truncate(atOffset: 0)

        for dir in dirs {
            try removeDir(dir: dir)
        }

        log("make \(block).mp4")
    }
    // TODO use defer
    try fileHandle.close()
    try FileManager.default.removeItem(at: tempFile)
    log("end makeMP4s()")
}

func isDeviceOnPower() -> Bool {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let type = IOPSGetProvidingPowerSourceType(snapshot)
    guard let type = type else {
        return false
    }
    let type2 = type.takeRetainedValue() as String
    return type2 == kIOPSACPowerValue
}

let semaphore = DispatchSemaphore(value: 1)

func doProcess() async {
    log("doProcess()")
    guard isOnPower else {
        return
    }

    if semaphore.wait(timeout: .now()) == .success {
        defer { semaphore.signal() }

        do {
            try await makeMP4s()
        } catch {
            log("Error: \(error)")
        }
    } else {
        log("makeMP4s already running")
    }
}

var isOnPower = isDeviceOnPower()
let loop = IOPSNotificationCreateRunLoopSource({ _ in
    isOnPower = isDeviceOnPower()
}, nil).takeRetainedValue() as CFRunLoopSource
CFRunLoopAddSource(CFRunLoopGetCurrent(), loop, .defaultMode)

Task { await doProcess() }
Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
    Task { await doProcess() }
}

RunLoop.current.run()
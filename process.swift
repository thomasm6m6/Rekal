import Foundation
import VisionKit
import AppKit // included for NSImage. alternative? or is this the correct approach?
import IOKit.ps
import Dispatch

// FIXME figure out why there are discrepancies between the file index as calculated by this implementation vs process.py

let rootDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ss")
let imgDir = rootDir.appendingPathComponent("img")
let fullDir = rootDir.appendingPathComponent("full")
let smallDir = rootDir.appendingPathComponent("small")

var isOnPower = false

func log(_ string: String) {
    print(Date(), string)
}

func performOCR(on imageURL: URL) async -> String {
    // let imageURL = URL(fileURLWithPath: imagePath)
    guard FileManager.default.fileExists(atPath: imageURL.path) else {
        log("Error: File not found at \(imageURL.path)")
        return "" // TODO throw error
    }
    
    guard let image = NSImage(contentsOf: imageURL) else {
        log("Error: Unable to load the image.")
        return "" // TODO throw error
    }
    
    let analyzer = ImageAnalyzer()
    let configuration = ImageAnalyzer.Configuration([.text])
    
    let analysis = try? await analyzer.analyze(image, orientation: .right, configuration: configuration)
    return analysis!.transcript
}

func ocr(filePath: URL) async throws {
    let imagePath = filePath.appendingPathComponent("image.png")
    let ocrPath = filePath.appendingPathComponent("ocr.txt")

    let result = await performOCR(on: imagePath)
    try result.write(to: ocrPath, atomically: true, encoding: .utf8)
}

func encode() throws -> [Int: [URL]] {
    var files: [Int: [URL]] = [:]
    let now = Int(Date().timeIntervalSince1970)

    let fileManager = FileManager.default
    let contents = try fileManager.contentsOfDirectory(
        at: imgDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
    )

    for dirURL in contents {
        guard let isDir = try dirURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir else {
            continue
        }

        guard let timestamp = Int(dirURL.lastPathComponent) else {
            continue
        }
        if now - timestamp < 300 {
            continue
        }

        let block = timestamp / 300 * 300
        if files[block] != nil {
            files[block]?.append(dirURL)
        } else {
            files[block] = [dirURL]
        }
    }

    for (block, dirs) in files {
        files[block] = dirs.sorted {
            Int($0.lastPathComponent) ?? 0 < Int($1.lastPathComponent) ?? 0
        }
    }

    return files
}

func removeDir(dir: URL) throws {
    log("removeDir(\(dir.path))")
    // TODO remove dir instead once I'm confident
    let destinationDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ss_rm")
    let destinationURL = destinationDir.appendingPathComponent(dir.lastPathComponent)

    if !FileManager.default.fileExists(atPath: destinationDir.path) {
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true, attributes: nil)
    }

    try FileManager.default.moveItem(at: dir, to: destinationURL)
}

func makeMP4s() throws {
    log("makeMP4s()")
    // TODO iterate through files in numeric order of keys
    let files = try encode()

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    guard FileManager.default.createFile(atPath: tempFile.path, contents: nil, attributes: nil) else {
        return // TODO throw
    }
    let fileHandle = try FileHandle(forWritingTo: tempFile)
    // let fileHandle: FileHandle
    // do {
    //     fileHandle = try FileHandle(forWritingTo: tempFile)
    // } catch {
    //     throw NSError(domain: "FileHandling", code: 1,
    //         userInfo: [NSLocalizedDescriptionKey: "Cannot create file handle: \(error.localizedDescription)"])
    // }

    for (key, dirs) in files {
        if !isOnPower {
            break
        }
    
        let mp4Full = fullDir.appendingPathComponent("\(key).mp4")
        let mp4Small = smallDir.appendingPathComponent("\(key).mp4")

        if FileManager.default.fileExists(atPath: mp4Full.path) {
            log("\(mp4Full.path) exists; skipping")
            continue
        }

        var concatContent = ""
        for dir in dirs {
            concatContent += "file '\(dir.appendingPathComponent("image.png").path)'\nduration 1.0\n"
        }
        // TODO maybe use fileHandle
        try concatContent.write(to: tempFile, atomically: true, encoding: .utf8)

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
            do {
                try removeDir(dir: dir)
            } catch {
                log("Error: failed to remove dir \(dir.path): \(error)")
            }
        }

        log("make \(key).mp4")
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

func doProcess() {
    log("doProcess()")
    guard isOnPower else {
        return
    }

    if semaphore.wait(timeout: .now()) == .success {
        defer { semaphore.signal() }

        do {
            try makeMP4s()
        } catch {
            log("Error: \(error)")
        }
    } else {
        log("makeMP4s already running")
    }
}

isOnPower = isDeviceOnPower()
let loop = IOPSNotificationCreateRunLoopSource({ _ in
    isOnPower = isDeviceOnPower()
}, nil).takeRetainedValue() as CFRunLoopSource
CFRunLoopAddSource(CFRunLoopGetCurrent(), loop, .defaultMode)

doProcess()
Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
    doProcess()
}

RunLoop.current.run()
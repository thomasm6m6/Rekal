import Foundation
import VisionKit
import AppKit // included for NSImage. alternative? or is this the correct approach?
import IOKit.ps

// FIXME figure out why there are discrepancies between the file index as calculated by this implementation vs process.py

let rootDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ss")
let imgDir = rootDir.appendingPathComponent("img")
let fullDir = rootDir.appendingPathComponent("full")
let smallDir = rootDir.appendingPathComponent("small")

var isOnPower = false
var isProcessing = false

func performOCR(on imageURL: URL) async -> String {
    // let imageURL = URL(fileURLWithPath: imagePath)
    guard FileManager.default.fileExists(atPath: imageURL.path) else {
        print("Error: File not found at \(imageURL.path)")
        return "" // TODO throw error
    }
    
    guard let image = NSImage(contentsOf: imageURL) else {
        print("Error: Unable to load the image.")
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
    print("encode()")
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

    print("end encode()")
    return files
}

func removeDir(dir: URL) throws {
    print("removeDir(\(dir.path))")
    // TODO remove dir instead once I'm confident
    let destinationDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ss_rm")
    let destinationURL = destinationDir.appendingPathComponent(dir.lastPathComponent)

    if !FileManager.default.fileExists(atPath: destinationDir.path) {
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true, attributes: nil)
    }

    try FileManager.default.moveItem(at: dir, to: destinationURL)
    print("end removeDir()")
}

func makeMP4s() throws {
    print("makeMP4s()")
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
            print("\(mp4Full.path) exists; skipping")
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
            print("running \(processF)")
            try processF.run()
            print("running \(processS)")
            try processS.run()
        } catch {
            print("Error: \(error)")
            continue
        }

        processF.waitUntilExit()
        processS.waitUntilExit()

        try fileHandle.truncate(atOffset: 0)

        for dir in dirs {
            do {
                try removeDir(dir: dir)
            } catch {
                print("Error: failed to remove dir \(dir.path): \(error)")
            }
        }

        print("made \(key).mp4")
    }
    // TODO use defer
    try fileHandle.close()
    try FileManager.default.removeItem(at: tempFile)
    print("end makeMP4s()")
}

// NOTE takes a moment to update
func isDeviceOnPower() -> Bool {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let type = IOPSGetProvidingPowerSourceType(snapshot)
    guard let type = type else {
        return false
    }
    let type2 = type.takeRetainedValue() as String
    return type2 == kIOPSACPowerValue
}

let loop = IOPSNotificationCreateRunLoopSource({ _ in
    isOnPower = isDeviceOnPower()

    if isOnPower && !isProcessing {
        isProcessing = true
        do {
            try makeMP4s()
        } catch {
            print("Error: \(error)")
        }
        isProcessing = false
    }
}, nil).takeRetainedValue() as CFRunLoopSource
CFRunLoopAddSource(CFRunLoopGetCurrent(), loop, .defaultMode)

RunLoop.current.run()
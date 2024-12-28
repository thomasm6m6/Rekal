import Foundation
import VisionKit
import AppKit // included for NSImage. alternative? or is this the correct approach?

// FIXME figure out why there are discrepancies between the file index as calculated by this implementation vs process.py

let rootDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ss")
let imgDir = rootDir.appendingPathComponent("img")
let fullDir = rootDir.appendingPathComponent("full")
let smallDir = rootDir.appendingPathComponent("small")

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

func encode(blockLength: TimeInterval) throws -> [Int: [URL]] {
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
        if now - timestamp < Int(blockLength) {
            continue
        }

        let block = (timestamp / Int(blockLength)) * Int(blockLength)
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

func makeMP4s() throws {
    let files = try encode(blockLength: 300)

    for (key, dirs) in files {
        let mp4Full = fullDir.appendingPathComponent("\(key).mp4")
        let mp4Small = smallDir.appendingPathComponent("\(key).mp4")

        if FileManager.default.fileExists(atPath: mp4Full.path) {
            print("\(mp4Full.path) exists; skipping")
            continue
        }

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var concatContent = ""
        for dir in dirs {
            concatContent += "file '\(dir.appendingPathComponent("image.png").path)'\nduration 1.0\n"
        }
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

        try processF.run()
        try processS.run()

        processF.waitUntilExit()
        processS.waitUntilExit()

        // TODO truncate instead of removing entirely
        try FileManager.default.removeItem(at: tempFile)

        print("made \(key).mp4")
    }
}

do {
    try makeMP4s()
} catch {
    print("Error: \(error)")
}
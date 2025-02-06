import Foundation
import CoreGraphics
import ImageIO

// TODO: shared instance, maybe actor
class Logger {
    private let fileURL = URL(fileURLWithPath: "/tmp/a.log")
    private var fileHandle: FileHandle

    init() throws {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try "".write(to: fileURL, atomically: false, encoding: .utf8)
        }
        fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle.seekToEndOfFile()
    }

    deinit {
        fileHandle.closeFile()
    }

    func log(_ string: String) {
        let message = "\(Date.now)\t\(string)\n"

        print(message, terminator: "")

        if let data = message.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
}

struct QueryOptions {
    var fullText: Bool
}

struct Query: Codable {
    let minTimestamp: Int
    let maxTimestamp: Int
    let terms: [String]

    // Default Query gets all images for the current day, in local timezone
    init() {
        let today = Int(Calendar.current.startOfDay(for: Date.now).timeIntervalSince1970)

        minTimestamp = today
        maxTimestamp = today + 60 * 60 * 24
        terms = []
    }

    // TODO: parse
    init(text: String, options: QueryOptions) {
        let today = Int(Calendar.current.startOfDay(for: Date.now).timeIntervalSince1970)

        minTimestamp = today
        maxTimestamp = today + 60 * 60 * 24
        terms = []
    }
}

struct SnapshotInfo: Codable, Sendable {
    let windowId: Int
    let rect: CGRect
    var windowName: String?
    var appId: String?
    var appName: String?
    var url: String?

    init(
        windowId: Int, rect: CGRect, windowName: String? = nil, appId: String? = nil,
        appName: String? = nil, url: String? = nil
    ) {
        self.windowId = windowId
        self.rect = rect
        self.windowName = windowName
        self.appId = appId
        self.appName = appName
        self.url = url
    }
}

struct Snapshot: Sendable {
    var image: CGImage?
    let timestamp: Int
    let info: SnapshotInfo
    let pHash: String
    var ocrData: String?

    init(image: CGImage?, timestamp: Int, info: SnapshotInfo, pHash: String, ocrData: String? = nil) {
        self.image = image
        self.timestamp = timestamp
        self.info = info
        self.pHash = pHash
        self.ocrData = ocrData
    }
}

struct EncodedSnapshot: Codable {
    var data: Data?
    let timestamp: Int
    let info: SnapshotInfo
    let pHash: String
    let ocrData: String?

    init(data: Data?, timestamp: Int, info: SnapshotInfo, pHash: String, ocrData: String? = nil) {
        self.data = data
        self.timestamp = timestamp
        self.info = info
        self.pHash = pHash
        self.ocrData = ocrData
    }
}

extension CGImage {
    var png: Data? {
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}

import Foundation
import CoreGraphics
import ImageIO
import Vision
internal import SQLite

struct XPCRequest: Codable {
    let messageType: MessageType
}

struct XPCResponse: Codable {
    let reply: Reply
}

enum MessageType: Codable {
    case fetchImages
    case controlCommand(Command)
    case statusQuery(Query)
}

enum Command: Codable {
    case startRecording
    case pauseRecording
    case processImages
}

enum Query: Codable {
    case imageCount
    case recordingStatus
}

enum Reply: Codable {
    case snapshots([EncodedSnapshot])
    case status(Status)
    case imageCount(Int)
    case error(String)
}

enum Status: Codable {
    case recording
    case stopped
}

struct SnapshotInfo: Codable, Sendable {
    let windowId: Int
    let rect: CGRect
    var windowName = ""
    var appId = ""
    var appName = ""
    var url = ""

    init(
        windowId: Int, rect: CGRect, windowName: String = "", appId: String = "",
        appName: String = "", url: String = ""
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
    var ocrData: String

    init(
        image: CGImage?, timestamp: Int, info: SnapshotInfo, pHash: String, ocrData: String = ""
    ) {
        self.image = image
        self.timestamp = timestamp
        self.info = info
        self.pHash = pHash
        self.ocrData = ocrData
    }
}

struct EncodedSnapshot: Codable {
    var image: Data?
    let timestamp: Int
    let info: SnapshotInfo
    let pHash: String
    let ocrData: String
    
    init(
        image: CGImage?, timestamp: Int, info: SnapshotInfo, pHash: String, ocrData: String = ""
    ) {
        if let image = image {
            self.image = image.png
        }
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

struct Video: Sendable {
    let timestamp: Int
    // let frameCount: Int
    let url: URL

    init(timestamp: Int, url: URL) {
        self.timestamp = timestamp
        // self.frameCount = frameCount
        self.url = url
    }
}

struct OCRResult: Codable, Identifiable {
    var text: String
    var normalizedRect: CGRect
    var uuid: UUID
    var id: UUID { uuid }

    init(text: String, normalizedRect: CGRect, uuid: UUID) {
        self.text = text
        self.normalizedRect = normalizedRect
        self.uuid = uuid
    }
}

enum OCRError: Error {
    case error(String)
}

func performOCR(on image: CGImage) async throws -> String {
    var request = RecognizeTextRequest()
    request.automaticallyDetectsLanguage = true
    request.usesLanguageCorrection = true
    request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
    request.recognitionLevel = .accurate

    let results = try await request.perform(on: image)
    var data: [OCRResult] = []

    for observation in results {
        data.append(
            OCRResult(
                text: observation.topCandidates(1)[0].string,
                normalizedRect: observation.boundingBox.cgRect,
                uuid: observation.uuid
            ))
    }

    let encoder = JSONEncoder()
    let jsonData = try encoder.encode(data)
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        throw OCRError.error("Cannot encode OCR data as JSON")
    }
    return jsonString
}


func log(_ string: String) {
    print("\(Date())\t\(string)")
}

enum FilesError: Error {
    case nonexistentDirectory(String)
}

// TODO this is probably unsafe/wrong
class Files: @unchecked Sendable {
    var appSupportDir: URL
    var databaseFile: URL

    // TODO rename to "shared"
    // maybe: static let shared = Files()
    static let `default`: Files = {
        do {
            return try Files(
                appSupportDir: Files.getAppSupportDir(),
                databaseFile: Files.getDatabaseFile()
            )
        } catch {
            fatalError("Failed to initialize default Files instance: \(error)")
        }
    }()

    init(appSupportDir: URL, databaseFile: URL) {
        self.appSupportDir = appSupportDir
        self.databaseFile = databaseFile
    }

    static func getAppSupportDir() throws -> URL {
        let bundleIdentifier = "com.thomasm6m6.Rekal"  // TODO bundle.main.bundleIdentifier(?)
        guard
            let dir = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else {
            throw FilesError.nonexistentDirectory(
                "Failed to get location of Application Support directory")
        }
        return dir.appending(path: bundleIdentifier)
    }

    static func getDatabaseFile() throws -> URL {
        let appSupportDir = try self.getAppSupportDir()
        return appSupportDir.appending(path: "db.sqlite3")
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Maybe functions to iterate over mp4s
}

enum DatabaseError: Error {
    case fileError(String)
    case error(String)
}

class Database {
    let db: Connection
    let snapshotTable = Table("snapshots")
    let videoTable = Table("videos")

    let snapshotTimestamp = SQLite.Expression<Int>("timestamp")
    let snapshotWindowID = SQLite.Expression<Int>("window_id")
    let snapshotWindowName = SQLite.Expression<String?>("window_name")
    let snapshotAppID = SQLite.Expression<String?>("app_id")
    let snapshotAppName = SQLite.Expression<String?>("app_name")
    let snapshotURL = SQLite.Expression<String?>("url")
    let snapshotX = SQLite.Expression<Int>("x")
    let snapshotY = SQLite.Expression<Int>("y")
    let snapshotWidth = SQLite.Expression<Int>("width")
    let snapshotHeight = SQLite.Expression<Int>("height")
    let snapshotPHash = SQLite.Expression<String>("p_hash")
    let snapshotOCRData = SQLite.Expression<String>("ocr_data")
    let snapshotVideoTimestamp = SQLite.Expression<Int>("snapshot_video_timestamp")

    let videoTimestamp = SQLite.Expression<Int>("timestamp")
    // let videoFrameCount = SQLite.Expression<Int>("frame_count")
    let videoPath = SQLite.Expression<String>("path")

    init() throws {
        let file = Files.default.databaseFile
        if !FileManager.default.fileExists(atPath: file.path) {
            guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
                throw DatabaseError.fileError("Failed to create '\(file.path)'")
            }
        }

        db = try Connection(file.path)
        try createSnapshotTable()
        try createVideoTable()
    }

    func createSnapshotTable() throws {
        try db.run(
            snapshotTable.create(ifNotExists: true) { t in
                t.column(snapshotTimestamp, primaryKey: true)
                t.column(snapshotWindowID)
                t.column(snapshotWindowName)
                t.column(snapshotAppID)
                t.column(snapshotAppName)
                t.column(snapshotURL)
                t.column(snapshotX)
                t.column(snapshotY)
                t.column(snapshotWidth)
                t.column(snapshotHeight)
                t.column(snapshotPHash)
                t.column(snapshotOCRData)
                t.column(snapshotVideoTimestamp, references: videoTable, videoTimestamp)
            })
    }

    func createVideoTable() throws {
        try db.run(
            videoTable.create(ifNotExists: true) { t in
                t.column(videoTimestamp, primaryKey: true)
                // t.column(videoFrameCount)
                t.column(videoPath, unique: true)
            })
    }

    func insertSnapshot(_ snapshot: Snapshot, videoTimestamp: Int) throws {
        try db.run(
            snapshotTable.insert(
                snapshotTimestamp <- snapshot.timestamp,
                snapshotWindowID <- snapshot.info.windowId,
                snapshotWindowName <- snapshot.info.windowName,
                snapshotAppID <- snapshot.info.appId,
                snapshotAppName <- snapshot.info.appName,
                snapshotURL <- snapshot.info.url,
                snapshotX <- Int(snapshot.info.rect.minX),
                snapshotY <- Int(snapshot.info.rect.minY),
                snapshotWidth <- Int(snapshot.info.rect.width),
                snapshotHeight <- Int(snapshot.info.rect.height),
                snapshotPHash <- snapshot.pHash,
                snapshotOCRData <- snapshot.ocrData,
                snapshotVideoTimestamp <- videoTimestamp
            ))
    }

    func insertVideo(_ video: Video) throws {
        try db.run(
            videoTable.insert(
                videoTimestamp <- video.timestamp,
                // videoFrameCount <- video.frameCount,
                videoPath <- video.url.path
            ))
    }

    func videosBetween(minTime: Int, maxTime: Int) throws -> [Video] {
        var videos: [Video] = []
        let query = videoTable.filter(videoTimestamp >= minTime && videoTimestamp < maxTime)
        for row in try db.prepare(query) {
            videos.append(
                Video(
                    timestamp: row[videoTimestamp],
                    // frameCount: row[videoFrameCount],
                    url: URL(filePath: row[videoPath])
                ))
        }
        return videos
    }

    func snapshotsInVideo(videoTimestamp: Int) throws -> [Snapshot] {
        var snapshots: [Snapshot] = []
        let query = snapshotTable.filter(snapshotVideoTimestamp == videoTimestamp)
        for row in try db.prepare(query) {
            let info = SnapshotInfo(
                windowId: row[snapshotWindowID],
                rect: CGRect(
                    x: row[snapshotX], y: row[snapshotY], width: row[snapshotWidth],
                    height: row[snapshotHeight]),
                windowName: row[snapshotWindowName] ?? "",
                appId: row[snapshotAppID] ?? "",
                appName: row[snapshotAppName] ?? "",
                url: row[snapshotURL] ?? ""
            )
            snapshots.append(
                Snapshot(
                    image: nil,
                    timestamp: row[snapshotTimestamp],
                    info: info,
                    pHash: row[snapshotPHash],
                    ocrData: row[snapshotOCRData]
                ))
        }

        return snapshots
    }
}

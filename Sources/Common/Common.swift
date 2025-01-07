import Foundation
import CoreGraphics
import SQLite

public struct SnapshotInfo: Sendable {
    public let windowId: Int
    public let rect: CGRect
    public var windowName = ""
    public var appId = ""
    public var appName = ""
    public var url = ""

    public init(windowId: Int, rect: CGRect, windowName: String = "", appId: String = "", appName: String = "", url: String = "") {
        self.windowId = windowId
        self.rect = rect
        self.windowName = windowName
        self.appId = appId
        self.appName = appName
        self.url = url
    }
}

public struct Snapshot: Sendable {
    public let image: CGImage
    public let timestamp: Int
    public let info: SnapshotInfo
    public let pHash: String
    public var ocrText: String? = nil

    public init(image: CGImage, timestamp: Int, info: SnapshotInfo, pHash: String) {
        self.image = image
        self.timestamp = timestamp
        self.info = info
        self.pHash = pHash
    }
}

public struct Video: Sendable {
    public let timestamp: Int
    // public let frameCount: Int
    public let url: URL

    public init(timestamp: Int, url: URL) {
        self.timestamp = timestamp
        // self.frameCount = frameCount
        self.url = url
    }
}

public func log(_ string: String) {
    print("\(Date())\t\(string)")
}

public enum FilesError: Error {
    case nonexistentDirectory(String)
}

// TODO this is probably unsafe/wrong
public class Files: @unchecked Sendable {
    public var appSupportDir: URL
    public var databaseFile: URL

    public static let `default`: Files = {
        do {
            return try Files(
                appSupportDir: Files.getAppSupportDir(),
                databaseFile: Files.getDatabaseFile()
            )
        } catch {
            fatalError("Failed to initialize default Files instance: \(error)")
        }
    }()

    public init(appSupportDir: URL, databaseFile: URL) {
        self.appSupportDir = appSupportDir
        self.databaseFile = databaseFile
    }

    public static func getAppSupportDir() throws -> URL {
        let bundleIdentifier = "com.example.Rekal" // TODO bundle.main.bundleIdentifier(?)
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw FilesError.nonexistentDirectory("Failed to get location of Application Support directory")
        }
        return dir.appending(path: bundleIdentifier)
    }

    public static func getDatabaseFile() throws -> URL {
        let appSupportDir = try self.getAppSupportDir()
        return appSupportDir.appending(path: "db.sqlite3")
    }

    public static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Maybe functions to iterate over mp4s
}

public enum DatabaseError: Error {
    case fileError(String)
    case error(String)
}

public class Database {
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
    let snapshotOCRText = SQLite.Expression<String>("ocr_text")
    let snapshotVideoTimestamp = SQLite.Expression<Int>("snapshot_video_timestamp")

    let videoTimestamp = SQLite.Expression<Int>("timestamp")
    // let videoFrameCount = SQLite.Expression<Int>("frame_count")
    let videoPath = SQLite.Expression<String>("path")

    public init() throws {
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

    public func createSnapshotTable() throws {
        try db.run(snapshotTable.create(ifNotExists: true) { t in
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
            t.column(snapshotOCRText)
            t.column(snapshotVideoTimestamp, references: videoTable, videoTimestamp)
        })
    }

    public func createVideoTable() throws {
        try db.run(videoTable.create(ifNotExists: true) { t in
            t.column(videoTimestamp, primaryKey: true)
            // t.column(videoFrameCount)
            t.column(videoPath, unique: true)
        })
    }

    public func insertSnapshot(_ snapshot: Snapshot, videoTimestamp: Int) throws {
        try db.run(snapshotTable.insert(
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
            snapshotOCRText <- snapshot.ocrText ?? "",
            snapshotVideoTimestamp <- videoTimestamp
        ))
    }

    public func insertVideo(_ video: Video) throws {
        print(video)
        try db.run(videoTable.insert(
            videoTimestamp <- video.timestamp,
            // videoFrameCount <- video.frameCount,
            videoPath <- video.url.path
        ))
    }

    public func videosBetween(minTime: Int, maxTime: Int) throws -> [Video] {
        var videos: [Video] = []
        let query = videoTable.filter(videoTimestamp >= minTime && videoTimestamp < maxTime)
        for row in try db.prepare(query) {
            videos.append(Video(
                timestamp: row[videoTimestamp],
                // frameCount: row[videoFrameCount],
                url: URL(filePath: row[videoPath])
            ))
        }
        return videos
    }
}
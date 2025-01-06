import Foundation
import CoreGraphics
import SQLite

public struct SnapshotInfo: Sendable {
    public var windowId: Int
    public var rect: CGRect
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
    public var image: CGImage
    public var time: Int
    public var info: SnapshotInfo
    public var ocrText: String?

    public init(image: CGImage, time: Int, info: SnapshotInfo, ocrText: String? = nil) {
        self.image = image
        self.time = time
        self.info = info
        self.ocrText = ocrText
    }
}

public struct Video: Sendable {
    public var timestamp: Int
    public var frameCount: Int
    public var smallURL: URL
    public var largeURL: URL

    public init(timestamp: Int, frameCount: Int, smallURL: URL, largeURL: URL) {
        self.timestamp = timestamp
        self.frameCount = frameCount
        self.smallURL = smallURL
        self.largeURL = largeURL
    }
}

public func log(_ string: String) {
    print("\(Date())\t\(string)")
}

public enum FilesError: Error {
    case nonexistentDirectory(String)
}

// public func getAppSupportDir() throws -> URL {
// let bundleIdentifier = "com.example.Rekal" // TODO bundle.main.bundleIdentifier(?)
// guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
//     throw FilesError.nonexistentDirectory("Failed to get location of Application Support directory")
// }
// let appSupportDir = dir.appending(path: bundleIdentifier)
// return appSupportDir
// }

// public func getDatabaseFile() throws -> URL {
//     let appSupportDir = try getAppSupportDir()
//     return appSupportDir.appending(path: "db.sqlite3")
// }

public class Files {
    public static func appSupportDir() throws -> URL {
        let bundleIdentifier = "com.example.Rekal" // TODO bundle.main.bundleIdentifier(?)
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw FilesError.nonexistentDirectory("Failed to get location of Application Support directory")
        }
        return dir.appending(path: bundleIdentifier)
    }

    public static func databaseFile() throws -> URL {
        let appSupportDir = try self.appSupportDir()
        return appSupportDir.appending(path: "db.sqlite3")
    }

    public static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Maybe functions to iterate over "small" mp4s and "large" mp4s
}

/*
CREATE TABLE snapshots {
timestamp INT PRIMARY KEY,
...
FOREIGN KEY (video_timestamp) REFERENCES videos(timestamp)
}

CREATE TABLE videos {
timestamp INT PRIMARY KEY,
frames INT,
small_file TEXT UNIQUE,
large_file TEXT UNIQUE
}
*/

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
    let snapshotOCRText = SQLite.Expression<String?>("ocr_text")
    let snapshotVideoTimestamp = SQLite.Expression<Int>("snapshotVideoTimestamp")

    let videoTimestamp = SQLite.Expression<Int>("timestamp")
    let videoFrameCount = SQLite.Expression<Int>("frame_count")
    let videoSmallPath = SQLite.Expression<String>("small_file")
    let videoLargePath = SQLite.Expression<String>("large_file")

    public init() throws {
        let file = try Files.databaseFile()
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
            t.column(snapshotOCRText)
            t.column(snapshotVideoTimestamp, references: videoTable, videoTimestamp)
        })
    }

    public func createVideoTable() throws {
        try db.run(videoTable.create(ifNotExists: true) { t in
            t.column(videoTimestamp, primaryKey: true)
            t.column(videoFrameCount)
            t.column(videoSmallPath, unique: true)
            t.column(videoLargePath, unique: true)
        })
    }

    public func insertSnapshot(snapshot: Snapshot) throws {
        try db.run(snapshotTable.insert(
            snapshotTimestamp <- snapshot.time,
            snapshotWindowID <- snapshot.info.windowId,
            snapshotWindowName <- snapshot.info.windowName,
            snapshotAppID <- snapshot.info.appId,
            snapshotAppName <- snapshot.info.appName,
            snapshotURL <- snapshot.info.url,
            snapshotX <- Int(snapshot.info.rect.minX),
            snapshotY <- Int(snapshot.info.rect.minY),
            snapshotWidth <- Int(snapshot.info.rect.width),
            snapshotHeight <- Int(snapshot.info.rect.height),
            snapshotOCRText <- snapshot.ocrText
        ))
    }

    public func insertVideo(video: Video) throws {
        try db.run(videoTable.insert(
            videoTimestamp <- video.timestamp,
            videoFrameCount <- video.frameCount,
            videoSmallPath <- video.smallURL.path,
            videoLargePath <- video.largeURL.path
        ))
    }

    public func videosBetween(minTime: Int, maxTime: Int) throws -> [Video] {
        var videos: [Video] = []
        let query = videoTable.filter(videoTimestamp >= minTime && videoTimestamp < maxTime)
        for row in try db.prepare(query) {
            videos.append(Video(
                timestamp: row[videoTimestamp],
                frameCount: row[videoFrameCount],
                smallURL: URL(filePath: row[videoSmallPath]),
                largeURL: URL(filePath: row[videoLargePath])
            ))
        }
        return videos
    }
}
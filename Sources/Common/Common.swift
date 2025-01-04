import Foundation
import CoreGraphics
import SQLite

public struct RecordInfo: Sendable {
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

public struct Record: Sendable {
    public var image: CGImage
    public var time: Int
    public var info: RecordInfo
    public var ocrText: String?
    public var mp4LargeURL: URL?
    public var mp4SmallURL: URL?

    public init(image: CGImage, time: Int, info: RecordInfo, ocrText: String? = nil, mp4LargeURL: URL? = nil, mp4SmallURL: URL? = nil) {
        self.image = image
        self.time = time
        self.info = info
        self.ocrText = ocrText
        self.mp4LargeURL = mp4LargeURL
        self.mp4SmallURL = mp4SmallURL
    }
}

public func log(_ string: String) {
    print("\(Date())\t\(string)")
}

public enum FilesError: Error {
    case nonexistentDirectory(String)
}

public func getAppSupportDir() throws -> URL {
let bundleIdentifier = "com.example.Rekal" // TODO bundle.main.bundleIdentifier(?)
guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
    throw FilesError.nonexistentDirectory("Failed to get location of Application Support directory")
}
let appSupportDir = dir.appending(path: bundleIdentifier)
return appSupportDir
}

public func getDatabaseFile() throws -> URL {
    let appSupportDir = try getAppSupportDir()
    return appSupportDir.appending(path: "db.sqlite3")
}

public class Files {
    public let appSupportDir: URL
    public let databaseFile: URL

    public init() throws {
        let bundleIdentifier = "com.example.Rekal" // TODO bundle.main.bundleidentifier(?)
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw FilesError.nonexistentDirectory("Failed to get location of Application Support directory")
        }
        appSupportDir = dir.appending(path: bundleIdentifier)

        databaseFile = appSupportDir.appending(path: "db.sqlite3")
    }

    public func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Maybe functions to iterate over "small" mp4s and "large" mp4s
}

public enum DatabaseError: Error {
    case fileError(String)
    case error(String)
}

public class Database {
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

    // public init(files: Files) throws {
    public init() throws {
        let databaseFile = try getDatabaseFile()
        let dbPath = /*files.*/ databaseFile.path
        guard FileManager.default.createFile(atPath: dbPath, contents: nil) else {
            throw DatabaseError.fileError("Failed to create '\(dbPath)'")
        }

        db = try Connection(dbPath)
        try create()
    }

    public func create() throws {
        try db.run(records.create(ifNotExists: true) { t in
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

    public func insert(record: Record) throws {
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
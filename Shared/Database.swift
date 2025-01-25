import Foundation
internal import SQLite

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
    let snapshotOCRData = SQLite.Expression<String?>("ocr_data")
    let snapshotVideoTimestamp = SQLite.Expression<Int>("snapshot_video_timestamp")

    let videoTimestamp = SQLite.Expression<Int>("timestamp")
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
            t.column(snapshotOCRData)
            t.column(snapshotVideoTimestamp, references: videoTable, videoTimestamp)
        })
    }

    func createVideoTable() throws {
        try db.run(videoTable.create(ifNotExists: true) { t in
            t.column(videoTimestamp, primaryKey: true)
            t.column(videoPath, unique: true)
        })
    }

    func insertSnapshot(_ snapshot: Snapshot, videoTimestamp: Int) throws {
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
            snapshotOCRData <- snapshot.ocrData,
            snapshotVideoTimestamp <- videoTimestamp
        ))
    }

    func insertVideo(_ video: Video) throws {
        try db.run(videoTable.insert(
            videoTimestamp <- video.timestamp,
            videoPath <- video.url.path
        ))
    }

    func videosBetween(minTime: Int, maxTime: Int) throws -> VideoList {
        var videos = VideoList()
        let query = videoTable.filter(videoTimestamp >= minTime && videoTimestamp < maxTime)
        for row in try db.prepare(query) {
            let timestamp = row[videoTimestamp]
            videos[timestamp] = Video(
                timestamp: timestamp,
                url: URL(filePath: row[videoPath])
            )
        }
        return videos
    }

    func snapshotsInVideo(videoTimestamp: Int) throws -> SnapshotList {
        var snapshots = SnapshotList()
        let query = snapshotTable.filter(snapshotVideoTimestamp == videoTimestamp)
        for row in try db.prepare(query) {
            let timestamp = row[snapshotTimestamp]
            let info = SnapshotInfo(
                windowId: row[snapshotWindowID],
                rect: CGRect(
                    x: row[snapshotX],
                    y: row[snapshotY],
                    width: row[snapshotWidth],
                    height: row[snapshotHeight]),
                windowName: row[snapshotWindowName],
                appId: row[snapshotAppID],
                appName: row[snapshotAppName],
                url: row[snapshotURL]
            )

            snapshots[timestamp] = Snapshot(
                image: nil,
                timestamp: timestamp,
                info: info,
                pHash: row[snapshotPHash],
                ocrData: row[snapshotOCRData]
            )
        }

        return snapshots
    }

    func getAppList() throws -> ([String], [String]) {
        var appIds: [String] = []
        var appNames: [String] = []
        for row in try db.prepare(snapshotTable) {
            let appId = row[snapshotAppID]
            let appName = row[snapshotAppName]

            guard var appId = appId, var appName = appName else {
                continue
            }
            appId = appId.lowercased()
            appName = appName.lowercased()

            if !appIds.contains(appId) {
                appIds.append(appId)
            }
            if !appNames.contains(appName) {
                appNames.append(appName)
            }
        }

        return (appIds, appNames)
    }
}

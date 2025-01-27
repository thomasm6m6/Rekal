import Foundation
import CoreGraphics
import OrderedCollections

typealias SnapshotList = OrderedDictionary<Int, Snapshot>
typealias VideoList = OrderedDictionary<Int, Video>
typealias EncodedSnapshotList = OrderedDictionary<Int, EncodedSnapshot>

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

struct Video: Sendable {
    let timestamp: Int
    let url: URL

    init(timestamp: Int, url: URL) {
        self.timestamp = timestamp
        self.url = url
    }
}

func log(_ string: String) {
    print("\(Date())\t\(string)")
}

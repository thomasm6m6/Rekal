import Foundation
import AVFoundation
import OrderedCollections

//struct Search {
//    var minTimestamp: Int?
//    var maxTimestamp: Int?
//    var apps: [String]
//    var terms: [String]
//}

//class FrameManager: ObservableObject {
//    // TODO: grok @Published
//    @Published var snapshots = SnapshotList()
//    @Published var videos = VideoList()
//    @Published var index = 0
//    var matchOCR = false
//    var appIds: [String] = []
//    var appNames: [String] = []
//    var urls: [String] = []

    // TODO: consider whether SQL JOIN function would be useful
    // TODO: use sql queries with the parsed query to know when to ignore a video entirely
//    func extractFrames(search searchText: String, options searchOptions: SearchOptions, xpcManager: XPCManager) {
//        var db: Database
//        var getImagesInMemory = false
//
//        snapshots = [:]
//        videos = [:]
//        // TODO: for current date, maybe set index to last image?
//        index = 0
//
//        do {
//            db = try Database()
//        } catch {
//            log("Error connecting to database: \(error)")
//            return
//        }
//
//        let searchText = searchText.lowercased().trimmingCharacters(in: .whitespaces)
//        let search = parseQuery(searchText, database: db)
//
//        let minTimestamp: Int
//        if search.minTimestamp == nil {
//            minTimestamp = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
//            getImagesInMemory = true
//        } else {
//            minTimestamp = search.minTimestamp!
//        }
//
//        let maxTimestamp = search.maxTimestamp ?? minTimestamp + 24 * 60 * 60
//
//        do {
//            videos = try db.videosBetween(minTime: minTimestamp, maxTime: maxTimestamp)
//
//            // TODO: skip as much of this process as possible according to filters
//            for (videoTimestamp, video) in videos {
//                var rawImages: [CGImage] = []
//                let snapshotsInVideo = try db.snapshotsInVideo(videoTimestamp: videoTimestamp)
//
//                let asset = AVURLAsset(url: video.url)
//                let generator = AVAssetImageGenerator(asset: asset)
//                generator.appliesPreferredTrackTransform = true
//                generator.requestedTimeToleranceBefore = .zero
//                generator.requestedTimeToleranceAfter = .zero
//
//                Task {
//                    do {
//                        let duration = try await asset.load(.duration)
//                        let times = stride(from: 1.0, to: duration.seconds, by: 1.0).map {
//                            CMTime(seconds: $0, preferredTimescale: duration.timescale)
//                        }
//
//                        for await result in generator.images(for: times) {
//                            switch result {
//                            case .success(requestedTime: _, let image, actualTime: _):
//                                rawImages.append(image)
//                            case .failure(requestedTime: let requested, let error):
//                                print("Failed to process image at \(requested.seconds) seconds for video '\(video.url.path)': '\(error)'")
//                            }
//                        }
//                    } catch {
//                        print("Error loading video: \(error)")
//                    }
//
//                    guard snapshotsInVideo.count == rawImages.count else {
//                        print("snapshotsInVideo.count (\(snapshotsInVideo.count)) != rawImages.count (\(rawImages.count)) for \(video.url.path)")
//                        return
//                    }
//
//                    // TODO: proper fuzzy search
//                    for (index, image) in rawImages.enumerated() {
//                        let timestamp = snapshotsInVideo.keys[index]
//                        guard var snapshot = snapshotsInVideo[timestamp] else {
//                            continue
//                        }
//                        snapshot.image = image
//
//                        if (search.terms.count == 0 && search.apps.count == 0) || FrameManager.queryMatches(
//                            search: search,
//                            snapshot: snapshot,
//                            options: searchOptions
//                        ) {
//                            Task { @MainActor in
//                                self.snapshots[timestamp] = snapshot
//                            }
//                        }
//                    }
//                }
//            }
//        } catch {
//            log("Error decoding video: \(error)")
//        }
//
//        if !getImagesInMemory {
//            return
//        }
//
//        guard let session = xpcManager.session else {
//            log("No XPC session")
//            return
//        }
//
//        // TODO: fetch all(?) the in-memory images, asynchronously
//        // FIXME: can block indefinitely if sendSync doesn't return
//        //
//        // TODO: break up into small chunks, 10 snapshots or so per request
//        // (if there's actually a reason to? don't think we get parallel
//        // processing bc only one channel)
//
//        let request = XPCRequest(messageType: .fetchImages)
////        try? session.send(request) { _ in }
//
//        do {
//            try session.send(request) { result in
//                switch result {
//                case .success(let response):
//                    do {
//                        let response = try response.decode(as: XPCResponse.self)
////                        DispatchQueue.main.async {
//                            switch response.reply {
//                            case .snapshots(let encodedSnapshots):
//                                let decodedSnapshots = decodeSnapshots(encodedSnapshots)
//                                for (timestamp, snapshot) in decodedSnapshots {
//                                    if self.snapshots[timestamp] == nil {
//                                        self.snapshots[timestamp] = snapshot
//                                    }
//                                }
//                            default:
//                                log("Unrecognized reply: \(response.reply)")
//                            }
////                        }
//                    } catch {
//                        log("Failed to decode reply: \(error)")
//                    }
//                case .failure(let error):
//                    log("XPC error: \(error)")
//                }
//            }
//        } catch {
//            log("Error sending XPC request: \(error)")
//        }
//    }

//    func previousImage() {
//        if index > 0 {
//            index -= 1
//        }
//    }
//
//    func nextImage() {
//        if index < snapshots.count - 1 {
//            index += 1
//        }
//    }

    // TODO: support date being provided on either side of the query string
//    func parseQuery(_ query: String, database: Database) -> Search {
//        let dateRegexStr = #"\d{4}-\d{2}-\d{2}"#
//        let dateRangeRegexStr = "\(dateRegexStr)( to \(dateRegexStr))?"
//
//        var minTimestamp: Int?
//        var maxTimestamp: Int?
//        var apps: [String] = []
//        var terms: [String] = []
//
//        do {
//            let regex = try Regex(dateRangeRegexStr)
//            if let match = try regex.prefixMatch(in: query) {
//                let (startDate, endDate) = parseDate(string: String(match.0))
//                terms = String(query[match.range.upperBound...])
//                    .split(separator: " ").map { String($0) }
//
//                if let startDate = startDate {
//                    minTimestamp = Int(startDate.timeIntervalSince1970)
//                    if let endDate = endDate {
//                        maxTimestamp = Int(endDate.timeIntervalSince1970)
//                    } else {
//                        maxTimestamp = minTimestamp! + 24 * 60 * 60
//                    }
//                }
//            } else {
//                terms = query.split(separator: " ").map { String($0) }
//            }
//        } catch {
//            print("error: \(error)")
//        }
//
//        if appIds.count == 0 && appNames.count == 0 && urls.count == 0 {
//            do {
//                (appIds, appNames, urls) = try database.getAppList()
//            } catch {
//                print("Error getting app list from database: \(error)")
//            }
//        }
//
//        var hostNames: [String] = []
//        for url in urls {
//            if let host = URL(string: url)?.host(percentEncoded: false) {
//                hostNames.append(host)
//            }
//        }
//
//        var newTerms: [String] = []
//        for term in terms {
//            let matchesApp = appIds.contains(term) ||
//                appNames.contains(where: { $0.contains(term) }) ||
//                hostNames.contains(term)
//
//            if matchesApp {
//                apps.append(term)
//            } else {
//                newTerms.append(term)
//            }
//        }
//        terms = newTerms
//
//        return Search(
//            minTimestamp: minTimestamp,
//            maxTimestamp: maxTimestamp,
//            apps: apps,
//            terms: terms
//        )
//    }
//
//    // FIXME: very very bad
//    func parseDate(string: String) -> (Date?, Date?) {
//        let firstYear = Int(String(string[String.Index(utf16Offset: 0, in: string)...String.Index(utf16Offset: 3, in: string)]))!
//        let firstMonth = Int(String(string[String.Index(utf16Offset: 5, in: string)...String.Index(utf16Offset: 6, in: string)]))!
//        let firstDay = Int(String(string[String.Index(utf16Offset: 8, in: string)...String.Index(utf16Offset: 9, in: string)]))!
//
//        var components = DateComponents()
//        components.year = firstYear
//        components.month = firstMonth
//        components.day = firstDay
//        let firstDate = Calendar.current.date(from: components)
//
//        if string.contains(" to ") {
//            let secondYear = Int(String(string[String.Index(utf16Offset: 13, in: string)...String.Index(utf16Offset: 17, in: string)]))!
//            let secondMonth = Int(String(string[String.Index(utf16Offset: 19, in: string)...String.Index(utf16Offset: 20, in: string)]))!
//            let secondDay = Int(String(string[String.Index(utf16Offset: 22, in: string)...String.Index(utf16Offset: 23, in: string)]))!
//
//            components.year = secondYear
//            components.month = secondMonth
//            components.day = secondDay
//            let secondDate = Calendar.current.date(from: components)
//            return (firstDate, secondDate)
//        }
//
//        return (firstDate, nil)
//    }
//
//    // TODO: handle quotes and such
//    // if a value is quoted, don't parse it as a date and do match case(?)
//    static func queryMatches(search: Search, snapshot: Snapshot, options: SearchOptions) -> Bool {
//        let info = snapshot.info
//
//        for app in search.apps {
//            if app == info.appId?.lowercased() {
//                return true
//            } else if info.appName?.lowercased().contains(app) == true {
//                return true
//            }
//        }
//
//        // true if any value of `terms` is a substring of `windowName`
//        if let windowName = info.windowName?.lowercased(),
//           search.terms.contains(where: { windowName.contains($0) })
//        {
//            return true
//        }
//
//        // true if any value of `terms` is a substring of `url`
//        if let url = info.url,
//           let host = URL(string: url)?.host(percentEncoded: false),
//           search.terms.contains(where: { host.contains($0) })
//        {
//            return true
//        }
//
//        if options.fullText,
//           let ocrData = snapshot.ocrData,
//           search.terms.allSatisfy({ ocrData.contains($0) })
//        {
//            return true
//        }
//
//        return false
//    }
//}

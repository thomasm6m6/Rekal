import Foundation
import AVFoundation
import OrderedCollections

struct Search {
    var minTimestamp: Int?
    var maxTimestamp: Int?
    var apps: [String]
    var terms: [String]
}

struct SearchOptions {
    var fullText: Bool
}

@MainActor
class FrameManager: ObservableObject {
    @Published var snapshots = SnapshotList()
    @Published var videos = VideoList()
    @Published var index = 0
    @Published var isProcessing = false
    var matchOCR = false
    private var appIds: [String] = []
    private var appNames: [String] = []

    // TODO consider whether SQL JOIN function would be useful
    // TODO use sql queries with the parsed query to know when to ignore a video entirely
    func extractFrames(search searchText: String, options searchOptions: SearchOptions) {
        var db: Database

        snapshots = [:]
        videos = [:]
        index = 0

        do {
            db = try Database()
        } catch {
            log("Error connecting to database: \(error)")
            return
        }

        let searchText = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let search = parseQuery(searchText, database: db)

        let minTimestamp = search.minTimestamp ??
            Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let maxTimestamp = search.maxTimestamp ?? minTimestamp + 24 * 60 * 60

        Task {
            do {
                let tempDir = try Files.tempDir()
                videos = try db.videosBetween(minTime: minTimestamp, maxTime: maxTimestamp)

                isProcessing = true
                defer {
                    isProcessing = false
                }

                // TODO skip as much of this process as possible according to filters
                for (videoTimestamp, video) in videos {
                    var rawImages: [CGImage] = []
                    let snapshotsInVideo = try db.snapshotsInVideo(videoTimestamp: videoTimestamp)

                    let asset = AVURLAsset(url: video.url)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.requestedTimeToleranceBefore = .zero
                    generator.requestedTimeToleranceAfter = .zero

                    do {
                        let duration = try await asset.load(.duration)
                        let times = stride(from: 1.0, to: duration.seconds, by: 1.0).map {
                            CMTime(seconds: $0, preferredTimescale: duration.timescale)
                        }

                        for await result in generator.images(for: times) {
                            switch result {
                            case .success(requestedTime: _, let image, actualTime: _):
                                rawImages.append(image)
                            case .failure(requestedTime: let requested, let error):
                                print("Failed to process image at \(requested.seconds) seconds for video '\(video.url.path)': '\(error)'")
                            }
                        }
                    } catch {
                        print("Error loading video: \(error)")
                    }

                    guard snapshotsInVideo.count == rawImages.count else {
                        print("snapshotsInVideo.count != rawImages.count for \(video.url.path)")
                        continue
                    }

                    // TODO proper fuzzy search
                    for (index, image) in rawImages.enumerated() {
                        let timestamp = snapshotsInVideo.keys[index]
                        guard var snapshot = snapshotsInVideo[timestamp] else {
                            continue
                        }
                        snapshot.image = image

                        if (search.terms.count == 0 && search.apps.count == 0) || queryMatches(
                            search: search,
                            snapshot: snapshot,
                            options: searchOptions
                        ) {
                            snapshots[timestamp] = snapshot
                        }
                    }
                }
                try FileManager.default.removeItem(at: tempDir)
            } catch {
                print(error)
            }
        }
    }

    func incrementIndex() {
        if index < snapshots.count - 1 {
            index += 1
        }
    }

    func decrementIndex() {
        if index > 0 {
            index -= 1
        }
    }

    func parseQuery(_ query: String, database: Database) -> Search {
        let dateRegexStr = #"\d{4}-\d{2}-\d{2}"#
        let dateRangeRegexStr = "\(dateRegexStr)( to \(dateRegexStr))?"

        var minTimestamp: Int?
        var maxTimestamp: Int?
        var apps: [String] = []
        var terms: [String] = []

        do {
            let regex = try Regex(dateRangeRegexStr)
            if let match = try regex.prefixMatch(in: query) {
                let (startDate, endDate) = parseDate(string: String(match.0))
                terms = String(query[match.range.upperBound...])
                    .split(separator: " ").map { String($0) }

                if let startDate = startDate {
                    minTimestamp = Int(startDate.timeIntervalSince1970)
                    if let endDate = endDate {
                        maxTimestamp = Int(endDate.timeIntervalSince1970)
                    } else {
                        maxTimestamp = minTimestamp! + 24 * 60 * 60
                    }
                }
            } else {
                terms = query.split(separator: " ").map { String($0) }
            }
        } catch {
            print("error: \(error)")
        }

        if appIds.count == 0 && appNames.count == 0 {
            do {
                (appIds, appNames) = try database.getAppList()
            } catch {
                print("Error getting app list from database: \(error)")
            }
        }
        var newTerms: [String] = []
        for term in terms {
            let matchesApp = appIds.contains(term) ||
                appNames.contains(where: { $0.contains(term) })

            if matchesApp {
                apps.append(term)
            } else {
                newTerms.append(term)
            }
        }
        terms = newTerms

        return Search(
            minTimestamp: minTimestamp,
            maxTimestamp: maxTimestamp,
            apps: apps,
            terms: terms
        )
    }

    // FIXME very very bad
    func parseDate(string: String) -> (Date?, Date?) {
        let firstYear = Int(String(string[String.Index(utf16Offset: 0, in: string)...String.Index(utf16Offset: 3, in: string)]))!
        let firstMonth = Int(String(string[String.Index(utf16Offset: 5, in: string)...String.Index(utf16Offset: 6, in: string)]))!
        let firstDay = Int(String(string[String.Index(utf16Offset: 8, in: string)...String.Index(utf16Offset: 9, in: string)]))!

        var components = DateComponents()
        components.year = firstYear
        components.month = firstMonth
        components.day = firstDay
        let firstDate = Calendar.current.date(from: components)

        if string.contains(" to ") {
            let secondYear = Int(String(string[String.Index(utf16Offset: 13, in: string)...String.Index(utf16Offset: 17, in: string)]))!
            let secondMonth = Int(String(string[String.Index(utf16Offset: 19, in: string)...String.Index(utf16Offset: 20, in: string)]))!
            let secondDay = Int(String(string[String.Index(utf16Offset: 22, in: string)...String.Index(utf16Offset: 23, in: string)]))!

            components.year = secondYear
            components.month = secondMonth
            components.day = secondDay
            let secondDate = Calendar.current.date(from: components)
            return (firstDate, secondDate)
        }

        return (firstDate, nil)
    }

    // TODO handle quotes and such
    // if a value is quoted, don't parse it as a date and do match case(?)
    func queryMatches(search: Search, snapshot: Snapshot, options: SearchOptions) -> Bool {
        let info = snapshot.info
        
        for app in search.apps {
            if let appId = info.appId, app == appId.lowercased() {
                return true
            } else if let appName = info.appName, appName.lowercased().contains(app) {
                return true
            }
        }

        if let windowName = info.windowName {
            let windowName = windowName.lowercased()

            // true if any value of `terms` is a substring of `windowName`
            if search.terms.contains(where: { windowName.contains($0) }) {
                return true
            }
        }

        if let urlString = info.url,
           let url = URL(string: urlString),
           let host = url.host(percentEncoded: false)
        {
            // true if any value of `terms` is a substring of `url`
            if search.terms.contains(where: { host.contains($0) }) {
                return true
            }
        }

        if options.fullText, let ocrData = snapshot.ocrData {
            if search.terms.allSatisfy({ ocrData.contains($0) }) {
                return true
            }
        }

        return false
    }
}

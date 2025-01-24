import Foundation
import AVFoundation
import OrderedCollections

struct Search {
    var minTimestamp: Int
    var maxTimestamp: Int
    var terms: [String]
}

@MainActor
class FrameManager: ObservableObject {
    @Published var snapshots = SnapshotList()
    @Published var videos = VideoList()
    @Published var index = 0
    @Published var isProcessing = false
    var matchOCR = false
    
    // TODO consider whether SQL JOIN function would be useful
    func extractFrames(query: String) {
        snapshots = [:]
        videos = [:]
        index = 0

        let query = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard query != "", let search = parseQuery(query) else {
            return
        }

        Task {
            do {
                let db = try Database()
                let tempDir = try Files.tempDir()
                videos = try db.videosBetween(minTime: search.minTimestamp, maxTime: search.maxTimestamp)
                print(search.minTimestamp, search.maxTimestamp, videos.count)

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

                        if search.terms.count == 0 || queryMatches(
                            terms: search.terms,
                            snapshot: snapshot,
                            matchOCR: matchOCR)
                        {
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
    
    func parseQuery(_ query: String) -> Search? {
        let dateRegexStr = #"\d{4}-\d{2}-\d{2}"#
        let dateRangeRegexStr = "\(dateRegexStr)( to \(dateRegexStr))?"

        var startDate: Date?
        var endDate: Date?

        do {
            let regex = try Regex(dateRangeRegexStr)
            if let match = try regex.prefixMatch(in: query) {
                (startDate, endDate) = parseDate(string: String(match.0))
                let terms = String(query[match.range.upperBound...])
                    .split(separator: " ").map { String($0) }

                if let startDate = startDate {
                    let minTimestamp = Int(startDate.timeIntervalSince1970)
                    let maxTimestamp: Int
                    if let endDate = endDate {
                        maxTimestamp = Int(endDate.timeIntervalSince1970)
                    } else {
                        maxTimestamp = minTimestamp + 24 * 60 * 60
                    }
                    return Search(
                        minTimestamp: minTimestamp,
                        maxTimestamp: maxTimestamp,
                        terms: terms
                    )
                }
            }
        } catch {
            print("error: \(error)")
        }

        return nil
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
        
        print(firstDate!)

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
    func queryMatches(terms: [String], snapshot: Snapshot, matchOCR: Bool) -> Bool {
        let info = snapshot.info

        if let appId = info.appId {
            let appId = appId.lowercased()

            if terms.contains(appId) {
                return true
            }

            if let last = appId.split(separator: ".").last,
               terms.contains(String(last).lowercased()) {
                return true
            }
        }

        if let appName = info.appName {
            let appName = appName.lowercased()

            if terms.contains(appName) {
                return true
            }
        }

        if let windowName = info.windowName {
            let windowName = windowName.lowercased()
            
            if terms.contains(where: { windowName.contains($0) }) {
                return true
            }
        }

        if matchOCR, let ocrData = snapshot.ocrData {
            if terms.allSatisfy({ ocrData.contains($0) }) {
                return true
            }
        }

        return false
    }
}

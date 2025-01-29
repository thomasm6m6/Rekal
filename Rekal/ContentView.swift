import SwiftUI
import XPC
import Vision
import AVFoundation

// TODO: make "open rekal" function properly
// TODO: alternative to passing frameManager manually to every custom view?
// TODO: use `public`/`private`/`@Published` correctly
// FIXME: "onChange(of: CGImageRef) action tried to update multiple times per frame"
// TODO: easily noticeable warning (maybe a popup, and/or an exclamation point through the menu bar icon) if the record function throws when it shouldn't
// FIXME: applescript
// TODO: combine frameManager, xpcManager, etc into a ContextManager?
// TODO: search bar doesn't show in overflow menu when window width is small

struct SearchOptions {
    var fullText: Bool
}

struct Search {
    var minTimestamp: Int
    var maxTimestamp: Int
    var terms: [String]

    static func parse(text: String) -> Search {
        let today = Int(Calendar.current.startOfDay(for: Date.now).timeIntervalSince1970)

        let dateRegexStr = #"\d{4}-\d{2}-\d{2}"#
        let dateRangeRegexStr = "\(dateRegexStr)( to \(dateRegexStr))?"

        var minTime: Int?
        var maxTime: Int?
        var termsList: [String] = []

        do {
            let regex = try Regex(dateRangeRegexStr)
            if let match = try regex.prefixMatch(in: text) {
                let (startDate, endDate) = parseDate(string: String(match.0))
                termsList = String(text[match.range.upperBound...])
                    .split(separator: " ").map { String($0) }

                if let startDate = startDate {
                    minTime = Int(startDate.timeIntervalSince1970)
                }

                if let endDate = endDate {
                    maxTime = Int(endDate.timeIntervalSince1970)
                }
            }
        } catch {
            print("Error: \(error)")
        }

        return Search(
            minTimestamp: minTime ?? today,
            maxTimestamp: maxTime ?? (minTime ?? today) + 24 * 60 * 60,
            terms: termsList
        )
    }

    private enum DateError: Error {
        case error(String)
    }

    private static func parseDateNumber(
        _ string: String, _ start: Int, _ end: Int
    ) throws -> Int {
        let start = String.Index(utf16Offset: start, in: string)
        let end = String.Index(utf16Offset: end, in: string)
        guard let result = Int(String(string[start...end])) else {
            throw DateError.error("error: string = \(string[start...end])")
        }
        return result
    }

    // TODO: this is very very bad
    private static func parseDate(string: String) -> (Date?, Date?) {
        do {
            let firstYear = try parseDateNumber(string, 0, 3)
            let firstMonth = try parseDateNumber(string, 5, 6)
            let firstDay = try parseDateNumber(string, 8, 9)

            var components = DateComponents()
            components.year = firstYear
            components.month = firstMonth
            components.day = firstDay
            let firstDate = Calendar.current.date(from: components)

            if string.contains(" to ") {
                let secondYear = try parseDateNumber(string, 14, 17)
                let secondMonth = try parseDateNumber(string, 19, 20)
                let secondDay = try parseDateNumber(string, 22, 23)

                components.year = secondYear
                components.month = secondMonth
                components.day = secondDay
                let secondDate = Calendar.current.date(from: components)
                return (firstDate, secondDate)
            }

            return (firstDate, nil)
        } catch {
            print("Error: \(error)")
            return (nil, nil)
        }
    }
}

struct ContentView: View {
    @FocusState private var isFocused: Bool

    @StateObject private var imageModel = ImageModel()

    private let backgroundColor = Color(red: 18/256, green: 18/256, blue: 18/256) // #121212

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            // FIXME: clicking outside the imageview (ie in the blank area of the window)
            // makes it unresponsive to arrow keys
            NavigationStack {
                VStack {
                    Spacer()

                    if !imageModel.snapshots.isEmpty,
                       let image = imageModel.snapshots[imageModel.index].image {
                        Group {
                            Image(image, scale: 1.0, label: Text("Screenshot"))
                                .resizable()
                                .scaledToFit()
                        }
                        .padding()
                    } else {
                        Text("No images found")
                    }

                    Spacer()
                }
                .onAppear {
                    imageModel.loadImages()
                    isFocused = true
                }
                .focusable()
                .focused($isFocused)
                .focusEffectDisabled()
                .onKeyPress(.leftArrow) {
                    imageModel.previousImage()
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    imageModel.nextImage()
                    return .handled
                }
            }
            .toolbar {
                Toolbar(imageModel: imageModel)
            }
            .toolbarBackground(backgroundColor)
        }
        .onAppear {
            _ = LaunchManager.registerLoginItem()
            _ = LaunchManager.registerLaunchAgent()
        }
    }
}

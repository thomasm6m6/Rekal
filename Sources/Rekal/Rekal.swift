import SwiftUI
import Foundation
import AVFoundation
import Common

import Vision
import ImageIO

// TODO don't block the UI while loading images
// FIXME Viewer is pretty memory-heavy, e.g. 7.24gb for 4774 files (dec 27)
//       Memory usage continues increasing after it finishes loading images
//       Or maybe it just seems that way because of lazy loading?
// TODO arrow keys and media keys
// TODO export image
// TODO zoom
// TODO slider for granularity using similarity percentage via hashing
// TODO serialize OCR data

// TODO XPC/EventKit
// TODO holding arrow keys scrubs in that direction
// TODO load last 5 minutes of images from memory (via XPC)

// TODO support cmd+c, cmd+a, context menu -> copy

// FIXME changing current image via stepper does not cancel OCR
// FIXME OCR coordinates are messed up in upper left corner of image


// TODO write unprocessed images to disk on quit
// let signalQueue = DispatchQueue(label: "signal-handler")

// let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
// let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)

// func handleSignal(_ signal: Int32) {
//     print("Received signal \(signal == SIGINT ? "SIGINT" : "SIGTERM"). Cleaning up...")
//     exit(EXIT_SUCCESS)
// }

// sigintSource.setEventHandler { handleSignal(SIGINT) }
// sigtermSource.setEventHandler { handleSignal(SIGTERM) }

// signal(SIGINT, SIG_IGN)  // Ignore default handling for SIGINT
// signal(SIGTERM, SIG_IGN) // Ignore default handling for SIGTERM
// sigintSource.resume()
// sigtermSource.resume()


@MainActor
class VideoFrameManager: ObservableObject {
    @Published var snapshots: [Snapshot] = []
    @Published var videos: [Video] = []
    @Published var index = 0
    @Published var isProcessing = false

    // TODO consider whether SQL JOIN function would be useful
    func extractFrames(date: Date, search: String = "") {
        snapshots = []
        videos = []
        index = 0

        let minTimestamp = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        let maxTimestamp = minTimestamp + 86400

        do {
            let db = try Database()
            let tempDir = try Files.tempDir()
            videos = try db.videosBetween(minTime: minTimestamp, maxTime: maxTimestamp)

            Task {
                isProcessing = true
                // TODO skip as much of this process as possible according to filters
                for video in videos {
                    var rawImages: [CGImage] = []
                    var videoSnapshots = try db.snapshotsInVideo(videoTimestamp: video.timestamp)

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
                            case .success(requestedTime: _, image: let image, actualTime: _):
                                rawImages.append(image)
                            case .failure(requestedTime: let requested, error: let error):
                                print("Failed to process image at \(requested.seconds) seconds for video '\(video.url.path)': '\(error)'")
                            }
                        }
                    } catch {
                        print("Error loading video: \(error)")
                    }

                    guard videoSnapshots.count == rawImages.count else {
                        print("videoSnapshots.count != rawImages.count for \(video.url.path)")
                        continue
                    }

                    // TODO proper fuzzy search
                    for (index, _) in rawImages.enumerated() {
                        videoSnapshots[index].image = rawImages[index]
                        let trimmedSearch = search.lowercased().trimmingCharacters(in: .whitespaces)
                        if trimmedSearch == "" {
                            snapshots.append(videoSnapshots[index])
                            continue
                        }

                        let info = videoSnapshots[index].info
                        if trimmedSearch == info.appId.lowercased() {
                            snapshots.append(videoSnapshots[index])
                            continue
                        }

                        if let name = info.appId.split(separator: ".").last, trimmedSearch == name.lowercased() {
                            snapshots.append(videoSnapshots[index])
                            continue
                        }

                        if trimmedSearch == info.appName.lowercased().trimmingCharacters(in: .whitespaces) {
                            snapshots.append(videoSnapshots[index])
                            continue
                        }
                    }
                }
                isProcessing = false
                try FileManager.default.removeItem(at: tempDir)
            }
        } catch {
            print(error)
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
}

enum OCRError: Error {
    case error(String)
}

@Observable
class OCR {
    var data: [OCRResult] = []
    var json: String? = nil
    var request = RecognizeTextRequest()

    @MainActor
    func performOCR(on snapshot: Snapshot) async throws {
        guard let image = snapshot.image else {
            throw OCRError.error("No image")
        }

        data.removeAll()

        request.usesLanguageCorrection = false
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.recognitionLevel = .accurate

        let results = try await request.perform(on: image)

        for observation in results {
            let text = observation.topCandidates(1)[0].string
            let rect = observation.boundingBox.cgRect
            data.append(OCRResult(
                text: text,
                x: Float(rect.minX),
                y: Float(rect.minY),
                width: Float(rect.width),
                height: Float(rect.height),
                uuid: observation.uuid
            ))
        }

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            json = jsonString
            // print("Encoded JSON string:", jsonString)
        }

        try decode()
        print(data)
    }

    func decode() throws {
        guard let json = json, let jsonData = json.data(using: .utf8) else {
            throw OCRError.error("Cannot decode json")
        }
        let decoder = JSONDecoder()
        let results = try decoder.decode([OCRResult].self, from: jsonData)
        data = results
    }
}

struct MainView: View {
    @StateObject private var frameManager = VideoFrameManager()
    @State private var selectedDate = Date()
    @State private var search = ""
    @Namespace var namespace

    @State var ocrIsRequested = false
    @State private var imageOCR = OCR()

    var body: some View {
        NavigationSplitView {
            VStack {
                DatePicker(
                    "",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()

                HStack {
                    Spacer()

                    TextField("", value: $frameManager.index, formatter: NumberFormatter())
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.body, design: .monospaced))
                        .disabled(frameManager.snapshots.isEmpty)

                    Text("/ \(frameManager.snapshots.count)")
                        .font(.system(.body, design: .monospaced))

                    // FIXME the stepper will happily go out of bounds
                    Stepper(
                        value: $frameManager.index,
                        in: 0...frameManager.snapshots.count,
                        step: 10
                    ) {}
                    .disabled(frameManager.snapshots.isEmpty)
                }
                .padding(.horizontal, 2)

                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)

                Button(action: extractFrames) {
                    Text("Extract frames")
                        .frame(maxWidth: .infinity)
                }

                Button(action: performOCR) {
                    Text("OCR")
                        .frame(maxWidth: .infinity)
                }

                if frameManager.isProcessing {
                    ProgressView("Processing...")
                }

                Spacer()
            }
            .padding(.horizontal, 10)
        } detail: {
            ImageView(frameManager: frameManager, imageOCR: imageOCR)
        }
    }

    func extractFrames() {
        frameManager.extractFrames(date: selectedDate, search: search)
    }

    func performOCR() {
        Task {
            let snapshot = frameManager.snapshots[frameManager.index]
            if snapshot.image != nil {
                try await imageOCR.performOCR(on: snapshot)
            }
        }
    }
}

struct OCRTextView: View {
    @State private var isSelected = false
    @State private var isHovering = false
    @State private var text: String
    // @State private var boundingBox: NormalizedRect
    @State private var x: Float
    @State private var y: Float
    @State private var width: Float
    @State private var height: Float

    init(_ text: String, x: Float, y: Float, width: Float, height: Float) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    // TODO finish
    var body: some View {
        GeometryReader { geometry in
            let boundingBox = NormalizedRect(
                x: CGFloat(x),
                y: CGFloat(y),
                width: CGFloat(width),
                height: CGFloat(height)
            )
            let rect = boundingBox.toImageCoordinates(geometry.size, origin: .upperLeft)
            Rectangle()
                .fill(isHovering ? .green : .blue)
                // .fill(isSelected ? .blue : .clear)
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .onTapGesture(count: 2) {
                    isSelected = true
                    print("double click")
                }
                .onTapGesture(count: 1) {
                    isSelected = false
                    print("single click")
                }
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.iBeam.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
    }
}

struct ImageView: View {
    let frameManager: VideoFrameManager
    var imageOCR: OCR

    @State private var currentIndex = 0
    @State private var isPlaying = false
    @State private var ocrIsRequested = false

    let timer = Timer.publish(every: 0.025, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            if !frameManager.snapshots.isEmpty {
                if let image = frameManager.snapshots[frameManager.index].image {
                    Image(image, scale: 1.0, label: Text("Screenshot"))
                        .resizable()
                        .scaledToFit()
                        .overlay(
                            ForEach(imageOCR.data, id: \.uuid) { result in
                                OCRTextView(result.text,
                                    x: result.x,
                                    y: result.y,
                                    width: result.width,
                                    height: result.height)
                            }
                        )
                } else {
                    Text("Failed to get the image")
                }
            } else {
                Spacer()

                Text("No images to display")
            }

            Spacer()

            HStack {
                Button(action: previousImage) {
                    Image(systemName: "arrow.left")
                }
                .disabled(isPlaying || frameManager.index <= 0)

                Spacer()

                Button(action: { isPlaying.toggle() }) {
                    Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                        .imageScale(.large)
                }
                .disabled(frameManager.snapshots.isEmpty || frameManager.index >= frameManager.snapshots.count - 1)

                Text("\(frameManager.snapshots.count == 0 ? 0 : frameManager.index+1)/\(frameManager.snapshots.count) frames")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: nextImage) {
                    Image(systemName: "arrow.right")
                }
                .disabled(isPlaying || frameManager.index >= frameManager.snapshots.count - 1)
            }
            .padding()
        }
        .onReceive(timer) { _ in
            if isPlaying {
                nextImage()
            }
        }
    }

    private func nextImage() {
        imageOCR.data.removeAll()
        frameManager.incrementIndex()
        if frameManager.index == frameManager.snapshots.count - 1 && isPlaying {
            isPlaying = false
        }
    }

    private func previousImage() {
        imageOCR.data.removeAll()
        frameManager.decrementIndex()
    }
}

@main
struct Rekal: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
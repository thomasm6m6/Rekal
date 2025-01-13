import SwiftUI
import Foundation
import AVFoundation
import Common

import Vision
import ImageIO

// TODO don't block the UI while loading images
// TODO load full images
// FIXME Viewer is pretty memory-heavy, e.g. 7.24gb for 4774 files (dec 27)
//       Memory usage continues increasing after it finishes loading images
//       Or maybe it just seems that way because of lazy loading?
// TODO arrow keys and media keys
// TODO export image
// TODO zoom
// TODO slider for granularity using similarity percentage via hashing

// TODO XPC/EventKit
// TODO menu bar icon to pause/resume recording
// TODO button to force processing regardless of battery state
// TODO holding arrow buttons scrubs in that direction


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
    @Published var images: [CGImage] = []
    @Published var videos: [Video] = []
    @Published var index = 0
    @Published var isProcessing = false

    // TODO consider whether SQL JOIN function would be useful
    func extractFrames(date: Date) {
        images = []
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
                for video in videos {
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
                                self.images.append(image)
                            case .failure(requestedTime: let requested, error: let error):
                                print("Failed to process image at \(requested.seconds) seconds for video '\(video.url.path)': '\(error)'")
                            }
                        }
                    } catch {
                        print("Error loading video: \(error)")
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
        if index < images.count - 1 {
            index += 1
        }
    }

    func decrementIndex() {
        if index > 0 {
            index -= 1
        }
    }

    // func performOCR() {
    //     let request = RecognizeTextRequest()

    //     Task {
    //         let result = try await request.perform(on: URL(filePath: "/tmp/a.png"), orientation: nil)

    //         for observation in result {
    //             let text = observation.topCandidates(1)[0]
    //             print(text.string)
    //             // let bbox = [
    //             //     (round(observation.topLeft.x*10)/10, round(observation.topLeft.y*10)/10),
    //             //     (round(observation.topRight.x*10)/10, round(observation.topRight.y*10)/10),
    //             //     (round(observation.bottomRight.x*10)/10, round(observation.bottomRight.y*10)/10),
    //             //     (round(observation.bottomLeft.x*10)/10, round(observation.bottomLeft.y*10)/10)]
    //             // print(bbox, "\t", text.string)
    //         }
    //     }
    // }
}

struct MainView: View {
    @StateObject private var frameManager = VideoFrameManager()
    @State private var selectedDate = Date()
    @Namespace var namespace

    @State private var imageOCR = OCR()

    var body: some View {
        NavigationSplitView {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)

                Button("Extract Frames") {
                    frameManager.extractFrames(date: selectedDate)
                }
                .disabled(frameManager.isProcessing)

                Button("OCR") {
                    Task { try await imageOCR.performOCR() }
                }

                if frameManager.isProcessing {
                    ProgressView("Processing...")
                }

                Spacer()
            }
        } detail: {
            ImageView(frameManager: frameManager, imageOCR: imageOCR)
        }
    }
}

@Observable
class OCR {
    var observations = [RecognizedTextObservation]()

    var request = RecognizeTextRequest()

    @MainActor
    func performOCR() async throws {
        request.usesLanguageCorrection = false
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.recognitionLevel = .accurate

        observations.removeAll()

        let url = URL(filePath: "/tmp/a.png")
        let results = try await request.perform(on: url)

        for observation in results {
            observations.append(observation)
            print(observation.topLeft.x, observation.topLeft.y, observation.topCandidates(1)[0].string)
        }
    }
}

// struct Box: Shape {
//     private let normalizedRect: NormalizedRect

//     init(observation: any BoundingBoxProviding) {
//         normalizedRect = observation.boundingBox
//     }

//     func path(in rect: CGRect, content: String) -> Text {
//         // let rect = normalizedRect.toImageCoordinates(rect.size, origin: .upperLeft)
//         return Text(content)
//             .offset(x: rect.minX, y: rect.minY)
//             .frame(width: rect.width, height: rect.height)
//     }
// }

func loadCGImage() -> CGImage? {
    let url = URL(filePath: "/tmp/a.png")
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        print("uhoh")
        return nil
    }

    let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)

    if cgImage == nil {
        print("failed")
    }

    return cgImage
}

struct OCRTextView: View {
    @State private var text: String
    @State private var x: CGFloat
    @State private var y: CGFloat
    @State private var width: CGFloat
    @State private var height: CGFloat

    init(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var body: some View {
        Text(text)
            .background(.red)
            .textSelection(.enabled)
            .lineLimit(1)
            .minimumScaleFactor(0.01)
            .frame(width: width, height: height)
            .position(x: x, y: y)
    }
}

struct ObservationsOverlay: View {
    let observations: [RecognizedTextObservation]
    let geometrySize: CGSize

    init(observations: [RecognizedTextObservation], geometrySize: CGSize) {
        self.observations = observations
        self.geometrySize = geometrySize
        print(geometrySize)
    }

    var body: some View {
        ForEach(observations, id: \.uuid) { observation in
            let text = observation.topCandidates(1)[0].string
            let rect = observation.boundingBox.toImageCoordinates(geometrySize, origin: .upperLeft)

            OCRTextView(text, x: rect.midX, y: rect.midY, width: rect.width, height: rect.height)
        }
    }
}

struct ImageView: View {
    let frameManager: VideoFrameManager
    var imageOCR: OCR

    @State private var currentIndex = 0
    @State private var isPlaying = false
    
    // let timer = Timer.publish(every: 0.025, on: .main, in: .common).autoconnect()

    var body: some View {
        if let image = loadCGImage() {
            Image(image, scale: 1.0, label: Text("a"))
                .resizable()
                .scaledToFit()
                .overlay(
                    GeometryReader { geometry in
                        ObservationsOverlay(
                            observations: imageOCR.observations,
                            geometrySize: geometry.size
                        )
                    }
                )
            // GeometryReader { geometry in
            //     Image(image, scale: 1.0, label: Text("A"))
            //         .resizable()
            //         // .scaledToFit()
            //         .aspectRatio(contentMode: .fit)
            //         .overlay {
            //             ObservationsOverlay(
            //                 observations: imageOCR.observations,
            //                 geometrySize: geometry.size
            //             )
            //         }
            //         // .padding()
            // }
        }

        // VStack {
        //     if !frameManager.images.isEmpty {
        //         Image(frameManager.images[frameManager.index], scale: 1.0, label: Text("Screenshot"))
        //             .resizable()
        //             .aspectRatio(contentMode: .fit)
        //             .frame(maxWidth: .infinity, maxHeight: .infinity)
        //     } else {
        //         Spacer()
        //         Text("No images available")
        //     }

        //     Spacer()

        //     HStack {
        //         Button(action: previousImage) {
        //             Image(systemName: "arrow.left")
        //         }
        //         .disabled(isPlaying || frameManager.index <= 0)

        //         Spacer()

        //         Button(action: { isPlaying.toggle() }) {
        //             Image(systemName: isPlaying ? "pause.circle" : "play.circle")
        //                 .imageScale(.large)
        //         }
        //         .disabled(frameManager.images.isEmpty || frameManager.index >= frameManager.images.count - 1)

        //         Text("\(frameManager.images.count == 0 ? 0 : frameManager.index+1)/\(frameManager.images.count) frames")
        //             .font(.system(.body, design: .monospaced))
        //             .foregroundColor(.secondary)

        //         Spacer()

        //         Button(action: nextImage) {
        //             Image(systemName: "arrow.right")
        //         }
        //         .disabled(isPlaying || frameManager.index >= frameManager.images.count - 1)
        //     }
        //     .padding()
        // }
        // .onReceive(timer) { _ in
        //     if isPlaying {
        //         nextImage()
        //     }
        // }
    }

    private func previousImage() {
        frameManager.decrementIndex()
    }

    private func nextImage() {
        frameManager.incrementIndex()
        if frameManager.index == frameManager.images.count - 1 && isPlaying {
            isPlaying = false
        }
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
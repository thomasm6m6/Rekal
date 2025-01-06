import Foundation
import CoreGraphics
@preconcurrency import VisionKit // TODO probably shouldn't use preconcurrency
import AVFoundation
import IOKit.ps
import CoreImage
import Common

enum ProcessingError: Error {
    case imageDestinationCreationFailed(String)
    case error(String)
}

actor Processor {
    private let data: Data
    private let interval: Int
    private let database: Database

    init(data: Data, interval: Int) throws {
        self.data = data
        self.interval = interval

        let appSupportDir = try Files.appSupportDir()
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true, attributes: nil)
        self.database = try Database()
    }

    func process() async throws {
        try await saveRecords()
    }

    // FIXME small and large MP4s are the same size and I think same resolution
    private func saveRecords() async throws {
        // TODO probably shouldn't copy the records since that's a lot of data.
        // references? indices? pointers?

        if !isOnPower() {
            log("Device is using battery power; delaying processing")
            return
        }

        var snapshotList: [Int: [Snapshot]] = [:]
        let now = Int(Date().timeIntervalSince1970)

        print(await data.get())
        for snapshot in await data.get() {
            if now - snapshot.time > interval {
                break
            }
            let time = snapshot.time / interval * interval
            snapshotList[time, default: []].append(snapshot)
        }

        for (timestamp, var snapshots) in snapshotList {
            if !isOnPower() {
                log("Device is using battery power; delaying processing")
                break
            }
            log("Processing for \(timestamp)")

            let appSupportDir = try Files.appSupportDir()
            let videoLargeURL = appSupportDir.appending(path: "\(timestamp)-large.mp4")
            let videoSmallURL = appSupportDir.appending(path: "\(timestamp)-small.mp4")

            for (index, _) in snapshots.enumerated() {
                snapshots[index].ocrText = try await performOCR(image: snapshots[index].image)
            }

            let snapshotsSmall = snapshots
            for var snapshot in snapshotsSmall {
                guard let image = resize480p(snapshot.image) else {
                    throw ProcessingError.error("Resizing images failed")
                }
                snapshot.image = image
            }

            let video = Video(timestamp: timestamp, frameCount: snapshots.count,
                smallURL: videoSmallURL, largeURL: videoLargeURL)

            try await encodeMP4(snapshots: snapshotsSmall, outputURL: videoSmallURL)
            try await encodeMP4(snapshots: snapshots, outputURL: videoLargeURL)

            try database.insertVideo(video: video)
            for snapshot in snapshots {
                try database.insertSnapshot(snapshot: snapshot)
            }

            // TODO abomination
            for snapshot in snapshots {
                for (index, _) in await data.get().enumerated() {
                    let time = await data.get(at: index).time
                    if time == snapshot.time {
                        await data.remove(at: index)
                        break
                    }
                }
            }

            log("Created \(timestamp).mp4")
        }
    }

    private func resize480p(_ image: CGImage) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let aspectRatio = width / height

        let newHeight: CGFloat = 480
        let newWidth = newHeight * aspectRatio
        let newSize = CGSize(width: newWidth, height: newHeight)

        guard let colorSpace = image.colorSpace,
                let context = CGContext(
                    data: nil,
                    width: Int(newWidth),
                    height: Int(newHeight),
                    bitsPerComponent: image.bitsPerComponent,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: image.bitmapInfo.rawValue
                ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: newSize))

        return context.makeImage()
    }

    // TODO: see if AVFoundation can be made faster / make smaller files; if not, use ffmpeg (ramdisk, tmpfs, or API)
    private func encodeMP4(snapshots: [Snapshot], outputURL: URL) async throws {
        guard let firstSnapshot = snapshots.first else {
            throw ProcessingError.imageDestinationCreationFailed("No snapshots to encode")
        }

        let width = firstSnapshot.image.width
        let height = firstSnapshot.image.height

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for (index, snapshot) in snapshots.enumerated() {
            let time = CMTime(value: CMTimeValue(index), timescale: 1)
            while !input.isReadyForMoreMediaData {
                await Task.yield()
            }

            var pixelBuffer: CVPixelBuffer?
            let options: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, options as CFDictionary, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                throw ProcessingError.imageDestinationCreationFailed("Failed to create pixel buffer")
            }

            let context = CIContext()
            let ciImage = CIImage(cgImage: snapshot.image)
            context.render(ciImage, to: buffer)

            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()
        await writer.finishWriting()
    }

    private func performOCR(image: CGImage) async throws -> String? {
        let analyzer = ImageAnalyzer()
        let config = ImageAnalyzer.Configuration([.text])

        let analysis = try await analyzer.analyze(image, orientation: .right, configuration: config)
        return analysis.transcript
    }

    private func isOnPower() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(snapshot)
        guard let type = type else {
            return false // TODO maybe throw
        }
        let type2 = type.takeRetainedValue() as String
        return type2 == kIOPSACPowerValue
    }
}
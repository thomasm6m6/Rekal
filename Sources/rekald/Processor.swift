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

        try FileManager.default.createDirectory(at: Files.default.appSupportDir, withIntermediateDirectories: true, attributes: nil)
        self.database = try Database()
    }

    func process() async throws {
        try await saveRecords()
    }

    private func saveRecords() async throws {
        // TODO probably shouldn't copy the records since that's a lot of data.
        // references? indices? pointers?

        if !isOnPower() {
            log("Device is using battery power; delaying processing")
            return
        }

        var snapshotList: [Int: [Snapshot]] = [:]
        let now = Int(Date().timeIntervalSince1970)

        let imgs = await data.get()
        print(imgs.count)
        for snapshot in await data.get() {
            if now - snapshot.timestamp < interval {
                break
            }
            let timestamp = snapshot.timestamp / interval * interval
            snapshotList[timestamp, default: []].append(snapshot)
        }
        print(snapshotList)

        for (timestamp, var snapshots) in snapshotList {
            if !isOnPower() {
                log("Device is using battery power; delaying processing")
                break
            }
            log("Processing for \(timestamp)")

            let videoURL = Files.default.appSupportDir.appending(path: "\(timestamp).mp4")

            for (index, _) in snapshots.enumerated() {
                snapshots[index].ocrText = try await performOCR(image: snapshots[index].image)
            }

            try await encodeMP4(snapshots: snapshots, outputURL: videoURL)

            let video = Video(timestamp: timestamp, frameCount: snapshots.count, url: videoURL)

            try database.insertVideo(video: video)
            for snapshot in snapshots {
                try database.insertSnapshot(snapshot: snapshot)
            }

            // TODO abomination
            for snapshot in snapshots {
                for (index, _) in await data.get().enumerated() {
                    let timestamp = await data.get(at: index).timestamp
                    if timestamp == snapshot.timestamp {
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

    // FFmpeg with HEVC or AV1, using ramdisk or API+FFI
    // or: AVFoundation with HEVC (or maybe AV1?)
    private func encodeMP4(snapshots: [Snapshot], outputURL: URL) async throws {
        guard let firstSnapshot = snapshots.first else {
            throw ProcessingError.imageDestinationCreationFailed("No snapshots to encode")
        }

        let width = firstSnapshot.image.width
        let height = firstSnapshot.image.height

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        // let settings = AVOutputSettingsPreset.hevc1920x1080
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
            // AVVideoCompressionPropertiesKey: [
            //     AVVideoAverageBitRateKey: 1_000_000,
            //     AVVideoQualityKey: 0.5,
            //     AVVideoMaxKeyFrameIntervalKey: 60
            // ]
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
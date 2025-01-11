import Foundation
import CoreGraphics
@preconcurrency import VisionKit // TODO probably shouldn't use preconcurrency
import AVFoundation
import IOKit.ps
import CoreImage
import Common

// TODO proper queue algorithm?
// FIXME only a few images make it into the mp4s
// FIXME seems to fail silently sometimes. need more logging

class MediaWriter {
    let input: AVAssetWriterInput
    let writer: AVAssetWriter
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let url: URL
    var index = 0

    init(input: AVAssetWriterInput, writer: AVAssetWriter, adaptor: AVAssetWriterInputPixelBufferAdaptor, url: URL) {
        self.input = input
        self.writer = writer
        self.adaptor = adaptor
        self.url = url
    }
}

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
        let snapshots = await data.get()
        let appSupportDir = Files.default.appSupportDir
        let now = Int(Date().timeIntervalSince1970)
        let maxTimestamp = now / interval * interval

        log("Processing \(snapshots.count) snapshots...")

        guard isOnPower() else {
            log("Device is using battery power; delaying processing")
            return
        }

        guard let firstSnapshot = snapshots.values.first else {
            log("No snapshots to encode")
            return
        }

        let height = firstSnapshot.image.height
        let width = firstSnapshot.image.width
        var mediaWriters: [Int: MediaWriter] = [:]
        let writerSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let bufferOptions: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        for (timestamp, var snapshot) in snapshots {
            let binTimestamp = timestamp / interval * interval
            if binTimestamp >= maxTimestamp {
                continue
            }

            if mediaWriters[binTimestamp] == nil {
                let outputURL = appSupportDir.appending(path: "\(binTimestamp).mp4")
                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                    sourcePixelBufferAttributes: nil)

                writer.add(input)
                writer.startWriting()
                writer.startSession(atSourceTime: .zero)

                mediaWriters[binTimestamp] = MediaWriter(input: input, writer: writer, adaptor: adaptor, url: outputURL)

                let video = Video(timestamp: binTimestamp, url: outputURL)
                try database.insertVideo(video)
            }

            guard let mediaWriter = mediaWriters[binTimestamp] else {
                throw ProcessingError.error("mediaWriters[\(binTimestamp)] does not exist")
            }

            // TODO might be able to use timestamp or something else instead of index
            mediaWriter.index += 1
            let time = CMTime(value: CMTimeValue(mediaWriter.index), timescale: 1)

            while !mediaWriter.input.isReadyForMoreMediaData {
                await Task.yield()
            }

            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                kCVPixelFormatType_32ARGB, bufferOptions as CFDictionary, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                throw ProcessingError.error("Failed to create pixel buffer")
            }

            let context = CIContext()
            let ciImage = CIImage(cgImage: snapshot.image)
            context.render(ciImage, to: buffer)

            mediaWriter.adaptor.append(buffer, withPresentationTime: time)

            snapshot.ocrText = try await performOCR(image: snapshot.image)
            try database.insertSnapshot(snapshot, videoTimestamp: binTimestamp)
            await data.remove(for: timestamp)
        }

        // TODO async
        for mediaWriter in mediaWriters.values {
            mediaWriter.input.markAsFinished()
            await mediaWriter.writer.finishWriting()
            log("Wrote \(mediaWriter.index) frames to \(mediaWriter.url.path)")
        }
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
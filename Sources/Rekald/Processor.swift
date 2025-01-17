import AVFoundation
import Common
import CoreGraphics
import CoreImage
import Foundation
import IOKit.ps
import Vision
@preconcurrency import VisionKit  // TODO probably shouldn't use preconcurrency

// TODO proper queue algorithm?
// TODO layout-aware OCR
// TODO make sure it correctly handles being unplugged mid-processing

// TODO dump files to disk after a certain period of time if we haven't been connected to power

// TODO write video files as soon as they're done, not once all the images have been processed
// (might be that this is already happening, but the "wrote file.mp4" message waits)

// FIXME:
// 2025-01-13 07:32:46 +0000       Skipping: idle
// timestamp: 1736748533
// timestamp: 1736748537
// 2025-01-13 07:32:47 +0000       Skipping: idle
// 2025-01-13 07:32:47 +0000       Processing 270 snapshots...
// timestamp: 1736748537
// 2025-01-13 07:32:47 +0000       Error processing snapshots: UNIQUE constraint failed: videos.timestamp (code: 19)
// timestamp: 1736748542
// timestamp: 1736748544
// 2025-01-13 07:32:48 +0000       Skipping: idle
// timestamp: 1736748548

class MediaWriter {
    let input: AVAssetWriterInput
    let writer: AVAssetWriter
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let url: URL
    var index = 0

    init(
        input: AVAssetWriterInput, writer: AVAssetWriter,
        adaptor: AVAssetWriterInputPixelBufferAdaptor, url: URL
    ) {
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

        try FileManager.default.createDirectory(
            at: Files.default.appSupportDir, withIntermediateDirectories: true, attributes: nil)
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

        guard let firstSnapshot = snapshots.values.first,
            let firstImage = firstSnapshot.image
        else {
            log("No snapshots to encode")
            return
        }

        let height = firstImage.height
        let width = firstImage.width
        var mediaWriters: [Int: MediaWriter] = [:]
        let writerSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let bufferOptions: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]

        for (timestamp, var snapshot) in snapshots {
            guard let image = snapshot.image else {
                throw ProcessingError.error("Cannot get image")
            }
            log("Processing timestamp: \(timestamp)")

            let binTimestamp = timestamp / interval * interval
            if binTimestamp >= maxTimestamp {
                break
            }

            if mediaWriters[binTimestamp] == nil {
                let outputURL = appSupportDir.appending(path: "\(binTimestamp).mp4")
                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: nil)

                writer.add(input)
                writer.startWriting()
                writer.startSession(atSourceTime: .zero)

                mediaWriters[binTimestamp] = MediaWriter(
                    input: input, writer: writer, adaptor: adaptor, url: outputURL)

                let video = Video(timestamp: binTimestamp, url: outputURL)
                try database.insertVideo(video)
            }

            guard let mediaWriter = mediaWriters[binTimestamp] else {
                throw ProcessingError.error("mediaWriters[\(binTimestamp)] does not exist")
            }

            mediaWriter.index += 1
            let time = CMTime(value: CMTimeValue(mediaWriter.index), timescale: 1)

            while !mediaWriter.input.isReadyForMoreMediaData {
                await Task.yield()
            }

            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault, width, height,
                kCVPixelFormatType_32ARGB, bufferOptions as CFDictionary, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                throw ProcessingError.error("Cannot create pixel buffer")
            }

            let context = CIContext()
            let ciImage = CIImage(cgImage: image)
            context.render(ciImage, to: buffer)

            mediaWriter.adaptor.append(buffer, withPresentationTime: time)

            snapshot.ocrData = try await performOCR(on: image)
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

    private func performOCR(on image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.recognitionLevel = .accurate

        let results = try await request.perform(on: image)
        var data: [OCRResult] = []

        for observation in results {
            data.append(
                OCRResult(
                    text: observation.topCandidates(1)[0].string,
                    normalizedRect: observation.boundingBox.cgRect,
                    uuid: observation.uuid
                ))
        }

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ProcessingError.error("Cannot encode OCR data as JSON")
        }
        return jsonString
    }

    private func isOnPower() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(snapshot)
        guard let type = type else {
            return false  // TODO maybe throw
        }
        let type2 = type.takeRetainedValue() as String
        return type2 == kIOPSACPowerValue
    }
}

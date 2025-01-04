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
    // private let files: Files

    init(data: Data, interval: Int /*, files: Files*/) throws {
        self.data = data
        self.interval = interval
        // self.files = files

        // FIXME use files.appSupportDir
        let appSupportDir = try getAppSupportDir()
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true, attributes: nil)
        self.database = try Database(/*files: files*/)
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

        var recordList: [Int: [Record]] = [:]
        let now = Int(Date().timeIntervalSince1970)

        for record in await data.get() {
            if now - record.time > interval {
                break
            }
            let time = record.time / interval * interval
            recordList[time, default: []].append(record)
        }

        for (time, var subrecords) in recordList {
            if !isOnPower() {
                log("Device is using battery power; delaying processing")
                break
            }

            let appSupportDir = try getAppSupportDir()
            let mp4LargeURL = /*files.*/ appSupportDir.appending(path: "\(time)-large.mp4")
            let mp4SmallURL = /*files.*/ appSupportDir.appending(path: "\(time)-small.mp4")

            for (index, _) in subrecords.enumerated() {
                subrecords[index].ocrText = try await performOCR(image: subrecords[index].image)
                subrecords[index].mp4LargeURL = mp4LargeURL
                subrecords[index].mp4SmallURL = mp4SmallURL
            }

            let subrecordsSmall = subrecords
            for var record in subrecordsSmall {
                guard let image = resize480p(record.image) else {
                    throw ProcessingError.error("Resizing images failed")
                }
                record.image = image
            }

            try await encodeMP4(records: subrecords, outputURL: mp4LargeURL)
            try await encodeMP4(records: subrecordsSmall, outputURL: mp4SmallURL)

            for record in subrecords {
                try database.insert(record: record)
            }

            // TODO abomination
            for record in subrecords {
                for (index, _) in await data.get().enumerated() {
                    let time = await data.get(at: index).time
                    if time == record.time {
                        await data.remove(at: index)
                        break
                    }
                }
            }

            log("Created \(time).mp4")
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
    private func encodeMP4(records: [Record], outputURL: URL) async throws {
        guard let firstRecord = records.first else {
            throw ProcessingError.imageDestinationCreationFailed("No records to encode")
        }

        let width = firstRecord.image.width
        let height = firstRecord.image.height

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

        for (index, record) in records.enumerated() {
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
            let ciImage = CIImage(cgImage: record.image)
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
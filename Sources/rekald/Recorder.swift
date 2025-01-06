import Foundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit // TODO probably shouldn't use preconcurrency
import Common

enum RecordingError: Error {
    case infoError(String)
}

actor Recorder {
    private let data: Data
    // private let files: Files
    private let interval: TimeInterval
    private var lastSnapshot: Snapshot? = nil

    init(data: Data, interval: TimeInterval /*, files: Files*/) {
        self.data = data
        self.interval = interval
        // self.files = files
    }

    func record() async throws {
        if isIdle() {
            log("Skipping: idle")
            return
        }

        // XXX not sure this code runs the way I expect
        // Expect catch clause, but not guard-else clause, to be run if `capture` throws
        do {
            guard let snapshot = try await capture() else {
                return
            }
            await data.add(snapshot: snapshot)
            log("Saved image")
        } catch {
            log("Did not save image: \(error)")
        }
    }

    private func capture() async throws -> Snapshot? {
        let timestamp = Int(Date().timeIntervalSince1970)
        var info: SnapshotInfo? = nil

        guard let frontmostAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }

        // or SCShareableContent.current(?)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw RecordingError.infoError("No displays found")
        }

        for window in content.windows {
            if let app = window.owningApplication, app.processID == frontmostAppPID {
                info = await getWindowInfo(window: window)
                break
            }
        }
        guard let info = info else {
            // Happens when the focused application has no windows, usually after closing a window
            throw RecordingError.infoError("Failed to get window info")
        }

        // TODO make these configurable via GUI (UserDefaults?)
        let excludedApps: [String] = ["com.apple.FaceTime", "com.apple.Passwords"]
        let excludedURLs: [String] = [] // TODO zoom.us, meet.jit.si, etc

        if info.appId != "" {
            for app in excludedApps {
                if app == info.appId {
                    log("Skipping: active application is on blacklist")
                    return nil
                }
            }
        }
        if info.url != "" {
            for url in excludedURLs {
                if url == info.url {
                    log("Skipping: active URL is on blacklist")
                    return nil
                }
            }
        }

        // TODO exclude apps, and exclude the browser if the active url is blacklisted
        // for the browser, get the specific window id containing blacklisted urls and exclude that window
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        if let lastSnapshot = lastSnapshot, isSimilar(image1: lastSnapshot.image, image2: image) {
            log("Images are similar; skipping")
            return nil
        }

        let snapshot = Snapshot(image: image, time: timestamp, info: info)
        lastSnapshot = snapshot
        return snapshot
    }

    private func getWindowInfo(window: SCWindow) async -> SnapshotInfo {
        var info = SnapshotInfo(windowId: Int(window.windowID), rect: window.frame)

        if let title = window.title {
            info.windowName = title
        }

        if let app = window.owningApplication {
            info.appName = app.applicationName
            info.appId = app.bundleIdentifier

            if app.bundleIdentifier == "com.google.Chrome" {
                if let lastSnapshot = lastSnapshot, window.title == lastSnapshot.info.windowName {
                    info.url = lastSnapshot.info.url
                    return info
                } else if let url = getBrowserURL() {
                    info.url = url
                }
            }
        }

        return info
    }

    private func isIdle() -> Bool {
        let events: [CGEventType] = [
            .keyDown,

            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,

            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,

            .scrollWheel
        ]

        for event in events {
            let time = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: event)
            if time < interval {
                return false
            }
        }
        return true
    }

    private func isSimilar(image1: CGImage, image2: CGImage) -> Bool {
        if let similarity = pHash(image1: image1, image2: image2) {
            return similarity > 0.8
        }
        return false
    }

    private func getBrowserURL() -> String? {
        let script = "tell application \"Google Chrome\" to get URL of active tab of front window"
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if error == nil {
                return output.stringValue
            }
            print("Error getting active URL via AppleScript")
        }
        return nil
    }

    private func pHash(image1: CGImage, image2: CGImage) -> Double? {
        // Size for DCT
        let size = 32
        let hashSize = 8
        
        // Create contexts for downsampling
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let context1 = CGContext(data: nil,
                                    width: size,
                                    height: size,
                                    bitsPerComponent: 8,
                                    bytesPerRow: size,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo.rawValue),
            let context2 = CGContext(data: nil,
                                    width: size,
                                    height: size,
                                    bitsPerComponent: 8,
                                    bytesPerRow: size,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }

        // Draw downsampled grayscale images
        context1.draw(image1, in: CGRect(x: 0, y: 0, width: size, height: size))
        context2.draw(image2, in: CGRect(x: 0, y: 0, width: size, height: size))
        
        guard let pixels1 = context1.data?.assumingMemoryBound(to: UInt8.self),
            let pixels2 = context2.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        // Convert to binary using median as threshold
        var values1 = [UInt8](repeating: 0, count: size * size)
        var values2 = [UInt8](repeating: 0, count: size * size)
        
        // Copy pixels to sort for median
        for i in 0..<(size * size) {
            values1[i] = pixels1[i]
            values2[i] = pixels2[i]
        }
        
        values1.sort()
        values2.sort()
        
        let threshold1 = values1[size * size / 2]
        let threshold2 = values2[size * size / 2]
        
        // Convert to binary
        var binaryPixels1 = [Float](repeating: 0, count: size * size)
        var binaryPixels2 = [Float](repeating: 0, count: size * size)
        
        for i in 0..<(size * size) {
            binaryPixels1[i] = pixels1[i] > threshold1 ? 255 : 0
            binaryPixels2[i] = pixels2[i] > threshold2 ? 255 : 0
        }
        
        // Apply DCT
        var dct1 = [Float](repeating: 0, count: hashSize * hashSize)
        var dct2 = [Float](repeating: 0, count: hashSize * hashSize)
        
        // Calculate DCT and take top-left 8x8
        for y in 0..<hashSize {
            for x in 0..<hashSize {
                var sum1: Float = 0
                var sum2: Float = 0
                
                for i in 0..<size {
                    for j in 0..<size {
                        let cos = cosf(Float.pi * Float(x) * Float(j) / Float(size)) *
                                cosf(Float.pi * Float(y) * Float(i) / Float(size))
                        sum1 += binaryPixels1[i * size + j] * cos
                        sum2 += binaryPixels2[i * size + j] * cos
                    }
                }
                
                dct1[y * hashSize + x] = sum1
                dct2[y * hashSize + x] = sum2
            }
        }
        
        // Calculate average values
        let avg1 = dct1.reduce(0, +) / Float(hashSize * hashSize)
        let avg2 = dct2.reduce(0, +) / Float(hashSize * hashSize)
        
        // Generate hash bits
        var hash1: UInt64 = 0
        var hash2: UInt64 = 0
        
        for i in 0..<(hashSize * hashSize) {
            if dct1[i] > avg1 {
                hash1 |= 1 << i
            }
            if dct2[i] > avg2 {
                hash2 |= 1 << i
            }
        }
        
        // Calculate Hamming distance
        let xorHash = hash1 ^ hash2
        let hammingDistance = xorHash.nonzeroBitCount
        
        // Convert to similarity percentage
        return 1.0 - (Double(hammingDistance) / Double(hashSize * hashSize))
    }
}
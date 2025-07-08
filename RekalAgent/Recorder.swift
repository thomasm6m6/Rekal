import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit  // TODO: probably shouldn't use preconcurrency

// TODO: ignore incognito chrome windows by default
// FIXME:
//   *** Terminating app due to uncaught exception 'NSInternalInconsistencyException',
//   reason: 'NSScreen reconfig must only happen on the main thread.'
// I think it happened when I connected the laptop to power. But definitely not every time I did

enum RecordingError: Error {
  case infoError(String)
}

actor Recorder {
  var isRecording = true
  private let data: SnapshotData
  private let interval: TimeInterval
  private var lastSnapshot: Snapshot? = nil

  init(data: SnapshotData, interval: TimeInterval) {
    self.data = data
    self.interval = interval
  }

  func setRecording(_ status: Bool) {
    log("Setting recording status to \(status)")
    isRecording = status
  }

  func record() async throws {
    if !isRecording {
      return
    }

    if isIdle() {
      log("Skipping: idle")
      return
    }

    do {
      guard let snapshot = try await capture() else {
        return
      }
      data.add(timestamp: snapshot.timestamp, snapshot: snapshot)
      log("Saved image")
    } catch {
      // throw?
      log("Did not save image: \(error)")
    }
  }

  private func capture() async throws -> Snapshot? {
    let timestamp = Int(Date().timeIntervalSince1970)
    var info: SnapshotInfo? = nil

    guard let frontmostAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
      return nil
    }

    // FIXME: one of the following two statements is throwing, *sometimes*. Not sure under what
    // conditions. Oddly, the error does not get printed anywhere.
    // or SCShareableContent.current(?)
    log("a")
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    log("b")
    guard let display = content.displays.first else {
      throw RecordingError.infoError("No displays found")
    }
    log("c")

    for window in content.windows {
      if frontmostAppPID == window.owningApplication?.processID {
        info = await getWindowInfo(window: window)
        break
      }
    }
    guard let info = info else {
      // Happens when the focused application has no windows, usually after closing a window
      throw RecordingError.infoError("Failed to get window info")
    }

    //        log("rect: \(info.rect), display.frame: \(display.frame)")

    // TODO: make these configurable via GUI (UserDefaults?)
    // also private browser windows
    let excludedApps: [String] = [
      "com.apple.FaceTime", "com.apple.Passwords", "com.thomasm6m6.Rekal",
    ]
    let excludedURLs: [String] = []  // TODO: zoom.us, meet.jit.si, chrome://passwords, etc

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

    // TODO: exclude apps, and exclude the browser if the active url is blacklisted
    // for the browser, get the specific window id containing blacklisted urls and
    // exclude that window
    let filter = SCContentFilter(
      display: display,
      excludingApplications: [],
      exceptingWindows: [])

    let config = SCStreamConfiguration()
    config.width = display.width
    config.height = display.height

    let image = try await SCScreenshotManager.captureImage(
      contentFilter: filter, configuration: config)
    guard let hash = pHash(for: image) else {
      log("Skipping: cannot make hash for image")
      return nil
    }
    let snapshot = Snapshot(
      image: image,
      timestamp: timestamp,
      info: info,
      pHash: hash)

    if let lastSnapshot = lastSnapshot,
      isSimilar(snapshot1: snapshot, snapshot2: lastSnapshot)
    {
      log("Skipping: images are similar")
      return nil
    }

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
        if let lastSnapshot = lastSnapshot,
          window.title == lastSnapshot.info.windowName
        {
          log("\(window.title) == \(lastSnapshot.info.windowName)")
          log("url: \(lastSnapshot.info.url)")
          info.url = lastSnapshot.info.url
        } else if let url = getBrowserURL() {
          info.url = url
          log("here")
          log("url: \(info.url)")
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

      .scrollWheel,
    ]

    for event in events {
      let time = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: event)
      if time < interval {
        return false
      }
    }
    return true
  }

  private func getBrowserURL() -> String? {
    let script = "tell application \"Google Chrome\" to get URL of active tab of front window"
    var error: NSDictionary?
    guard let scriptObject = NSAppleScript(source: script) else {
      log("Error constructing AppleScript")
      return nil
    }
    let output = scriptObject.executeAndReturnError(&error)
    if error != nil {
      log("Error executing AppleScript: \(error)")
      return nil
    }
    return output.stringValue
  }

  private func isSimilar(snapshot1: Snapshot, snapshot2: Snapshot) -> Bool {
    guard
      let similarity = computeSimilarityPercentage(hash1: snapshot1.pHash, hash2: snapshot2.pHash)
    else {
      return false
    }
    return similarity >= 90
  }

  func computeSimilarityPercentage(hash1: String, hash2: String) -> Double? {
    guard let hammingDistance = computeSimilarity(hash1: hash1, hash2: hash2) else {
      return nil
    }

    let binaryLength = hexToBinary(hexString: hash1).count
    let similarity = 100.0 * (1.0 - (Double(hammingDistance) / Double(binaryLength)))
    return similarity
  }

  func computeSimilarity(hash1: String, hash2: String) -> Int? {
    guard hash1.count == hash2.count else { return nil }

    let binary1 = hexToBinary(hexString: hash1)
    let binary2 = hexToBinary(hexString: hash2)

    guard binary1.count == binary2.count else { return nil }

    return zip(binary1, binary2).filter { $0 != $1 }.count
  }

  func pHash(for cgImage: CGImage) -> String? {
    let targetSize = CGSize(width: 32, height: 32)
    guard let resizedImage = resizeCGImage(cgImage: cgImage, targetSize: targetSize),
      let grayscaleImage = convertToGrayscale(cgImage: resizedImage),
      let pixelData = getPixelData(from: grayscaleImage, size: targetSize)
    else {
      return nil
    }

    let dctData = computeDCT(pixelData: pixelData, size: targetSize)
    let dctTopLeft = dctData.prefix(64)
    let averageDCT = dctTopLeft.reduce(0, +) / Float(dctTopLeft.count)
    let hash = dctTopLeft.map { $0 > averageDCT ? "1" : "0" }.joined()
    return binaryToHex(binaryString: hash)
  }

  func resizeCGImage(cgImage: CGImage, targetSize: CGSize) -> CGImage? {
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    guard
      let context = CGContext(
        data: nil,
        width: Int(targetSize.width),
        height: Int(targetSize.height),
        bitsPerComponent: cgImage.bitsPerComponent,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue
      )
    else {
      return nil
    }
    context.interpolationQuality = .low
    context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
    return context.makeImage()
  }

  func convertToGrayscale(cgImage: CGImage) -> CGImage? {
    let width = cgImage.width
    let height = cgImage.height
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue)
    context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context?.makeImage()
  }

  func getPixelData(from cgImage: CGImage, size: CGSize) -> [UInt8]? {
    let width = Int(size.width)
    let height = Int(size.height)
    var pixelData = [UInt8](repeating: 0, count: width * height)
    guard
      let context = CGContext(
        data: &pixelData,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else {
      return nil
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixelData
  }

  func computeDCT(pixelData: [UInt8], size: CGSize) -> [Float] {
    let width = Int(size.width)
    let height = Int(size.height)
    var floatData = pixelData.map { Float($0) }

    func dct1D(_ data: [Float]) -> [Float] {
      let N = data.count
      var result = [Float](repeating: 0, count: N)
      let factor = Float.pi / Float(N)
      for k in 0..<N {
        var sum: Float = 0
        for n in 0..<N {
          sum += data[n] * cos(factor * Float(k) * (Float(n) + 0.5))
        }
        result[k] = sum
      }
      return result
    }

    // Perform 2D DCT
    for y in 0..<height {
      let rowStart = y * width
      let row = Array(floatData[rowStart..<(rowStart + width)])
      let transformedRow = dct1D(row)
      floatData.replaceSubrange(rowStart..<(rowStart + width), with: transformedRow)
    }

    for x in 0..<width {
      var column = [Float](repeating: 0, count: height)
      for y in 0..<height {
        column[y] = floatData[y * width + x]
      }
      let transformedColumn = dct1D(column)
      for y in 0..<height {
        floatData[y * width + x] = transformedColumn[y]
      }
    }

    return floatData
  }

  func binaryToHex(binaryString: String) -> String {
    let chunks = stride(from: 0, to: binaryString.count, by: 4).map {
      binaryString.index(
        binaryString.startIndex, offsetBy: $0)..<binaryString.index(
          binaryString.startIndex, offsetBy: min($0 + 4, binaryString.count))
    }
    return chunks.map { String(format: "%X", Int(binaryString[$0], radix: 2)!) }.joined()
  }

  func hexToBinary(hexString: String) -> String {
    let binaryMap = [
      "0": "0000", "1": "0001", "2": "0010", "3": "0011",
      "4": "0100", "5": "0101", "6": "0110", "7": "0111",
      "8": "1000", "9": "1001", "A": "1010", "B": "1011",
      "C": "1100", "D": "1101", "E": "1110", "F": "1111",
    ]
    return hexString.uppercased().compactMap { binaryMap[String($0)] }.joined()
  }
}

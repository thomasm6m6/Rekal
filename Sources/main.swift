import Foundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit
import SQLite

struct Window {
  let id: Int
  let rect: CGRect
  let isActive: Bool
  var title: String?
  var appName: String?
  var appId: String?
  var url: String?
}

struct Snapshot {
  let timestamp: Int
  let windows: [Int: Window]

  init(timestamp: Int, windows: [Int: Window]) {
    self.timestamp = timestamp
    self.windows = windows
  }
}

enum RecordingError: Error {
  case infoError(String)
}

actor Recorder {
  var isRecording = true
  private let interval: TimeInterval
  private var lastSnapshot: Snapshot? = nil

  init(interval: TimeInterval) {
    self.interval = interval
  }

  func setRecording(_ status: Bool) {
    isRecording = status
  }

  func record() async throws {
    if !isRecording {
      return
    }

    if isIdle() {
      print("Idle; skipping...")
      return
    }

    do {
      guard let snapshot = try await capture() else {
        return
      }
      print("Got snapshot:")
      print(snapshot)
    } catch {
      // throw?
      print("Did not save image: \(error)")
    }
  }

  private func capture() async throws -> Snapshot? {
    let timestamp = Int(Date().timeIntervalSince1970)
    var windows: [Int: Window] = [:]

    guard let frontmostAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
      return nil
    }

    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    for window in content.windows {
      // This number is a total guess. It seems that normal app windows are 0 and
      // most system-level windows (dock, etc) are 25. Exceptions include the
      // ChatGPT option+space window (8), Spotlight (23), etc. Menubar is 24.
      if window.windowLayer > 23 {
        continue
      }
      guard let title = window.title, let app = window.owningApplication else {
        throw RecordingError.infoError("Cannot get window title or app")
      }
      let id = Int(window.windowID)
      var windowInfo = Window(
        id: id,
        rect: window.frame,
        isActive: frontmostAppPID == app.processID,
        title: title,
        appName: app.applicationName,
        appId: app.bundleIdentifier,
      )
      if app.bundleIdentifier == "com.google.Chrome" {
        if let lastWindow = lastSnapshot?.windows[id], title == lastWindow.title {
          windowInfo.url = lastWindow.url
        } else if let url = getBrowserURL() {
          windowInfo.url = url
        }
      }
      windows[id] = windowInfo
    }

    let snapshot = Snapshot(
      timestamp: timestamp,
      windows: windows,
    )

    lastSnapshot = snapshot
    return snapshot
  }

  private func getBrowserURL() -> String? {
    let script = "tell application \"Google Chrome\" to get URL of active tab of front window"
    var error: NSDictionary?
    guard let scriptObject = NSAppleScript(source: script) else {
      print("Error constructing AppleScript")
      return nil
    }
    let output = scriptObject.executeAndReturnError(&error)
    if error != nil {
      print("Error executing AppleScript: \(String(describing: error))")
      return nil
    }
    return output.stringValue
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
}

let currentPathURL = URL(filePath: FileManager.default.currentDirectoryPath)
let dbPath = currentPathURL.appending(path: "db.sqlite3")

let recorder = Recorder(interval: 1.0)

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
  Task {
    do {
      try await recorder.record()
    } catch {
      print("Error capturing snapshot: \(error)")
    }
  }
}

RunLoop.main.run()

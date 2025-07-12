import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

// import SQLite

struct Window {
  let id: Int
  let rect: CGRect
  let isActive: Bool
  let zIndex: Int
  var title: String
  var appName: String
  var appId: String
  var url: String?
}

struct Snapshot {
  let timestamp: Int  // milliseconds
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
  private var lastSnapshot = Snapshot(timestamp: 0, windows: [:])

  func setRecording(_ status: Bool) {
    isRecording = status
  }

  func record() async throws {
    if !isRecording {
      return
    }

    do {
      let snapshot = try await capture()
      print(snapshot)
    } catch {
      // throw?
      print("Did not save image: \(error)")
    }
  }

  private func capture() async throws -> Snapshot {
    let timestamp = Int(Date().timeIntervalSince1970 * 1000)  // milliseconds
    var windows: [Int: Window] = [:]
    let appBlacklist = ["com.apple.WindowManager"]

    guard let frontmostAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
      throw RecordingError.infoError("Cannot get frotnmost application ID")
    }

    let content = try await SCShareableContent.excludingDesktopWindows(
      true, onScreenWindowsOnly: true)
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
      if appBlacklist.contains(app.bundleIdentifier) {
        continue
      }
      let id = Int(window.windowID)
      var windowInfo = Window(
        id: id,
        rect: window.frame,
        isActive: frontmostAppPID == app.processID,
        zIndex: window.windowLayer,
        title: title,
        appName: app.applicationName,
        appId: app.bundleIdentifier,
      )
      if app.bundleIdentifier == "com.google.Chrome" {
        if let lastWindow = lastSnapshot.windows[id], title == lastWindow.title {
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
}

class RecorderController {
  private let recorder = Recorder()
  private let minInterval: TimeInterval = 1
  private var lastSnapshot = Date(timeIntervalSince1970: 0)
  private var monitor: Any?

  init() {
    setupMonitor()
  }

  private func setupMonitor() {
    let eventMask =
      ((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.otherMouseDown.rawValue))

    let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(eventMask),
      callback: { proxy, type, event, refcon in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
        let mySelf = Unmanaged<RecorderController>.fromOpaque(refcon).takeUnretainedValue()
        mySelf.maybeCapture()
        return Unmanaged.passUnretained(event)
      },
      userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )

    guard let tap = eventTap else {
      print("Failed to create event tap. Do you have Accessibility permissions?")
      exit(1)
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  private func maybeCapture() {
    let now = Date()
    guard now.timeIntervalSince(lastSnapshot) >= minInterval else { return }
    let recorder = self.recorder
    Task {
      do {
        try await recorder.record()
      } catch {
        print("Error capturing snapshot: \(error)")
      }
    }
    lastSnapshot = now
  }
}

let controller = RecorderController()

print("Starting event tap listener...")
CFRunLoopRun()

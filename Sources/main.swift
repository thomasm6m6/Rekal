import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

// import SQLite

struct Window: Sendable {
  let id: Int
  let rect: CGRect
  let isActive: Bool
  let zIndex: Int
  var title: String
  var appName: String
  var appId: String
  var url: String?
}

struct Event: Sendable {
  let timestamp: Int64
  let type: CGEventType
  let data: String?

  init(timestamp: Int64, type: CGEventType, data: String?) {
    self.timestamp = timestamp
    self.type = type
    self.data = data
  }

  init?(cgEvent: CGEvent) {
    var data: String?

    if cgEvent.type == .keyUp || cgEvent.type == .keyDown {
      var length: Int = 0
      var string = [UniChar](repeating: 0, count: 4)

      cgEvent.keyboardGetUnicodeString(maxStringLength: 4,
        actualStringLength: &length,
        unicodeString: &string)

      data = String(utf16CodeUnits: string, count: length)
    }

    self.init(timestamp: Int64(cgEvent.timestamp), type: cgEvent.type, data: data)
  }
}

actor EventLogger {
  private var buffer = [Event]()

  func log(event: Event) async {
    buffer.append(event)
    if buffer.count >= 100 {
      await flushToDisk()
    }
  }

  private func flushToDisk() async {
    // TODO write to disk
    for event in buffer {
      print(event)
    }
    buffer.removeAll()
  }
}

struct Snapshot: Sendable {
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

@MainActor
final class RecorderController {
  private let recorder = Recorder()
  private let eventLogger = EventLogger()
  private let minInterval: TimeInterval = 1
  private var lastSnapshot = Date(timeIntervalSince1970: 0)

  init() {
    let eventMask =
      ((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.otherMouseDown.rawValue))

    let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(eventMask),
      callback: { _, _, cgEvent, refcon in
        guard let refcon = refcon else { return Unmanaged.passUnretained(cgEvent) }
        let controller = Unmanaged<RecorderController>
          .fromOpaque(refcon)
          .takeUnretainedValue()
        let event = Event(cgEvent: cgEvent)
        Task { @MainActor in
          await controller.handle(event: event)
        }
        return Unmanaged.passUnretained(cgEvent)
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

  private func handle(event: Event?) async {
    // log event
    if let event = event {
      await eventLogger.log(event: event)
    }

    // maybe capture screen
    // let now = Date()
    // guard now.timeIntervalSince(lastSnapshot) >= minInterval else { return }
    // let recorder = self.recorder
    // Task {
    //   do {
    //     try await recorder.record()
    //   } catch {
    //     print("Error capturing snapshot: \(error)")
    //   }
    // }
    // lastSnapshot = now
  }
}

let controller = RecorderController()

print("Starting event tap listener...")
CFRunLoopRun()

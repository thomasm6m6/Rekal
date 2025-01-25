import Foundation

enum FilesError: Error {
    case nonexistentDirectory(String)
}

// TODO this is probably unsafe/wrong
class Files: @unchecked Sendable {
    var appSupportDir: URL
    var databaseFile: URL

    // TODO rename to "shared"
    // maybe: static let shared = Files()
    static let `default`: Files = {
        do {
            return try Files(
                appSupportDir: Files.getAppSupportDir(),
                databaseFile: Files.getDatabaseFile()
            )
        } catch {
            fatalError("Failed to initialize default Files instance: \(error)")
        }
    }()

    init(appSupportDir: URL, databaseFile: URL) {
        self.appSupportDir = appSupportDir
        self.databaseFile = databaseFile
    }

    static func getAppSupportDir() throws -> URL {
        let bundleIdentifier = "com.thomasm6m6.Rekal"  // TODO bundle.main.bundleIdentifier(?)
        guard
            let dir = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else {
            throw FilesError.nonexistentDirectory(
                "Failed to get location of Application Support directory")
        }
        return dir.appending(path: bundleIdentifier)
    }

    static func getDatabaseFile() throws -> URL {
        let appSupportDir = try self.getAppSupportDir()
        return appSupportDir.appending(path: "db.sqlite3")
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // TODO Maybe functions to iterate over mp4s
}

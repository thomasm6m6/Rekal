import Foundation

// TODO: don't do this
extension XPCSession: @unchecked @retroactive Sendable {}

enum XPCError: Error {
    case noSession
    case badResponse
}

// does this need to be an actor?
actor XPCManager {
    private var xpcSession: XPCSession?

    init() {}

    deinit {
        xpcSession?.cancel(reason: "Done")
    }

    private func getSession() throws -> XPCSession {
        if xpcSession == nil {
            // might like to use options: .inactive, but can't solve the concurrency error
            // solution is probably etiher nonisolated(unsafe) or to run on main actor
            xpcSession = try XPCSession(machService: "com.thomasm6m6.RekalAgent.xpc")
        }
        guard let session = xpcSession else {
            throw XPCError.noSession
        }
        return session
    }

    func setRecording(_ state: Bool) async throws -> Bool {
        let session = try getSession()

        let request = XPCRequest(messageType: .setRecording(state))
        let response = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<XPCResponse, any Error>) in

            do {
                try session.send(request) { result in
                    switch result {
                    case .success(let reply):
                        do {
                            let response = try reply.decode(as: XPCResponse.self)
                            continuation.resume(returning: response)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        switch response.reply {
        case .recordingStatus(let status):
            return status
        default:
            throw XPCError.badResponse
        }
    }

    // FIXME: not loading from XPC
    func getSnapshots(timestamps: [Int]) async throws -> [Snapshot] {
        guard timestamps.count > 0 else { return [] }
        let session = try getSession()

        // FIXME: ignoring search parameters. should use the timestamps passed as argument (also fix in loadImagesFromDisk)
        let request = XPCRequest(messageType: .getSnapshots(timestamps: timestamps))
        let response = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<XPCResponse, any Error>) in

            do {
                try session.send(request) { result in
                    switch result {
                    case .success(let reply):
                        do {
                            let response = try reply.decode(as: XPCResponse.self)
                            continuation.resume(returning: response)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        switch response.reply {
        case .snapshots(let encodedSnapshots):
            return decodeSnapshots(encodedSnapshots)
        default:
            throw XPCError.badResponse
        }
    }

    func getTimestamps(query: Query) async throws -> [Int] {
        let session = try getSession()

        let request = XPCRequest(messageType: .getTimestamps(query: query))
        let response = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<XPCResponse, any Error>) in

            do {
                try session.send(request) { result in
                    switch result {
                    case .success(let reply):
                        do {
                            let response = try reply.decode(as: XPCResponse.self)
                            continuation.resume(returning: response)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        switch response.reply {
        case .timestamps(let timestamps):
            print(timestamps)
            return timestamps
        default:
            throw XPCError.badResponse
        }
    }
}

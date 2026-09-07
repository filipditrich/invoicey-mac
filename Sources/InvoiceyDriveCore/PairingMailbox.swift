import Foundation

/// Receives `invoicey-drive://oauth` and Associated Domains callbacks while pairing.
public final class PairingMailbox: @unchecked Sendable {
  public static let shared = PairingMailbox()

  private let queue = DispatchQueue(label: "me.ditrich.invoicey.drive.pairing-mailbox")
  private var continuation: CheckedContinuation<String, Error>?
  private var pending: Result<String, Error>?
  private var finished = false

  public init() {}

  public func reset() {
    queue.sync {
      continuation = nil
      pending = nil
      finished = false
    }
  }

  @discardableResult
  public func deliver(_ url: URL) -> Bool {
    let result: Result<String, Error>
    do {
      guard let code = try PairingCallback.authorizationCode(from: url) else {
        return false
      }
      result = .success(code)
    } catch {
      result = .failure(error)
    }
    queue.async {
      self.finish(result)
    }
    return true
  }

  public func waitForCode(timeout: Duration) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
      group.addTask {
        try await withCheckedThrowingContinuation { continuation in
          self.queue.async {
            if let pending = self.pending {
              self.pending = nil
              continuation.resume(with: pending)
              return
            }
            if self.finished {
              continuation.resume(throwing: DriveError.pairingFailed("Callback already finished."))
              return
            }
            self.continuation = continuation
          }
        }
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw DriveError.pairingTimeout
      }
      guard let code = try await group.next() else {
        throw DriveError.pairingTimeout
      }
      group.cancelAll()
      return code
    }
  }

  func finish(_ result: Result<String, Error>) {
    if finished {
      return
    }
    finished = true
    if let continuation {
      self.continuation = nil
      continuation.resume(with: result)
    } else {
      pending = result
    }
  }
}

import FileProvider
import Foundation
import InvoiceyDriveCore

enum FileProviderDomainOutcome: Equatable, Sendable {
  case skippedNotBundled
  case added
  case alreadyPresent
  case removed
  case idleUnpaired
  case failed(String)
}

enum FileProviderDomainRegistration {
  static var isBundledApp: Bool {
    Bundle.main.bundlePath.hasSuffix(".app")
      && Bundle.main.bundleIdentifier == DriveConstants.bundleId
  }

  static func makeDomain() -> NSFileProviderDomain {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier(DriveConstants.fileProviderDomainId),
      displayName: DriveConstants.domainDisplayName
    )
    domain.isHidden = false
    return domain
  }

  static func sync(paired: Bool) async -> FileProviderDomainOutcome {
    guard isBundledApp else {
      return .skippedNotBundled
    }
    let domain = makeDomain()
    do {
      let present = try await isDomainPresent()
      if FileProviderDomainPolicy.needsAdd(paired: paired, domainPresent: present) {
        try await addDomain(domain)
        try await signalWorkingSet()
        return .added
      }
      if FileProviderDomainPolicy.needsRemove(paired: paired, domainPresent: present) {
        try await NSFileProviderManager.remove(domain)
        return .removed
      }
      if paired {
        try await signalWorkingSet()
        return .alreadyPresent
      }
      return .idleUnpaired
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  static func userVisibleRootURL() async -> URL? {
    guard isBundledApp, let manager = manager() else {
      return nil
    }
    return try? await manager.getUserVisibleURL(for: .rootContainer)
  }

  static func signalWorkingSet() async throws {
    guard let manager = manager() else {
      return
    }
    try await manager.signalEnumerator(for: .workingSet)
  }

  static func isDomainPresent() async throws -> Bool {
    let domains = try await NSFileProviderManager.domains()
    return domains.contains { $0.identifier.rawValue == DriveConstants.fileProviderDomainId }
  }

  static func manager() -> NSFileProviderManager? {
    NSFileProviderManager(for: makeDomain())
  }

  static func addDomain(_ domain: NSFileProviderDomain) async throws {
    var lastError: Error = DriveError.usage("File Provider add did not run.")
    for attempt in 1...3 {
      do {
        try await NSFileProviderManager.add(domain)
        return
      } catch {
        lastError = error
        if try await isDomainPresent() {
          return
        }
        try await Task.sleep(for: .milliseconds(400 * attempt))
      }
    }
    throw lastError
  }
}

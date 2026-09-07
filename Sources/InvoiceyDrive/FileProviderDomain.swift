import FileProvider
import Foundation
import InvoiceyDriveCore

enum FileProviderDomainRegistration {
  static var isBundledApp: Bool {
    Bundle.main.bundlePath.hasSuffix(".app")
      && Bundle.main.bundleIdentifier == DriveConstants.bundleId
  }

  static func sync(paired: Bool) async {
    guard isBundledApp else {
      return
    }
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier(DriveConstants.fileProviderDomainId),
      displayName: DriveConstants.domainDisplayName
    )
    do {
      let existing = NSFileProviderManager(for: domain)
      if paired {
        if existing == nil {
          try await NSFileProviderManager.add(domain)
        }
        return
      }
      if existing != nil {
        try await NSFileProviderManager.remove(domain)
      }
    } catch {
      fputs(
        "Invoicey Drive: File Provider domain sync failed: \(error.localizedDescription)\n",
        stderr
      )
    }
  }
}

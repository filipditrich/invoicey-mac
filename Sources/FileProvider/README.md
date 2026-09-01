import FileProvider
import Foundation
import InvoiceyDriveCore

/// How to turn this library into a Finder sidebar location.
///
/// `swift build` compiles enumerator + item identity against FileProvider.framework.
/// It does **not** register a domain. Finder needs an `.appex` embedded in an `.app`.
///
/// Required (Xcode, paid Apple Developer team):
/// 1. macOS app `me.ditrich.invoicey.drive` with `com.apple.developer.fileprovider.testing-mode`
///    for local sideload, plus App Group `group.me.ditrich.invoicey.drive` so the extension
///    can read the Keychain device token written by the menu bar app / CLI.
/// 2. File Provider extension target whose principal class is `InvoiceyDriveReplicatedExtension`.
///    Entitlement `com.apple.fileprovider.nonui` (or the File Provider capability in Xcode).
/// 3. Register the domain from the app (not from `swift run`):
///    `NSFileProviderManager.add(NSFileProviderDomain(identifier: "me.ditrich.invoicey.drive", displayName: "Invoicey Drive"))`
///
/// Until that Xcode project exists, use the CLI/menu-bar mirror folder:
/// `invoicey-drive pair` then `invoicey-drive sync`.
///
/// Product rules the enumerator already encodes:
/// - Tree is `workspaceName/issuerName/{layoutRelPath}` from the server index.
/// - File color tags come from index `displayStatus` (`tagData`); status is not in the filename.
/// - Finder delete does not cancel the invoice; the next enumerate restores the item.
/// - Drop-in create is rejected (`DriveError.dropInsIgnored`).
/// - Cancel only on the web.

import FileProvider
import Foundation
import InvoiceyDriveCore

/// How to turn this library into a Finder sidebar location.
///
/// `swift build` compiles enumerator + item identity against FileProvider.framework.
/// Finder Locations need the Xcode `.app` + `.appex` at the repo root
/// (`InvoiceyDrive.xcodeproj`, Team `72T6DX5YZU`).
///
/// Required (signed app, paid Apple Developer team):
/// 1. macOS app `me.ditrich.invoicey.drive` with App Group
///    `group.me.ditrich.invoicey.drive` so the extension can read the Keychain
///    device token, plus Associated Domains `applinks:invoicey.app`.
/// 2. File Provider extension `me.ditrich.invoicey.drive.provider` whose principal
///    class is `InvoiceyDriveReplicatedExtension`.
///    Entitlement `com.apple.fileprovider-nonui`.
/// 3. The bundled app registers the domain after pair
///    (`NSFileProviderDomain` identifier `me.ditrich.invoicey.drive`).
///
/// `swift run InvoiceyDrive` still uses the mirror folder only — it cannot embed
/// an appex.
///
/// Product rules the enumerator already encodes:
/// - Tree is `workspaceName/issuerName/{layoutRelPath}` from the server index.
/// - File color tags come from index `displayStatus` (`tagData`); status is not in the filename.
/// - Finder delete does not cancel the invoice; the next enumerate restores the item.
/// - Drop-in create is rejected (`DriveError.dropInsIgnored`).
/// - Cancel only on the web.

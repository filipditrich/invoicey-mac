import InvoiceyDriveCore
import Testing

struct DriveMenuCopyTests {
  @Test func statusTitleNeverLooksLikeConnect() {
    #expect(
      DriveMenuCopy.statusTitle(paired: false, lastStatusLine: "Connect Invoicey")
        == "Invoicey Drive"
    )
    #expect(
      DriveMenuCopy.statusTitle(paired: true, lastStatusLine: "Connect Invoicey")
        == "Invoicey Drive"
    )
    #expect(DriveMenuCopy.statusTitle(paired: true, lastStatusLine: "") == "Invoicey Drive")
    #expect(
      DriveMenuCopy.statusTitle(paired: true, lastStatusLine: "Synced just now")
        == "Synced just now"
    )
    #expect(
      DriveMenuCopy.statusTitle(paired: false, lastStatusLine: "Synced just now")
        == "Invoicey Drive"
    )
  }
}

struct FileProviderDomainPolicyTests {
  @Test func addsOnlyWhenPairedAndMissing() {
    #expect(FileProviderDomainPolicy.needsAdd(paired: true, domainPresent: false))
    #expect(!FileProviderDomainPolicy.needsAdd(paired: true, domainPresent: true))
    #expect(!FileProviderDomainPolicy.needsAdd(paired: false, domainPresent: false))
  }

  @Test func removesOnlyWhenUnpairedAndPresent() {
    #expect(FileProviderDomainPolicy.needsRemove(paired: false, domainPresent: true))
    #expect(!FileProviderDomainPolicy.needsRemove(paired: true, domainPresent: true))
    #expect(!FileProviderDomainPolicy.needsRemove(paired: false, domainPresent: false))
  }
}

import Foundation
import InvoiceyDriveCore
import Testing

struct DriveMenuCopyTests {
  @Test func headerIncludesVersion() {
    #expect(DriveMenuCopy.headerTitle(version: nil) == "Invoicey Drive")
    #expect(DriveMenuCopy.headerTitle(version: "  ") == "Invoicey Drive")
    #expect(DriveMenuCopy.headerTitle(version: "0.1.7") == "Invoicey Drive  0.1.7")
  }

  @Test func detailStatusSkipsNameAndConnect() {
    #expect(DriveMenuCopy.detailStatus(paired: false, lastStatusLine: "Synced just now") == nil)
    #expect(DriveMenuCopy.detailStatus(paired: true, lastStatusLine: "") == nil)
    #expect(DriveMenuCopy.detailStatus(paired: true, lastStatusLine: "Invoicey Drive") == nil)
    #expect(DriveMenuCopy.detailStatus(paired: true, lastStatusLine: "Connect Invoicey") == nil)
    #expect(
      DriveMenuCopy.detailStatus(paired: true, lastStatusLine: "Synced just now")
        == "Synced just now"
    )
  }

  @Test func countRowsOnlyWhenPositive() {
    #expect(DriveMenuCopy.overdueTitle(0) == nil)
    #expect(DriveMenuCopy.unpaidTitle(0) == nil)
    #expect(DriveMenuCopy.overdueTitle(2) == "Overdue · 2")
    #expect(DriveMenuCopy.unpaidTitle(1) == "Unpaid · 1")
  }

  @Test func lastSyncTitleParsesISO8601() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(DriveMenuCopy.lastSyncTitle(iso8601: "not-a-date") == nil)
    #expect(DriveMenuCopy.lastSyncTitle(iso8601: "2023-11-14T22:13:20Z", now: date) != nil)
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

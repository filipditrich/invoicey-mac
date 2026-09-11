import Foundation

/// Whether the host should add or remove the Finder Locations domain.
public enum FileProviderDomainPolicy: Sendable {
  public static func needsAdd(paired: Bool, domainPresent: Bool) -> Bool {
    paired && !domainPresent
  }

  public static func needsRemove(paired: Bool, domainPresent: Bool) -> Bool {
    !paired && domainPresent
  }
}

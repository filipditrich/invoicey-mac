# Invoicey Drive

macOS companion librarian for [Invoicey](https://invoicey.ditrich.me). Bundle id `me.ditrich.invoicey.drive`. Sibling of the Invoicey turborepo (this repo is not inside `inveoiceyai`).

The Mac materializes the **server** index as files:

```text
{workspaceName}/{issuerName}/{layoutRelPath}.pdf
```

Plus `.isdoc` when the index says `includeIsdoc`. Finder delete comes back on the next sync. Drop-ins are ignored. Cancel only on the web.

## Local run (no paid File Provider team)

Pairing is PKCE in the app. Never paste a PAT.

Web origin defaults to `http://localhost:3000` (`INVOICEY_DRIVE_API_URL`). Production is `https://invoicey.ditrich.me`.

```bash
cd /Users/filipditrich/Work/invoicey-mac

# start Invoicey web on :3000 in the turborepo, then:
swift run invoicey-drive pair
# browser opens {api}/drive/connect?challenge=…&redirect=http://127.0.0.1:<port>/oauth
# confirm the device on the web page; this process exchanges the code and stores the token

swift run invoicey-drive sync
# writes ~/Invoicey Drive unless you already set a folder

swift run invoicey-drive status
swift run invoicey-drive set-mirror ~/Invoicey\ Drive
swift run invoicey-drive sign-out
```

Menu bar (polls every 60s, on wake, and Sync now):

```bash
swift run InvoiceyDrive
```

`swift run` uses `http://127.0.0.1:<port>/oauth`. The custom scheme `invoicey-drive://oauth` is listed in `Sources/InvoiceyDrive/Info.plist` and works when this target is wrapped as a real `.app`.

Login item default ON applies only inside a bundled app (`SMAppService`). Unsigned `swift run` cannot register it.

## Token storage

Keychain service `me.ditrich.invoicey.drive`, account `device-token`. Sign out calls `POST /api/drive/revoke` then forgets the token.

If Keychain save fails (common for an unsigned `swift run` binary), the token is written to `~/Library/Application Support/Invoicey Drive/debug-token` with mode `0600`. That file is debug-only. Config (`config.json`) never stores the token.

## File Provider (Finder sidebar)

Sources live in `Sources/FileProvider/`. They map the same Core tree (`DriveTree`) to `NSFileProviderEnumerator` / item identifiers. `swift build` compiles that library.

Enabling **Locations → Invoicey Drive** needs an Xcode app + File Provider extension, File Provider + App Group entitlements, and a paid Developer team. Sample entitlements are next to the sources. See `Sources/FileProvider/README.md`.

APNs is out of scope.

## API

| Step | Request |
| --- | --- |
| Connect page | `GET {api}/drive/connect?challenge={S256}&redirect={url}&device={name}` |
| Token | `POST {api}/api/drive/token` `{ code, verifier, redirectUri }` |
| Index | `GET {api}/api/drive/index` `Authorization: Bearer {token}` |
| PDF | `GET {api}/api/drive/invoices/{id}/pdf` |
| ISDOC | `GET {api}/api/drive/invoices/{id}/isdoc` |
| Revoke | `POST {api}/api/drive/revoke` |

Redirect allowlist (web): `invoicey-drive://oauth`, `http://127.0.0.1:*/oauth`, `http://localhost:*/oauth`.

## Tests

```bash
swift test
```

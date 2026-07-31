# IndependentDemo

A runnable proof of the master plan **§20 "First end-to-end proof"**. It drives
the **real** `LumenUpdater`, signed TUF repositories, and installer modules
through every §20 scenario and reports PASS/FAIL.

## Run it

```bash
swift run independent-demo
```

Exits `0` if every scenario passes, `1` otherwise.

## What it proves

| §20 point | Scenario | How it's proven |
|:--:|:---|:---|
| 1 | `1.0 → 1.1` installs successfully | `checkForUpdates()` finds the update; `downloadAndInstall()` downloads, hash-verifies, and stages it |
| 2 | A modified archive is rejected before extraction | Artifact bytes are swapped after signing; download fails on SHA-256 mismatch — before a single byte is unpacked (Invariant 1) |
| 3 | A replayed older repository is rejected | A persisted `VersionTracker` spans two checks; the replayed metadata version is rejected as rollback |
| 4 | `1.1 → 1.2` crashes and rolls back to `1.1` | A transaction journal frozen at "awaiting health acknowledgement" + a preserved backup; `RollbackManager.recoverFromCrash` restores `1.1` |
| 5 | `1.1 → 1.3` succeeds after the failed release | A recovery release installs cleanly once the host is back on `1.1` |
| 6 | The flow works from a user-owned directory | Every flow runs in a user-writable temp directory |
| 10 | No private update key in the app bundle | The shipped bundle is scanned — only public root metadata, zero `.key`/private files |

Points **§20.7** (non-writable install → manual-update path), **§20.8**
(clean-machine Gatekeeper behavior), and **§20.9** (Developer ID–signed build)
require a full macOS GUI environment and are documented in
[`../../Documentation/ACCOUNTLESS_DISTRIBUTION.md`](../../Documentation/ACCOUNTLESS_DISTRIBUTION.md).

## How it works

The demo builds fully-signed repositories on the fly with
`RepositoryBuilder` (real Ed25519 keys, real SHA-256 hashes, a consistent
timestamp → snapshot → targets chain), then runs the production `LumenUpdater`
against them via a `LocalRepositoryFetcher`. Nothing is mocked in the
verification path — the same code that ships in the SDK is what's exercised.

Bundle versions used (monotonic): `1.0 = 100`, `1.1 = 101`, `1.2 = 102`,
`1.3 = 103`.

# Lumen Update test vectors

These fixtures are consumed by Phase 1 verifier tests.

## Directory contents
- `manifest.json` enumerates every vector file and its expected outcome.
- `*.json` files are self-contained test vectors.

## Vector schema
Each vector file contains:
- `vectorVersion`
- `description`
- `expectedResult`: `accept` or `reject`
- `expectedError`: present only for rejects
- `whatIsWrong`: human-readable annotation for invalid cases
- `metadata`:
  - `root.json`
  - `targets.json`
  - `snapshot.json`
  - `timestamp.json`

Each metadata file uses a realistic TUF shape:
- top-level `signed`
- top-level `signatures`
- canonical TUF role fields (`type`, `spec_version`, `version`, `expires`, `keys`, `roles`, `targets`, `meta`)

## Canonicalization used for signatures
For these fixtures, signing uses a deterministic JSON form:
- UTF-8
- sorted keys
- no extra whitespace
- array order preserved

This is intentionally simpler than full RFC 8785 JCS and is the signing rule the Phase 1 tests should mirror.

## Key material
The vectors use Ed25519 test keys generated locally with Swift CryptoKit. The root metadata includes the trusted public keys for:
- 2 root keys
- 2 targets keys (threshold 2)
- 1 snapshot key
- 1 timestamp key

A separate rogue key is used only for the unknown-key rejection case.

### Reproducible key generation
Run these commands to regenerate the test keys:

```bash
swift -e 'import Foundation; import CryptoKit; let names = ["root-a", "root-b", "targets-a", "targets-b", "snapshot", "timestamp", "rogue"]; var out: [String: [String: String]] = [:]; for name in names { let key = Curve25519.Signing.PrivateKey(); out[name] = ["seed": Data(key.rawRepresentation).base64EncodedString(), "public": Data(key.publicKey.rawRepresentation).base64EncodedString()] }; let url = URL(fileURLWithPath: "/tmp/lumen-update-test-keys/key-material.json"); try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]).write(to: url)'
```

## Expected error codes
- `SIGNATURE_INVALID`
- `THRESHOLD_NOT_MET`
- `METADATA_EXPIRED`
- `ROLLBACK_DETECTED`
- `PRODUCT_MISMATCH`
- `CHANNEL_MISMATCH`
- `ARCHITECTURE_MISMATCH`
- `MIX_AND_MATCH_DETECTED`
- `FAST_FORWARD_DETECTED`
- `UNKNOWN_KEY`

## Notes
- Valid vectors use real Ed25519 signatures.
- Invalid vectors are annotated with the specific failure reason.
- The `manifest.json` file is the source of truth for iteration order in tests.

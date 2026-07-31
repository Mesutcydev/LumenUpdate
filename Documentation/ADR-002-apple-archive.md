# ADR-002: Apple Archive as Primary Update Format

**Status:** Accepted
**Date:** 2026-07-31
**Deciders:** Lumen Architecture Team

## Context

macOS application bundles (`.app`) contain executable files, frameworks, resources, and metadata with specific file-system attributes:
- **Ownership** (user, group)
- **Permissions** (read, write, execute, setuid, setgid, sticky)
- **Flags** (UF_HIDDEN, SF_ARCHIVED, etc.)
- **Timestamps** (modification, access, creation)
- **Extended attributes** (quarantine, codesignatures, provenance)
- **Symlinks and hard links**
- **Resource forks** (legacy HFS metadata)

The update archive format must preserve these attributes during extraction to ensure the updated application functions correctly and maintains its security properties (e.g., code signatures, quarantine attributes).

## Decision

Use **Apple Archive (`.aar`)** as the first-class update format for Lumen. ZIP compatibility may be added later through a separately audited adapter.

## Consequences

### Positive
- **Native macOS support** via the Archive framework. No external dependencies.
- **Preserves all file-system metadata** including ownership, permissions, flags, timestamps, and extended attributes.
- **Efficient compression** using LZFSE or other Apple-supported algorithms.
- **Preserves hard links and symlinks** correctly, which is important for frameworks.
- **Built-in verification** via Apple Archive's manifest (SHA-256 of each entry).
- **Atomic extraction** via `ArchiveByteStream` API.

### Negative
- **macOS-only.** The CLI cannot package on Linux without porting (see ADR-003 for cross-platform crypto; packaging is macOS-only for v1).
- **Less universal than ZIP.** Many tools don't understand `.aar` files directly.
- **Apple Archive format is less widely understood.** Fewer reference implementations and documentation.
- **Requires the Archive framework** which is macOS 10.13+ (acceptable given v1 requires macOS 13+).

## Alternatives Considered

### Alternative 1: ZIP
**Description:** Use ZIP files for update archives.

**Rejected because:**
- ZIP does not preserve Unix permissions, ownership, or extended attributes reliably across implementations.
- Would require post-extraction fixup scripts to set permissions, which is forbidden by [SECURITY_INVARIANTS.md](../SECURITY_INVARIANTS.md) invariant 1 (no arbitrary scripts).
- The Apple Archive manifest provides built-in verification; ZIP requires a separate manifest.
- Code signature verification may fail if attributes are not preserved correctly.

### Alternative 2: tar.gz
**Description:** Use tar archives compressed with gzip.

**Rejected because:**
- tar preserves permissions and ownership but not macOS extended attributes or resource forks.
- No built-in integrity verification (requires separate manifest).
- Less efficient than Apple Archive's LZFSE compression.
- tar is not designed for macOS-specific metadata.

### Alternative 3: DMG (Disk Image)
**Description:** Use a DMG disk image as the update payload.

**Rejected because:**
- DMG is a disk image, not an archive. Requires mounting and copying files.
- Adds complexity (mount, copy, unmount).
- The user may see a "disk image mounted" notification, which is confusing.
- DMG files are not designed for programmatic verification (no manifest).
- Cannot be streamed efficiently.

### Alternative 4: Custom tar-based format
**Description:** Use a custom format based on tar with additional metadata.

**Rejected because:**
- Reinventing archive formats is error-prone and security-sensitive.
- No tooling support; every consumer must implement the parser.
- A malicious custom format could have subtle vulnerabilities.

## References

- Apple Archive documentation: https://developer.apple.com/documentation/applearchive
- Archive framework: https://developer.apple.com/documentation/archive
- [SECURITY_INVARIANTS.md](../SECURITY_INVARIANTS.md) — Invariant 1: no extraction before verification
- [SPEC.md](../SPEC.md) — Target metadata `archiveFormat` field

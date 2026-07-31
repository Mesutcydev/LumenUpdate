# ADR-001: Full TUF Profile vs TUF-lite

**Status:** Accepted
**Date:** 2026-07-31
**Deciders:** Lumen Architecture Team

## Context

The Update Framework (TUF) provides a comprehensive security model for software update systems. It defines four required top-level roles (Root, Targets, Snapshot, Timestamp) and formally addresses known attack classes: rollback, freeze, endless-data, wrong-target, mix-and-match, and key compromise. See [THREAT_MODEL.md](../THREAT_MODEL.md) for details.

A "TUF-lite" approach might simplify by reducing roles (e.g., merging Snapshot into Targets), using a custom protocol inspired by TUF, or implementing a simpler signature scheme.

The decision affects:
- Protocol security guarantees
- Implementation complexity
- Future extensibility
- Auditability

## Decision

Lumen implements a **constrained, documented TUF profile** rather than a homemade "TUF-lite" protocol. We adopt all four required top-level roles from the TUF specification with Lumen-specific extensions for macOS application metadata.

The full profile is documented in [SPEC.md](../SPEC.md).

## Consequences

### Positive
- **Battle-tested security model.** TUF has formal security analysis and a track record of use in production update systems.
- **Clear documentation and tooling ecosystem.** The TUF specification, python-tuf, and other implementations provide reference material.
- **Protection against all known TUF attack classes.** Rollback, freeze, endless-data, wrong-target, mix-and-match, and key compromise are all addressed.
- **Easier security audit.** The protocol is well-understood by security researchers.
- **Interoperability.** Compatible with other TUF implementations (e.g., python-tuf for tooling).

### Negative
- **More complex initial implementation.** Four roles, threshold signatures, and delegation require more code than a simple signed JSON approach.
- **Larger metadata footprint.** All four roles must be fetched and verified (total ~100 KB max).
- **Requires key management for multiple roles.** Each role has its own key(s), requiring ceremony and rotation procedures.
- **Steeper learning curve.** Developers integrating Lumen must understand TUF concepts.

## Alternatives Considered

### Alternative 1: TUF-lite with 2 roles (Root + Targets)
**Description:** Combine Snapshot and Timestamp into the Targets role, eliminating two roles.

**Rejected because:**
- Missing Snapshot means no protection against rollback of targets.json.
- Missing Timestamp means no proof of repository freshness; an attacker can replay old targets metadata indefinitely.
- Loses the separation of concerns that makes TUF's security model robust.

### Alternative 2: Custom protocol inspired by TUF
**Description:** Design a custom protocol that looks like TUF but is simpler.

**Rejected because:**
- Security protocols must be formally analyzed. Custom protocols have a history of subtle vulnerabilities.
- No community review or established tooling.
- Future maintainers must re-learn the protocol.
- Cannot leverage existing TUF implementations for tooling (e.g., python-tuf for server-side signing).

### Alternative 3: No TUF, just signed JSON
**Description:** Single signed JSON file with target list and signatures.

**Rejected because:**
- Lacks rollback protection (no version tracking per role).
- Lacks key rotation support (no delegation, no threshold signatures).
- Lacks delegation (no per-channel targets).
- Lacks freshness proof (no timestamp role).

### Alternative 4: The Update Framework with extensions (TAP, hash bins, succinct roles)
**Description:** Use the full TUF specification including optional features.

**Rejected because:**
- TAP (Transparent App Publishing) is not relevant for Lumen's self-hosted model.
- Hash bins add complexity without clear benefit for v1.
- Succinct roles are an optimization not needed at our scale.
- v1 should use the minimum subset that provides security; add features later.

## References

- TUF Specification: https://theupdateframework.io/docs/metadata/
- TUF Security: https://theupdateframework.io/security/
- [SPEC.md](../SPEC.md) — Lumen TUF Profile
- [THREAT_MODEL.md](../THREAT_MODEL.md) — Attacks addressed
- [SECURITY_INVARIANTS.md](../SECURITY_INVARIANTS.md) — Invariants enforced

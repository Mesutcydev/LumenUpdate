# Lumen Update — Incident Response

**Version:** 0.1 (Phase 0)
**Date:** 2026-07-31
**Status:** Accepted

This document defines the incident response playbooks for the Lumen Update framework. These playbooks cover key compromise, repository compromise, and malicious release scenarios.

---

## 1. Severity Classification

| Severity | Description | Response Time |
|----------|-------------|---------------|
| **Critical** | Active compromise in progress; users at immediate risk | < 1 hour |
| **High** | Confirmed compromise; users at risk if they update | < 4 hours |
| **Medium** | Potential compromise; investigation required | < 24 hours |
| **Low** | Suspicious activity; monitoring required | < 1 week |

---

## 2. Playbook 1: Compromised Timestamp Key

**Severity:** High
**Detection:** CI alerts, unexpected timestamp metadata changes, client reports of "metadata stale" errors

### 2.1 Immediate Actions (0-1 hour)
1. **Rotate the timestamp key immediately.**
   ```bash
   lumen timestamp rotate --reason "compromise-investigation"
   ```
2. **Invalidate in-flight updates.** The new timestamp metadata will supersede any in-flight malicious timestamp.
3. **Restrict CI runner access.** Lock down the CI runner that held the key.
4. **Preserve evidence.** Snapshot the CI runner's disk, logs, and network captures.

### 2.2 Short-Term Actions (1-24 hours)
1. **Investigate CI runner compromise.** How was the key leaked? Review:
   - CI runner access logs
   - Process listings at time of compromise
   - Network connections from the CI runner
   - Secret access logs
2. **Audit recent timestamp metadata.** Check the repository for any timestamp metadata signed by the compromised key.
3. **Notify users.** If any malicious timestamp was published, users will see "metadata stale" errors. Prepare a security advisory.

### 2.3 Long-Term Actions (1-7 days)
1. **Hardware security module.** Move the timestamp key to an HSM or dedicated signing service.
2. **Dedicated runners.** Use dedicated, hardened CI runners for signing operations.
3. **Key ceremony review.** Update the key ceremony to address the discovered vulnerability.

### 2.4 Recovery Criteria
- New timestamp key is in production
- CI runner is secured or replaced
- Investigation is complete
- Users are notified

---

## 3. Playbook 2: Compromised Targets Key

**Severity:** Critical
**Detection:** Unauthorized release published, security researcher report, anomaly detection

### 3.1 Immediate Actions (0-1 hour)
1. **Revoke the compromised targets key immediately.**
   ```bash
   lumen key revoke --keyID <id> --reason "targets-key-compromise"
   ```
2. **Use the second targets key (if still trusted) to sign a new targets metadata that excludes the compromised key.**
   ```bash
   lumen targets rotate --new-key <id> --revoke <compromised-id>
   ```
3. **If both targets keys are compromised, use the root to sign a new targets metadata.** This is an emergency root-anchored action.
4. **Halt all releases.** No new releases until the situation is resolved.

### 3.2 Short-Term Actions (1-24 hours)
1. **Identify the malicious release.** Which targets were signed by the compromised key?
2. **Assess user impact.** How many users received the malicious update? Check download metrics, version distribution telemetry (if available).
3. **Notify users.** Publish a security advisory with:
   - Affected versions
   - Recommended action (rollback, manual uninstall)
   - Timeline of events
4. **Coordinate with security researchers.** If reported by a researcher, acknowledge and coordinate disclosure.

### 3.3 Long-Term Actions (1-7 days)
1. **Reduce key holders.** Audit who has access to the targets key. Reduce to the minimum necessary.
2. **Implement multi-sig for targets.** Consider increasing threshold from 1-of-2 to 2-of-3.
3. **Hardware-backed signing.** Move targets keys to HSMs.
4. **Release approval workflow.** Add mandatory code review and approval step before any release.

### 3.4 Recovery Criteria
- Compromised key is revoked
- New targets metadata is published and accepted by clients
- No users are running malicious versions
- Post-mortem is published

---

## 4. Playbook 3: Compromised Root Key

**Severity:** Critical
**Detection:** Security audit, anomaly detection, researcher report

### 4.1 Immediate Actions (0-1 hour)
1. **Treat as catastrophic trust anchor failure.** The root is the trust anchor; compromise means the entire update system is untrusted.
2. **Trigger emergency key ceremony.** Prepare to generate new root keys.
3. **Coordinate via out-of-band channel.** Root compromise requires communication outside the normal update channel (email, phone, in-person).

### 4.2 Short-Term Actions (1-24 hours)
1. **Generate new root keys on fresh hardware.** This is a full key ceremony.
2. **Sign new root metadata with the remaining OLD root keys (if any are still trusted).**
   - If 2-of-3 old keys are still trusted, sign with those.
   - If fewer than 2 old keys are trusted, this is a full bootstrap failure.
3. **Publish new root metadata to all clients.** Clients will only accept the new root if signed by the threshold of OLD root keys.
4. **If full bootstrap failure:** A new application version with a new bundled root must be distributed out-of-band. Users must manually approve (Gatekeeper dialog). This is a manual update.

### 4.3 Long-Term Actions (1-7 days)
1. **Audit all keys for compromise.** If root was compromised, assume all derived keys are also compromised.
2. **Re-derive all keys.** Generate new targets, snapshot, and timestamp keys under the new root.
3. **Publish post-mortem.** Document the compromise, response, and lessons learned.

### 4.4 Recovery Criteria
- New root is published and accepted
- All derived keys are rotated
- Users are running updates verified by the new root
- Post-mortem is published

---

## 5. Playbook 4: Compromised Repository Server

**Severity:** High
**Detection:** Unexpected metadata changes, CDN alerts, anomaly detection, user reports

### 5.1 Immediate Actions (0-1 hour)
1. **Switch to backup repository.** If a secondary repository is configured, switch the CDN or DNS to point to the backup.
2. **Revoke current root if necessary.** If the server compromise includes access to signing keys, trigger root rotation.
3. **Take the compromised server offline.** Preserve evidence before rebuilding.

### 5.2 Short-Term Actions (1-24 hours)
1. **Forensic analysis.** How was the server compromised? Review access logs, process history, network connections.
2. **Audit metadata.** Check all metadata served during the compromise window for unauthorized changes.
3. **Restore from known-good backup.** If a known-good repository snapshot exists, restore from it.
4. **Re-sign all metadata if necessary.** If any metadata was tampered with, re-sign with trusted keys.

### 5.3 Long-Term Actions (1-7 days)
1. **Multi-mirror with independent signing.** Set up multiple mirrors, each with independent signing capability.
2. **Server hardening.** Review and harden the repository server configuration.
3. **Monitoring.** Add anomaly detection for metadata changes.

### 5.4 Recovery Criteria
- Backup repository is serving known-good metadata
- Compromised server is rebuilt and hardened
- All metadata is verified against trusted keys
- Monitoring is in place

---

## 6. Playbook 5: Malicious Release Published

**Severity:** Critical
**Detection:** Hash mismatch in client, bundle manifest verification failure, user report

### 6.1 Immediate Actions (0-1 hour)
1. **Identify the malicious release.** Which version is affected? What was the payload?
2. **Publish a new release immediately.** The new release will supersede the malicious one for clients that haven't updated yet.
   ```bash
   lumen release create --from-build <good-build-id> --notes "Security: rollback of malicious release <id>"
   lumen publish
   ```
3. **Halt the release pipeline.** No new releases until the source of compromise is identified.
4. **Preserve evidence.** Save the malicious release, the signing logs, and any related metadata.

### 6.2 Short-Term Actions (1-24 hours)
1. **Investigate the source.** How was the malicious release created? Was the build pipeline compromised? Was a key compromised?
2. **Assess user impact.** How many users installed the malicious release?
3. **Notify users.** Publish a security advisory:
   - Which version is affected
   - How to identify if they have it
   - Recommended action (update immediately, or manual uninstall)
4. **Coordinate with security researchers.** If reported, coordinate disclosure.

### 6.3 Long-Term Actions (1-7 days)
1. **Build pipeline hardening.** Reproducible builds, out-of-band verification, multi-party review.
2. **Key rotation.** If key compromise is suspected, rotate the relevant key.
3. **Post-mortem.** Document the incident and lessons learned.

### 6.4 Recovery Criteria
- New release is published and clients have updated
- No users are running the malicious version
- Source of compromise is identified and remediated
- Post-mortem is published

---

## 7. Communication Plan

### 7.1 User Notification
- **Release notes:** Include security notices in subsequent releases
- **Security advisory:** Publish on the project website and security mailing list
- **GitHub Security Advisory:** If the project is on GitHub, use the security advisory feature
- **In-app notification:** If possible, show a notification in the host application

### 7.2 Security Researcher Coordination
- Acknowledge receipt within 24 hours
- Provide regular updates (at least every 72 hours)
- Coordinate disclosure timing
- Credit the researcher in the advisory (if they wish)

### 7.3 Post-Mortem
- Published within 14 days of resolution
- Includes: timeline, root cause, impact, remediation, lessons learned
- Transparent about failures and improvements

---

## 8. Roles and Responsibilities

| Role | Responsibilities |
|------|-----------------|
| **Incident Commander** | Coordinates the response, makes key decisions |
| **Security Lead** | Technical investigation, forensic analysis |
| **Communications Lead** | User and researcher communications |
| **Release Manager** | Coordinates new releases and key rotations |
| **Operations Lead** | Infrastructure changes (CDN, repository) |

---

## 9. Pre-Incident Preparation

To enable effective incident response:
- **Document the key ceremony** in detail
- **Maintain an out-of-band contact list** (not stored in the repository)
- **Test the incident response process** annually with a tabletop exercise
- **Keep CI runner logs** for at least 90 days
- **Monitor metadata changes** with anomaly detection
- **Have a backup repository** ready to switch to

---

## 10. Cross-References

- [THREAT_MODEL.md](./THREAT_MODEL.md) — Threats that trigger these playbooks
- [SECURITY_INVARIANTS.md](./SECURITY_INVARIANTS.md) — Invariants that may be violated during an incident
- [KEY_MANAGEMENT.md](./KEY_MANAGEMENT.md) — Key rotation procedures used in these playbooks
- [SPEC.md](./SPEC.md) — Protocol details for emergency operations

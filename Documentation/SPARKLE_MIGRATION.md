# Sparkle Migration Guide

Migrating from Sparkle to Lumen requires a **bridge release** — a transitional update that contains both Sparkle and Lumen, signed with your existing Sparkle key.

---

## Why a Bridge Release?

Sparkle's trust model is based on the EdDSA (Ed25519) key embedded in your appcast. Users' Sparkle installations trust YOUR Sparkle key. Lumen uses a different trust model (TUF root metadata). You cannot simply swap one for the other — the trust transfer must happen inside an update authenticated by the OLD updater (Sparkle).

**If you've lost your Sparkle private key**, seamless migration is not secure. The fallback is a manually installed new application that bootstraps the Lumen root.

---

## Migration Steps

### Step 1: Prepare Lumen Infrastructure

```bash
lumen key generate --role root
lumen key generate --role targets
lumen key generate --role snapshot
lumen key generate --role timestamp
lumen root create --root-key root.key --targets-key targets.pub \
  --snapshot-key snapshot.pub --timestamp-key timestamp.pub
lumen init --product-id com.example.myapp
```

### Step 2: Build the Bridge Release

The bridge release is a normal application update that:

1. **Contains the Lumen framework** (LumenUpdateSDK.framework)
2. **Bundles the Lumen root metadata** (root.json in Contents/Resources/)
3. **Retains Sparkle** (Sparkle.framework still present)
4. **Includes a migration marker** (e.g., a file or UserDefaults flag)
5. **Is signed with your existing Sparkle Ed25519 key**

```
MyApp.app/
├── Contents/
│   ├── Frameworks/
│   │   ├── Sparkle.framework        ← retained
│   │   └── LumenUpdateSDK.framework ← added
│   ├── Resources/
│   │   └── root.json                ← Lumen root metadata
│   └── Info.plist
```

### Step 3: Publish via Sparkle

Sign and publish the bridge release through your existing Sparkle appcast:

```bash
# Use Sparkle's generate_appcast tool or your existing CI pipeline
# The bridge release MUST be signed with your Sparkle Ed25519 key
```

### Step 4: Wait for Adoption

Monitor your analytics. Wait until a sufficient percentage of users have updated to the bridge release.

### Step 5: Lumen Initializes

On first launch of the bridge release, Lumen:
1. Reads the bundled root.json
2. Verifies it is self-signed
3. Stores it as the trusted root
4. Begins checking for updates via Lumen

### Step 6: Publish Next Release via Lumen

```bash
lumen package ./MyApp.app
lumen release create --artifact MyApp-2.0.aar --manifest MyApp-2.0.bundle-manifest.json \
  --targets-key targets.key --snapshot-key snapshot.key --timestamp-key timestamp.key \
  --product-id com.example.myapp
lumen publish --repository ./UpdateRepository --destination <hosting>
```

In this release, Sparkle is retained but **disabled** (SUEnableAutomaticChecks = NO).

### Step 7: Remove Sparkle

In a subsequent release, remove Sparkle.framework entirely. Lumen is now the sole updater.

---

## Importing Sparkle Release History

```bash
lumen migrate sparkle ./appcast.xml
```

This converts your Sparkle appcast XML into Lumen target metadata. It does NOT transfer client trust — that happens via the bridge release.

---

## Migration Diagnostics

```bash
lumen transaction inspect --bundle /Applications/MyApp.app
```

This reports:
- Whether Sparkle.framework is present
- Whether LumenUpdateSDK.framework is present
- Whether root.json is bundled
- The current migration state

---

## Fallback: Lost Sparkle Key

If your Sparkle Ed25519 private key is lost:

1. **You cannot publish a Sparkle-signed update.**
2. **Users must manually download and install the new version.**
3. The new version bootstraps the Lumen root.
4. Document this clearly for your users.

This is the **bootstrapping problem**: there is no secure way to transfer trust without the old key.

---

## Cross-References

- [ACCOUNTLESS_DISTRIBUTION.md](./ACCOUNTLESS_DISTRIBUTION.md) — Accountless mode details
- [KEY_MANAGEMENT.md](./KEY_MANAGEMENT.md) — Key rotation and recovery
- [ADR-005-accountless-trust.md](./ADR-005-accountless-trust.md) — Trust model rationale

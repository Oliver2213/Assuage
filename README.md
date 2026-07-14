# Assuage

> An [age](https://age-encryption.org) encryption interface for macOS: encrypt and
> decrypt files and text from anywhere on your Mac, with keys you can keep in the
> Secure Enclave.

Assuage brings the power of modern cryptography to the macOS UI and to the system
itself. It aims for secure, sensible defaults, native platform integration, and
data-first design where invalid states can't be represented.

---

## Trust model

**All cryptography is pure in-process Swift** — there are **no third-party binaries
and no subprocesses** anywhere in what ships. Crypto runs through Apple's CryptoKit
and the [AgeKit](https://github.com/Oliver2213/AgeKit) Swift implementation of age.
Secure Enclave support is a native re-implementation of `age-plugin-se`'s wire
format, not a bundled copy of the plugin. There is nothing to trust for the crypto
but the app, Apple's frameworks, and one small vendored, auditable Bech32 file.

The `.app` **does** bundle additional binaries beyond the main executable, but they
are all **our own first-party code** — macOS *app extensions* that push the app's
reach into other parts of the system (Finder, Quick Look). They add no new trust
surface: each either links the *same* audited Swift core the app does, or ships no
crypto at all. Specifically:

- **Finder Quick Actions** (`EncryptAction` / `DecryptAction`) — headless Action
  Extensions with **no crypto and no keys**. They don't even link the core; they
  just forward the selected files to the app via LaunchServices and quit. All
  encryption/decryption still happens in the one app process.
- **Quick Look preview** (`QLExtension`) — links the Swift core (`AssuageCore`) and
  uses its header-only inspector to render an `.age` file's metadata as a preview.
  It reads the age header; it never decrypts payloads.

Interoperability is verified against real age implementations, so files produced by
Assuage work with the wider age ecosystem and vice versa.

---

## Features

### Implemented

**Encryption / decryption**
- Encrypt text or files to **one or more recipients** across every supported key type.
- **Mixed recipients** on a single file (e.g. a software key *and* a Secure Enclave key).
- **Passphrase (scrypt)** encryption and decryption, for text or files, when you'd
  rather not manage keys.
- **Binary or ASCII-armored** output.
- Decrypt with one or more identities (or a passphrase); armored input is detected
  automatically.
- **Streaming with progress**: bytes processed / total / throughput, for large files.
- **Folders**: a folder is zipped before encryption and restored on decrypt.
- **"Check if decryptable"**: reads only the age header to determine whether one of
  your keys is a recipient — without decrypting the payload.

**Keys**
- Generate keypairs of several types:
  - **age X25519** — the standard age key, exportable and usable with any age tool.
  - **age post-quantum (X-Wing)** — a hybrid ML-KEM-768 + X25519 key, exportable and
    usable with age 1.3 or later (requires macOS 26).
  - **Secure Enclave (P-256)** — the private key is generated in, and never leaves,
    the enclave; wire-compatible with `age-plugin-se`.
  - **Secure Enclave post-quantum (ML-KEM-768 + P-256)** — both private halves sealed
    in the enclave, so device-bound and quantum-secure (requires macOS 26).
- Secure Enclave **access-control chosen per key at generation**: none, passcode,
  any/current biometry, and biometry-and/or-passcode combinations. Using a
  presence-protected key prompts for Touch ID / passcode at decrypt time.
- **Import** age identities and **SSH Ed25519** private keys (including
  passphrase-protected OpenSSH keys); SSH keys become recipients and identities like
  any other. Export the full identity or **public key only**, formatted the way age
  formats generated keys (a comment header with the app name, creation date, access
  control, and public key, then the private key line); SSH keys export as OpenSSH.
- **Keychain persistence** with a **storage choice per key**: synced across your
  devices via iCloud Keychain, this Mac only, or **Touch ID–protected** (wrapped by
  the Secure Enclave, so it isn't decryptable at rest even while the keychain is
  unlocked). Enclave keys never sync.

**System integration** (all via first-party app extensions — see Trust model)
- **Services** for **Encrypt**, **Decrypt**, and **Check** that accept selected
  **text or files**, so they appear in the system-wide *Services* menu and in
  **Finder's** right-click menu. A crypto tool shouldn't silently rewrite other
  apps' data, so each service brings the app forward with the content loaded into
  the right panel (choose recipients, then encrypt) rather than transforming the
  pasteboard in place.
- **Finder Quick Actions** — *Encrypt with Assuage* / *Decrypt with Assuage* on the
  right-click menu for files and folders. The action forwards the selection to the
  app (no crypto in the extension); the app infers encrypt vs. decrypt from the
  contents and loads it into the right panel. Folders are zipped before encryption.
- **Quick Look preview** of `.age` files — press Space in Finder to see the file's
  age metadata (recipients/stanza types) without opening or decrypting it.

**App**
- Native SwiftUI Mac app: `NavigationSplitView` with Encrypt / Decrypt / Keys panels,
  drag-and-drop file wells, queued-file lists, native controls (free VoiceOver
  labels), menu command to generate a keypair (⌘K).

### Planned / deferred

- **Contacts association**: attach an age public key to a system contact and pick a
  person (filtered to those with keys) as a recipient.
- **Shamir Secret Sharing** (`age-plugin-sss`): threshold identities (need *k* of *n*
  keys to decrypt), with nested/subkey policies. Requires a subprocess, so it's gated
  on a decision about bundling.
- **App Sandbox / Mac App Store variant**: the app currently runs non-sandboxed to
  work on files anywhere. A sandboxed variant (security-scoped bookmarks + entitlements)
  is planned, potentially shipping first for discoverability.

---

## Architecture

A testable core package, a native app, and a set of first-party app extensions that
share that core. All crypto lives in the core; everything above it is UI or a thin
system-integration shell that calls in.

### `AssuageCore` (local Swift 6 package)

All cryptographic logic, unit-tested with fast `swift test` (no Xcode/simulator).
Depends on AgeKit. Platform floor macOS 15.

| Type | Responsibility |
| --- | --- |
| `Cipher` | Encrypt / decrypt / inspect. Text and file APIs; armored or binary; recipient keys or a passphrase; streaming with a `ProgressHandler`. `canDecrypt` inspects the header only. |
| `AgeRecipient` | A validated public recipient (`age1…`, `age1se1…`, `age1tagpq…`, or an `ssh-ed25519` line). Construction validates the encoding, so the value is always well-formed. |
| `AgeIdentity` | An identity: `id`, `label`, `created`, `material`, derived `recipient`. |
| `IdentityMaterial` | The private material, with *where it lives* encoded in the case: `.x25519` / `.postQuantum` / `.sshEd25519` (keychain-backed) or `.secureEnclave` / `.secureEnclavePostQuantum` (enclave-backed). An identity can't claim a source it doesn't have (no nullable secret paired with a separate flag that could disagree); `source` and `storage` are derived. |
| `SecureEnclaveRecipient` / `SecureEnclaveIdentity` | Native re-implementation of age-plugin-se's `piv-p256` / `p256tag` stanza crypto (P-256 ECDH + HKDF + ChaChaPoly). |
| `SecureEnclaveKeys` | Generate / load Secure Enclave keys; availability check. |
| `SecureEnclaveAccessControl` | Presence policy → `SecAccessControl`, mirroring age-plugin-se. |
| `CompositeRecipient` / `CompositeIdentity` | Fan a file key out to N recipients / try N identities, working around AgeKit's variadic-only `encrypt`/`decrypt` without forking it. |
| `Armoring` | age's PEM-style base64 armor (encode / decode / detect). |
| `Bech32` (vendored) | Bech32 used for Secure Enclave encodings, vendored from age-plugin-se for byte-identical output. |

### `Assuage` (SwiftUI app, macOS-only, Swift 6)

| Area | Types |
| --- | --- |
| State | `AppModel` (`@Observable`: identities, panel selection, compose state), `CryptoEngine` (runs blocking crypto off the main actor, streams `CryptoProgress` back). |
| Persistence | `IdentityStore` (data-protection keychain, one item per identity, value = JSON). |
| UI | `ContentView` (split view + Service dispatch), `EncryptView`, `DecryptView`, `KeysView`, `GenerateKeySheet`, plus `RecipientSelector`, `IdentityRow`, `FileWell`, `QueuedFilesList`, `ProgressStrip`, `InfoBanner`. |
| Services | `ServiceProvider` (AppKit `NSObject` reading text/files from the pasteboard), `ServiceBus` (bridges to SwiftUI), `AppDelegate` (registers the provider), `Info.plist` `NSServices`. |

### App extensions (embedded `.appex` bundles)

Separate targets, each its own bundle embedded in the app. They extend the app into
other parts of macOS without moving any crypto out of the app process.

| Target | Extension point | Role |
| --- | --- | --- |
| `EncryptAction` / `DecryptAction` | Action Extension (Finder Quick Actions + Services) | Headless forwarders — no crypto, no keys, don't link the core. Resolve each selected item's file URL and open the app via LaunchServices, which grants the app access to the selection. Activation rules gate them: Encrypt for any item, Decrypt only when every item is a `.age` file. The app infers encrypt vs. decrypt from the bytes. |
| `QLExtension` | Quick Look Preview | Links `AssuageCore` and uses its header-only `AgeFileInspector` to render an `.age` file's metadata in a preview. Reads the header only; never decrypts. |

### Concurrency

The app defaults to `MainActor` isolation. AgeKit's streaming primitives are
synchronous and blocking, so `CryptoEngine` runs them in a detached task and forwards
progress to the main actor via an `AsyncStream`; domain types are `Sendable`.

---

## Cryptographic details

- **age X25519**: standard age recipients (`age1…`) / identities (`AGE-SECRET-KEY-1…`).
- **age post-quantum (X-Wing)**: hybrid ML-KEM-768 + X25519 recipients / identities
  (`AGE-SECRET-KEY-PQ-1…`), matching age 1.3's built-in post-quantum keys.
- **Secure Enclave**: recipients `age1se1…`, identities `AGE-PLUGIN-SE-1…`. P-256
  key-agreement key generated in the enclave; the identity string encodes the
  device-bound key blob. Wrapping matches age-plugin-se exactly (HKDF label
  `piv-p256`, all-zero 12-byte nonce, 4-byte public-key tag for cheap
  recipient-matching before touching the enclave).
- **Secure Enclave post-quantum**: `age1tagpq…` (`mlkem768p256tag`) recipients whose
  payload pairs an ML-KEM-768 key with a P-256 enclave blob, again wire-compatible
  with age-plugin-se.
- **SSH Ed25519**: `ssh-ed25519 AAAA…` recipients; identities are the OpenSSH private
  key (only the 32-byte seed is retained after import). RSA / ssh-agent are out of scope.
- **Passphrase (scrypt)**: a passphrase stanza (age's default work factor) as the sole
  recipient, per the age spec.
- **Armor**: `-----BEGIN AGE ENCRYPTED FILE-----` … base64 wrapped at 64 columns.
- **Header inspection**: `Cipher.canDecrypt` runs the unwrap + header-MAC check but
  never reads plaintext, so it reveals recipient membership without decrypting.

---

## Testing

`swift test` in `AssuageCore` — round trips (binary / armored / multi-chunk /
multi-recipient), identity import/export, Codable persistence, Secure Enclave round
trips on real hardware, and **interop both directions** with:

- the real **`rage`** CLI, and
- the real **`age-plugin-se`** binary (via `rage` with the plugin on `PATH`).

Interop and Secure Enclave suites skip automatically when the tools / hardware are
absent. Secure Enclave tests use `none` access control to run headless.

---

## Dependencies & modifications

- **AgeKit** — the age implementation. We use our fork,
  [Oliver2213/AgeKit](https://github.com/Oliver2213/AgeKit) (local checkout at
  `~/src/AgeKit`, branch `assuagefixes`). One minimal patch: `Age.Stanza`
  was made publicly constructible/readable (its fields and `init(type:args:body:)`
  were `internal`), which its public `Recipient`/`Identity` protocols require to be
  usable by external conformers such as the Secure Enclave recipient.
- **Reference (not linked)**: `age-plugin-se` (Secure Enclave wire format, Bech32) and
  `age-plugin-sss` (future Shamir support).

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
- Encrypt text or files to **one or more recipients** (age X25519 and Secure Enclave).
- **Mixed recipients** on a single file (e.g. a software key *and* a Secure Enclave key).
- **Binary or ASCII-armored** output.
- Decrypt with one or more identities; armored input is detected automatically.
- **Streaming with progress**: bytes processed / total / throughput, for large files.
- **"Check if decryptable"**: reads only the age header to determine whether one of
  your keys is a recipient — without decrypting the payload.

**Keys**
- Generate **age X25519** keypairs (software) or **Secure Enclave** keypairs (the
  private key is generated in, and never leaves, the enclave).
- Secure Enclave **access-control chosen per key at generation**: none, passcode,
  any/current biometry, and biometry-and/or-passcode combinations. Using a
  presence-protected key prompts for Touch ID / passcode at decrypt time.
- Import identities from age key files; export the full identity or **public key only**,
  formatted the way age formats generated keys (a comment header with the app name,
  creation date, access control, and public key, then the private key line).
- **Keychain persistence** (data-protection keychain, `ThisDeviceOnly`) so keys
  survive relaunch and never sync off the Mac.

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
- **SSH recipients**: use ssh-ed25519 / ssh-rsa public keys as recipients.
- **Shamir Secret Sharing** (`age-plugin-sss`): threshold identities (need *k* of *n*
  keys to decrypt), with nested/subkey policies. Requires a subprocess, so it's gated
  on a decision about bundling.
- **Passphrase (scrypt)**: AgeKit can encrypt to a passphrase but its `ScryptIdentity`
  initialiser is internal, so decryption is currently unreachable — deferred to avoid
  an encrypt-but-can't-decrypt trap.
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
| `Cipher` | Encrypt / decrypt / inspect. Text and file APIs; armored or binary; streaming with a `ProgressHandler`. `canDecrypt` inspects the header only. |
| `AgeRecipient` | A validated public recipient (`age1…` or `age1se1…`). Construction validates the encoding, so the value is always well-formed. |
| `AgeIdentity` | An identity: `id`, `label`, `created`, `material`, derived `recipient`. |
| `IdentityMaterial` | `.x25519(secretKey, storedAt:)` or `.secureEnclave(identity, accessControl:)`. Location lives *in the case*, so an identity can't claim a source it doesn't have (no nullable secret paired with a separate flag that could disagree). `source` is derived. |
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
- **Secure Enclave**: recipients `age1se1…`, identities `AGE-PLUGIN-SE-1…`. P-256
  key-agreement key generated in the enclave; the identity string encodes the
  device-bound key blob. Wrapping matches age-plugin-se exactly (HKDF label
  `piv-p256`, all-zero 12-byte nonce, 4-byte public-key tag for cheap
  recipient-matching before touching the enclave).
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

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Assuage** is a native macOS [age](https://age-encryption.org) app: encrypt/decrypt files & text, manage keys (software, Secure Enclave, SSH, post-quantum), and sign/verify [C2SP signed notes](https://c2sp.org/signed-note). All cryptography is in-process Swift — no subprocesses, no third-party crypto binaries. See `README.md` for the full feature and trust-model writeup and `specs/` (`age.md`, `signed-note.md`) for on-the-wire formats.

> The repo directory is currently named `Cypherdex` (the app's old name) and **will likely be renamed**. Don't hard-code the `Cypherdex` path anywhere; derive paths, and expect memory entries that reference `Cypherdex`/`CypherdexCore` to be pre-rename artifacts.

## Build, test, run

- **Core logic tests — the fast primary loop:** `cd AssuageCore && swift test`. Pure Swift, no Xcode/simulator. Filter with `swift test --filter SignedNoteTests` or `--filter SignedNoteTests/someCase`. All crypto is exercised here; run it after any `AssuageCore` change. Uses Swift Testing.
- **Build the app:** prefer the Xcode MCP (`mcp__xcode__BuildProject`). **Do not assume the tab identifier is `windowtab1`** — call `mcp__xcode__XcodeListWindows` first and use the real one. CLI fallback: `xcodebuild -project Assuage.xcodeproj -scheme Assuage build`.
- **Run:** it's a GUI app — launch from Xcode's Run.
- **Interop / hardware tests self-skip when tooling is absent.** `RageInteropTests` needs `rage` on `PATH`; `SecureEnclaveInteropTests` also needs the real `age-plugin-se` binary; Secure Enclave suites need real hardware (they use `.none` access control to run headless). Signature tests verify rather than byte-compare (see Gotchas).

## Architecture

Three layers, with **all cryptography confined to the bottom one**.

1. **`AssuageCore/`** — local SwiftPM package, every bit of crypto, unit-testable without Xcode. Swift 6 language mode; platform floor macOS 15 / **iOS 18** (the core is already cross-platform). Key types: `Cipher` (encrypt/decrypt/inspect), `AgeIdentity` + `IdentityMaterial`, `SecureEnclave*` (native re-implementation of `age-plugin-se`'s wire format — **not** a bundled plugin), `SignedNote`/`SigningIdentity`/`VerifierKey`, `Composite*`, vendored `Bech32`.
2. **`Assuage/`** — the SwiftUI app (`Model/`, `Views/`, `Services/`, `Support/`). UI and app state only; calls into the core for anything cryptographic.
3. **App extensions** — `EncryptAction`/`DecryptAction`: **headless Finder Quick Action + Service forwarders with no crypto and no keys** (they don't link the core; they hand file URLs to the app via LaunchServices). `QLExtension`: links the core to render an `.age` header as a Quick Look preview (header-only; never decrypts).

### The AgeKit fork

The core depends on a **fork of AgeKit** referenced by local path (`~/src/AgeKit`, remote `github.com/Oliver2213/AgeKit`, branch **`assuagefixes`**). It is **not** a one-line patch — the fork carries: `Age.Stanza` made public (external Recipient/Identity conformers like Secure Enclave); a header-MAC fix (stanza bodies must wrap at 64 columns, else decrypting real age/rage output with a long grease stanza throws `.badHeaderMAC` — see `GreaseInteropTests`); the swift-nio dependency dropped for a small Foundation byte reader; `ScryptIdentity` made public with wrong-passphrase → `incorrectIdentity`; a full ssh-ed25519 recipient/identity port of age's `agessh` (plus seed/authorized-key/OpenSSH serialization); an HPKE key schedule; and the post-quantum recipients/identities (`mlkem768x25519` X-Wing and `mlkem768p256tag` tagged). When something in AgeKit blocks you, patching the fork is on the table — but keep patches minimal and verified wire-compatible with `rage` both directions.

### Data-first modeling (core convention)

Make invalid states unrepresentable rather than validating after the fact. `IdentityMaterial`'s enum case *is* where the secret lives (`.x25519`/`.postQuantum`/`.sshEd25519` keychain-backed; `.secureEnclave*` enclave-backed), so `source`/`storage` are derived and an identity can't claim a backing it lacks. Follow this when extending the model.

### Key taxonomy

Encryption and signing keys coexist but are kept strictly separate.
- **Encryption:** age X25519 (`age1…`), software post-quantum X-Wing (`age1pq…`), Secure Enclave P-256 (`age1se1…`), Secure Enclave post-quantum `mlkem768p256tag` (`age1tagpq…`). The two Secure Enclave types are wire-compatible with `age-plugin-se` and identity-portable both directions. SSH: `ssh-ed25519` recipients / OpenSSH private-key identities (32-byte seed retained). Post-quantum requires macOS 26 — gate with `if #available(macOS 26, *)`.
- **Signing:** Ed25519 note-signing keys (C2SP signed-note), where the signer name is **hashed into the 4-byte key ID** — the same key material under a different name is a different verifier key.

### App state & shared libraries

- `KeyLibrary` (`@Observable @MainActor`) is the keychain-backed store of all identities and signing keys; secrets are stripped from in-memory copies and **hydrated on demand right before** signing/decrypt/export (batched so a set of Touch ID–protected keys prompts once). `PeopleLibrary` is the contacts-backed store (loads lazily on view appearance). Both expose a `static let shared` used by every window **and** by the window-less Services.
- `AppModel` is **per-window** compose state (input, queues, panel selection, sheet routing) wrapping the shared `KeyLibrary`; menu commands target the active window via `@FocusedValue(\.appModel)`. `CryptoEngine` runs blocking crypto off the main actor and streams progress back.
- Settings are **global** (`@AppStorage`/`PreferenceKeys` + the `Settings` scene), deliberately not per-window.
- **Contacts are the source of truth for others' public keys** (age/ssh/verifier), stored on the contact card as custom-labeled URL fields — no parallel database. Note-verification trust = the verifier keys found on contacts.

### System integration (Services)

`ServiceProvider` (registered as `NSApplication.servicesProvider`; `@objc` method names match `NSMessage` in `Assuage/Info.plist`), `AppDelegate` (file opens), `ServiceBus` (AppKit → SwiftUI). Deliberate behavioral split: **encrypt/decrypt/check bring the app forward** with content loaded (a crypto tool shouldn't silently rewrite other apps' data); **sign transforms the selection in place** (synchronous, no window, reads keys straight from the keychain); **verify opens a standalone AppKit panel** (`VerifyPanel`). Adding a Service means editing both `ServiceProvider` and the `NSServices` array in `Info.plist`; after building, the Services menu may need a relaunch (or re-login) to refresh.

## Product principles

This is aiming to be a **genuinely great, Mac-assed Mac app** — hold that bar:

- **Multiple affordances for the same task.** Files should be addable by drag-and-drop *and* an "Add files" button; keys usable from a list *and* a context menu. Don't hide a capability behind a single gesture.
- **Context menus everywhere** they'd help, backed by real menu-bar/toolbar commands. Native controls (free VoiceOver), native windows/panels, keyboard shortcuts for frequent commands. Use the `mac-assed-mac-app` skill for UI-shape questions.
- **Novice-legible, actionable copy.** Users may not know encryption concepts. UI text should be understandable and tell them what to *do*, not just name a primitive. (A fuller user's guide is planned; write copy that will still make sense alongside it.)
- **Review new UI with the `swiftui-pro` skill** before considering it done.
- **iOS is coming** (core functionality is largely complete barring MailKit). Keep new logic platform-agnostic where practical; the core already targets iOS 18. Don't import iOS patterns into the Mac app, but don't wall logic into macOS-only code without reason.

## Engineering conventions

- **Target modern Swift (6.4) and modern async/await** where it fits — prefer structured concurrency over callbacks; keep `Sendable`/actor isolation honest.
- **Logging is expected on new code, by default.** Add a categorized `Logger` to the `Log` enum (`Assuage/Support/Log.swift`) — every logger is namespaced to `AppInfo.bundleIdentifier` (`dev.smoll.Assuage`) with a `category`. Annotate anything sensitive (names, contact identifiers, key material) with `privacy:`; string interpolations are redacted by default and the code relies on that.
- **Data-first, and tested** — add `swift test` coverage in `AssuageCore` for new core behavior.
- **Keep code organized and readable for humans** — one type per file; match the surrounding doc-comment density, which leans on explaining *why*.

## Gotchas

- **The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — every type in the `Assuage` target is implicitly `@MainActor` unless marked `nonisolated` (so `@objc` Service methods run on the main thread). `AssuageCore` does **not** use this default. Keep it in mind when reasoning about what runs where.
- **SourceKit routinely emits false positives** here — `No such module 'AssuageCore'` and same-module `Cannot find 'X' in scope` appear even though the build succeeds. **Trust the build result, not live diagnostics.**
- **CryptoKit Ed25519 signatures are randomized (hedged), not deterministic RFC 8032** — the same key/message gives different bytes each run (all valid). Never byte-compare a signature in a test; verify it instead (test that a *published* signature verifies against its published key, and that fresh signatures verify).
- **AgeKit interop edges baked into `AssuageCore`:** `encrypt`/`decrypt` are variadic-only, so a dynamic `[Recipient]` goes through `CompositeRecipient`/`CompositeIdentity` (`Composite.swift`) rather than forking the kit. `StreamReader` has no clean EOF — it throws an internal `.unexpectedEOF` on the read *after* the final chunk, which `Cipher.swift` detects by string (`"\(error)" == "unexpectedEOF"`) while rethrowing real decrypt failures. Header inspection (`Cipher.canDecrypt`) does the unwrap + header-MAC check without reading plaintext, so "am I a recipient?" is answerable without decrypting.

## Commit messages & memory

- Don't enumerate modified file names in commit messages ("git carries that") unless the list adds information beyond the names. Keep the co-author trailer.
- Durable cross-session context lives in the memory directory indexed by `memory/MEMORY.md`. Some entries predate the Assuage rename and the AgeKit fork — **verify a memory against the code before relying on it** (e.g. branch names, "not done yet" notes, `CypherdexCore` naming).

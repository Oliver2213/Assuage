# TODO

* [x] Clipboard import (encrypt/decrypt from clipboard content)

* Wipe private key material from memory once it's persisted. After generate/import the in-memory identity still holds its secret (private) half, so (a) an authenticated key can be used right after creation *without* a Touch ID prompt, and (b) the secret lingers in memory while unused. Fix: once `store.save` confirms the secret is written to the keychain, replace the in-memory identity with a secret-less copy (as `loadAll` already returns), so every operation re-hydrates on demand — forcing the auth prompt and keeping no private material around when idle. Applies to `KeyLibrary.add` / `importIdentities`.

* age-agent! Was reading the age plugin spec and it briefly mentions an outline for them
  A shim binary age-plugin-assuagent or something calls out / starts up the main app.
  Users should be able to create... Idk. "agent identities" or something, which represent a set of their keys.
  So the app might suggest "all keys", "all secure enclave keys" (better name for users), and these are dynamic and the public key stays the same as they add keys / remove them.
  (option to have this not be the case, regenerate this key invalidating the old public key when the dynamic list changes)
  My read of plugin spec suggests these agent identity keys are short-lived, so might change on app restart regardless. Option for this probably as well // fold it into above.

* Stretch / harder for me to test directly:: if you have a keys window open, you should be able to drag it to an encrypt or decrypt list, our standard UI view for that.

* Do we support passphrase encrypted age files as identities when decrypting? Do we support importing an encrypted identity (with a passphrase)?
* QuickLook **Thumbnail** extension: a lock-badge thumbnail for `.age` files
* Menu-bar extra (NSStatusItem): "Encrypt clipboard / Decrypt clipboard" in one click — pairs with clipboard import
* Recipient address book: saved named public keys you don't own, so you can encrypt to "Alice" without pasting her key each time. Import from file/clipboard, plus **recipient groups** for multi-recipient encryption
* Recipient QR code (show/scan) for phone transfer

* contacts integration:
  * When the user has requested for us to do so, ask for contacts access (we may and probably should get back only a small list of select contacts rather than the full db's list)
  * look for contacts with a specifically named field for age or ssh public keys.
(probably no standard name for these already, but better to check)
  * Surface those contacts along with the user's keys when encrypting or decrypting,
and by default encrypt to all the given contact's keys. Probably some Ui / button once a person is added to tweak their keys used for a given encrypt operation.
IE support fine grain control over which keys are used for a given contact but have a reasonable default.
  * A preference that determines this behavior: use all keys for a contact, use the first, last, pick each time.

* mail kit extension to provide signing / encryption to mail
  This is probably a later one after contacts, at least to add integrated "given an email address, can we sign or encrypt to it" functionality the extension lets us add.
* share extension: quickly encrypt a file or text to a given key or person, then return it for sharing
* Action extension?: encrypt given file or data. Might not be needed because of other ways: finder integration, share
* iMessage app to enc / dec in a conversation. This is mostly pointless except for sms or unencrypted RCS, but maybe.
* stretch / time goal: intents for the 27 releases, so siri knows what the app does and can access its functions on user's behalf

* Archive / compression options for folder encryption (currently: folder -> `.zip` (deflate) via NSFileCoordinator, then age-encrypt; decrypt leaves the `.zip`).
  Better ratios are available first-party and in-process (sandbox-safe, no dependency):
  * AppleArchive framework: folder trees with LZFSE (balanced) or LZMA (~7z-tight) -> `.aar`. Small code. Downside: `.aar` is macOS-centric (expands via built-in `aa` or our app; Finder double-click support is inconsistent).
  * Compression framework: LZFSE/LZMA/LZ4/zlib but single-stream only (no directory tree).
  * `.7z` / `.tar.xz` *format* (Windows 7-Zip / Linux interop): needs libarchive — ships and reads+writes 7z, but it's unsupported to link (no SDK headers, App-Store-risky) and we can't shell out to `bsdtar`/`aa` under the sandbox — so this means vendoring a third-party lib. Bigger call.
  Would offer the user a format preference (Zip = compatible default, Apple Archive = smaller). Pairs with a future auto-unpack-on-decrypt (use the same framework to expand back to a folder instead of leaving the archive).
  **Justification note:** a good final touch, but the tighter options are macOS-centric formats — they mostly benefit Mac users. Our goal is interop / UI convenience / deep system integration, and this doesn't quite fit that, so it's harder to justify. Still nice to have.

* Post-quantum hardware keys — the tagged `mlkem768p256tag` type (`age1tagpq…`). Phase 3.
  Done already (Phases 1–2): software X-Wing `mlkem768x25519` (age1pq) — generate/encrypt/decrypt, in AgeKit + the app.
  * **No longer blocked:** age-plugin-se v0.2.0 implements it (commit 520957b "Add support for post-quantum keys", ~/src/age-plugin-se). Their standard: the spec's `mlkem768p256tag` recipient (`age1tagpq…`; recipient = ML-KEM-768 encaps key 1184 ‖ uncompressed P-256 point 65 = 1249 bytes; enc = ML-KEM ct 1088 ‖ P-256 65 = 1153), with the ML-KEM-768 key stored **in the Secure Enclave** via CryptoKit's `SecureEnclave.MLKEM768` (macOS 26). age spec section: https://github.com/C2SP/C2SP/blob/main/age.md
  * **Encrypt-to (software): DONE** — `MLKEM768P256Recipient` in AgeKit + `age1tagpq` parsing in the app; verified against age-plugin-se on Secure Enclave ML-KEM hardware.
  * **Generate + decrypt (hardware): DONE** — `SecureEnclavePostQuantum` generates a `SecureEnclave.MLKEM768` + P-256 key and decrypts via `MLKEM768P256Identity` (decap in the enclave); the generate sheet re-enables "Post-quantum + Secure Enclave". Recipient/stanza are wire-compatible with age-plugin-se; identity encoding is our own (`AGE-PLUGIN-SE-PQ-`).
  * **Remaining follow-ups:** (a) runtime-verify the enclave generate/decrypt round trip in the app (needs a Touch ID prompt, so not in the automated tests); (b) identity *portability* — import an age-plugin-se `AGE-PLUGIN-SE-` PQ identity / export ours in their format (their identity container, not the spec).
  * Verify against age-plugin-se (~/src/age-plugin-se, `keygen --pq`) once on capable hardware; also the testkit vectors (https://age-encryption.org/testkit).

# TODO

* [x] Clipboard import (encrypt/decrypt from clipboard content)

* UI add menu button next to add age key in encrypt view: add ssh keys from code forge, add recipients file.
* assuage binary using the swift core, and a stanza you can copy from settings somewhere to alias it to /Apps/.... IE the user can just have this app installed and use it in the cli too.
* age-agent! Was reading the age plugin spec and it briefly mentions an outline for them
  A shim binary age-plugin-assuagent or something calls out / starts up the main app.
  Users should be able to create... Idk. "agent identities" or something, which represent a set of their keys.
  So the app might suggest "all keys", "all secure enclave keys" (better name for users), and these are dynamic and the public key stays the same as they add keys / remove them.
  (option to have this not be the case, regenerate this key invalidating the old public key when the dynamic list changes)
  My read of plugin spec suggests these agent identity keys are short-lived, so might change on app restart regardless. Option for this probably as well // fold it into above.

* Stretch / harder for me to test directly:: if you have a keys window open, you should be able to drag it to an encrypt or decrypt list, our standard UI view for that.

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
  * **Contacts API constraints (2026-07-14 research):**
    * Access: `CNContactStore.requestAccess(for: .contacts)`; needs `NSContactsUsageDescription`; sandbox/MAS build needs `com.apple.security.personal-information.addressbook`.
    * `.limited` authorization + its pickers (`ContactAccessButton`, `contactAccessPicker`) are **iOS 18 / Catalyst only — not native macOS** (macOS is full-access-or-denied). Model "contacts in scope" as an abstraction so iOS limited access drops in later; gate the pickers behind availability.
    * **Never delete a contact.** `CNMutableContact` + `CNSaveRequest.update(_:)`; remove a field by emptying it; NEVER `CNSaveRequest.delete`. Tag writes with `transactionAuthor`; watch `CNContactStoreDidChange`. My Card via `unifiedMeContactWithKeys(toFetch:)`.
    * No arbitrary/custom field, and the vCard `KEY` property isn't exposed. The `note` field needs `com.apple.developer.contacts.notes` (Apple approval + it's freeform text) → not used.
    * No pronouns in the API → write name-first, they/them-neutral copy everywhere; format names with `CNContactFormatter`.
  * **LOCKED DESIGN (2026-07-14) — contacts-centric, no parallel DB:**
    * Source of truth: private keys → keychain; everyone's public keys (age/ssh/verifier) + emails + forge URLs → the **contact card**. Recipient files stay first-class/ephemeral. Note-verification trust store = the verifier keys on contacts (no separate store). App-only "person" records (e.g. a "Backup keys" bundle, `source=app`) and `.keys` HTTP caching → later.
    * **Public keys on the card:** custom-labeled `urlAddresses`, same labels for yours and others — `age-public-key` / `ssh-public-key` / `verifier-key`. Value = scheme-mirrored URL (`age-public-key:age1…`); percent-encode payloads that aren't URL-safe (ssh lines, verifier keys); age bech32 is already safe. So AirDropping a card carries the keys and they ride iCloud sync.
    * **New tab "Contacts and other recipients"** (grouped with Keys/identities at the end). A filtered view onto Contacts; unified Person model that records `source` (Contacts vs app).
      * Rows: avatar · display name · capability chips (Age/SSH/PQ/Verifier/Forge-link). Search by name.
      * Filter (toolbar + View menu), default **"With encryption keys"** (age or ssh); also All contacts · Age · SSH · **Post-quantum** · Verifier · Forge links. PQ filter → multi-select → **Encrypt to Selected** (their PQ keys only).
      * Toolbar: filter · Encrypt to Selected · (iOS-later) ContactAccessButton to widen scope.
      * Context menu: Encrypt to [Name] / …Post-quantum only · Copy Public Keys · Fetch Keys from Profile… (HEAD+`.keys`, show the resolved source URL incl. redirects) · Add Key to [Name]… · Edit… · Show in Contacts.
      * Person editor (sheet): name+avatar read-only (Edit in Contacts; never rename/delete); emails read-only (canonical, multiple w/ labels); forge profiles (multiple, add/remove); public keys in Age/SSH/Verifier groups, add-by-paste / remove, each showing provenance (pasted, or the resolved `.keys` URL) like import. **Writes apply on explicit Save** ("this will be written to \(name)'s contact card"), `transactionAuthor`-tagged, only our fields.
    * **Forge-URL detection** without a hardcoded host list: append `.keys` if absent, HEAD for `text/plain` (as the existing recipients fetch does). Display the exact source URL we pulled from.
    * **Copy:** guide novices+experts — state the concept plainly, then the concrete action. No-keys example: "No public keys for \(name) yet. Add their age or SSH public key, or a profile link where Assuage can fetch them — like GitHub or Codeberg." Clear any "learn more" links with the user first.
    * **Sequencing:** after the signing path is stable — "Add verifier key to [contact]…" from the note-signatures view (+ save an age/ssh public key you hold onto a contact). Follow-up: "Publish my keys to My Card" (subset TBD). Deferred/uncertain: Finder "Encrypt to [contact]" quick action.

* mail kit extension to provide signing / encryption to mail
  This is probably a later one after contacts, at least to add integrated "given an email address, can we sign or encrypt to it" functionality the extension lets us add.
* share extension: quickly encrypt a file or text to a given key or person, then return it for sharing
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
  * **Identity portability: DONE** — our PQ identity uses age-plugin-se's exact encoding (`AGE-PLUGIN-SE-`, P-256-first two-blob container), so their `keygen --pq` identity imports into Assuage and ours exports to them. Verified both directions (import derives their recipient; our export re-imports) without a prompt.
  * **Remaining follow-up:** runtime-verify the enclave generate/decrypt round trip in the app (needs a Touch ID prompt, so not in the automated tests).
  * Verify against age-plugin-se (~/src/age-plugin-se, `keygen --pq`) once on capable hardware; also the testkit vectors (https://age-encryption.org/testkit).

# TODO

* [x] Clipboard import (encrypt/decrypt from clipboard content)

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

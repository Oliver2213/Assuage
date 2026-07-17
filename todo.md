# TODO

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
* Recipient QR code (show/scan) for phone transfer

* Contacts — remaining follow-ups (base integration shipped: Contacts panel, person editor,
  keys on the card, code-forge fetching, revoked-key lists, encrypt-to-contact, note verification):
  * Per-contact key-selection preference: use all keys / first / pick each time (default is all).
  * App-only "person" records (`source=app`, e.g. a "Backup keys" bundle) and `.keys` HTTP caching.
  * "Publish my keys to My Card" (subset TBD).
  * iOS/Catalyst `.limited` access + its pickers (`ContactAccessButton` / `contactAccessPicker`) — gated on availability; native macOS stays full-access-or-denied.
  * Deferred/uncertain: Finder "Encrypt to [contact]" quick action.

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

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

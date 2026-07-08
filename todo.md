# TODO

* [x] an app info struct like my other apps have with info like the website URL, repository URL (only show website if they're both the same) in the help menu
* [x] Clipboard import (encrypt/decrypt from clipboard content)

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

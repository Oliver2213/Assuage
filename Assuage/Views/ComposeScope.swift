/// Which kind of input a compose view (Encrypt / Decrypt) works on: pasted text
/// or queued files. The same `EncryptView` / `DecryptView` render either, so the
/// Files and Text panels reuse them.
enum ComposeScope {
    case text, files

    /// The panel this scope belongs to — used to tell which of the (both-mounted)
    /// compose views a menu command should act on.
    var panel: AppModel.Panel { self == .text ? .text : .files }
}

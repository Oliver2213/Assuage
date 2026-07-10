# Finder Quick Actions — Xcode setup

Two Action Extensions add **Encrypt with Assuage** and **Decrypt with Assuage**
to Finder's right‑click **Quick Actions** (and the Services menu). Each just
forwards the selected files/folders to the app via LaunchServices and quits — the
app decides encrypt vs. decrypt from the contents. No crypto, no UI in the
extensions.

Code lives in two **top‑level** folders, `EncryptAction/` and `DecryptAction/`
(siblings of `QLExtension/`). Top level — not under `Assuage/` — for the same
reason as `QLExtension/`: this project uses synchronized folder groups
(`objectVersion 77`), so anything under `Assuage/` is auto‑compiled into the app
target. Each folder becomes its own synchronized group, matching what the New
Target wizard produces (it always creates the target's folder at the repo root),
so there's no relocating to do.

You create the two targets; I wrote everything else. The handler needs **no
library** (only AppKit + UniformTypeIdentifiers), so there's nothing to link.

> **Clobber‑proofing:** my handler is `QuickActionForwarder.swift` (class
> `QuickActionForwarder`), *not* `ActionRequestHandler`, so it can't collide with
> the file Xcode's template generates. Still delete the template files (step 2).

---

## Do this twice — once per extension

|                     | Extension A                                         | Extension B                                         |
|---------------------|-----------------------------------------------------|-----------------------------------------------------|
| Product name        | `EncryptAction`                                     | `DecryptAction`                                     |
| Bundle identifier   | `dev.smoll.Assuage.EncryptAction`                   | `dev.smoll.Assuage.DecryptAction`                   |
| Handler (add mine)  | `EncryptAction/QuickActionForwarder.swift`          | `DecryptAction/QuickActionForwarder.swift`          |
| Info.plist          | `EncryptAction/Info.plist`                          | `DecryptAction/Info.plist`                          |
| Entitlements        | `EncryptAction/EncryptAction.entitlements`          | `DecryptAction/DecryptAction.entitlements`          |
| Finder label        | Encrypt with Assuage                                | Decrypt with Assuage                                |

### 1. Create the target
- **File ▸ New ▸ Target…** → **macOS** tab → **Application Extension** →
  **Action Extension** → Next.
- **Product Name**: `EncryptAction` (then `DecryptAction` the second time).
- **Embed in Application: Assuage.** If the popup is dimmed, that's normal with a
  single app — it auto‑selects. **Finish.**

Xcode generates a group with `ActionViewController.swift`, `ActionRequestHandler.swift`,
a `Main.storyboard`, an `Info.plist`, and an entitlements file, and adds an
**"Embed Foundation Extensions"** (a.k.a. Embed App Extensions) build phase to the
**Assuage** app target listing `EncryptAction.appex`.

> **If it didn't embed:** app target ▸ **Build Phases** ▸ **＋ ▸ New Copy Files Phase**,
> Destination **Plug‑ins**, **＋** add `EncryptAction.appex`. Confirm **Dependencies**
> lists the extension too.

### 2. Swap in the provided files — this is a **no‑UI** action
- **Delete** the generated `ActionViewController.swift`, `Main.storyboard`, and
  `ActionRequestHandler.swift` (move to Trash) — we forward and quit, no view.
- **Add** mine to the target: `EncryptAction/QuickActionForwarder.swift` (check the
  `EncryptAction` target on add). Since the wizard already made the `EncryptAction`
  folder at the repo root, just drop my file in beside it / replace its contents.

### 3. Point build settings at the provided plist / entitlements
Target ▸ **Build Settings**:
- `INFOPLIST_FILE = EncryptAction/Info.plist`
- `CODE_SIGN_ENTITLEMENTS = EncryptAction/EncryptAction.entitlements`
- `PRODUCT_BUNDLE_IDENTIFIER = dev.smoll.Assuage.EncryptAction`
- `MACOSX_DEPLOYMENT_TARGET` = same as the app (macOS 26). **Type it cleanly — no
  trailing space** (a stray space parses as "10.4" and breaks the build).
- **`INFOPLIST_KEY_CFBundleDisplayName = Encrypt with Assuage`** (Decrypt:
  `Decrypt with Assuage`). This is the **Finder label**. `GENERATE_INFOPLIST_FILE`
  stays `YES` and overlays my `Info.plist` (principal class, activation rule, etc.
  all come through) — but it forces `CFBundleDisplayName` to the product name
  unless this key overrides it. Verify in the built `.appex`, not just the source
  plist. (Rename‑proof it later with a project setting, e.g.
  `INFOPLIST_KEY_CFBundleDisplayName = Encrypt with $(ASSUAGE_APP_NAME)`.)

My `Info.plist` uses `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).QuickActionForwarder`
(no storyboard key), so it works regardless of the target/module name. It also
sets the Finder label via `CFBundleDisplayName` and the activation rule (Encrypt
shows for any item; Decrypt only when every selected item is a `.age` file).

### 4. (No library step)
Nothing to link — do **not** add AssuageCore. The handler is self‑contained.

---

## After both targets exist — build & test
1. Build and run **Assuage** once (embeds + registers both extensions).
2. Enable them if needed: **System Settings ▸ General ▸ Login Items & Extensions ▸
   Added Extensions** (or the Finder/Quick Actions section) — toggle the two on.
   Users manage which appear and their order here; we don't build our own control.
3. In Finder: right‑click a plain file or folder → **Quick Actions ▸ Encrypt with
   Assuage**; right‑click a `.age` file → **Decrypt with Assuage**. The app comes
   forward with the selection loaded.
4. If an action doesn't show up, re‑register services: `/System/Library/CoreServices/pbs -flush`
   then log out/in, or just rebuild/run the app.

## Notes / known limitations (documented, deferred)
- The picked verb isn't passed to the app; the app infers from bytes (all age →
  decrypt, else → encrypt). So "Encrypt" on an already‑`.age` selection will
  *decrypt* it — re‑encrypting ciphertext isn't reachable from Finder (use the
  Encrypt panel). Rare; a follow‑up could pass the verb via an app group.
- Folders are zipped to `<folder>.zip.age` on encrypt; decrypt leaves the `.zip`
  (no auto‑unpack — a later pref could add a marker + auto‑expand).

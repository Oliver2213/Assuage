# Quick Look preview extension — Xcode setup

Generic target name (`QLExtension`) so an app rename doesn't touch it. All code
lives in `QLExtension/` (a **top-level** folder, sibling to `AssuageCore/`);
you create the target, I wrote everything else.

> **Why not under `Assuage/`?** This project uses synchronized folder groups
> (`objectVersion 77`): every file physically under `Assuage/` is auto-added to
> the *app* target. Nesting the extension there would silently compile its
> `QLPreviewingController` code into the app. Keeping `QLExtension/` at the top
> level gives it its own synchronized group. For the same reason, the extension's
> membership follows its folder — you generally don't check/uncheck its files
> by hand; cross-target sharing (step 5) is the exception, set via File Inspector.

## 1. Create the target
- **File ▸ New ▸ Target…** (Target, not File).
- Select the **macOS** tab, scroll to **Application Extension**, pick
  **Quick Look Preview Extension**, Next.
- Product name: **`QLExtension`**.
- **Embed in Application: Assuage.** If this popup looks dimmed/greyed, that's
  normal — with a single app in the project it's auto-selected and not editable.
  Just click **Finish**.

Xcode generates a `QLExtension` group with a `PreviewViewController.swift`, a
`.storyboard`, an `Info.plist`, and an entitlements file, and — this is the
embedding — adds an **"Embed Foundation Extensions"** build phase to the
**Assuage** app target.

### If it didn't embed
Embedding for app extensions is *not* the "Embed" dropdown in the app's
Frameworks list (that stays "Do Not Embed" / dimmed for a `.appex` — expected).
It's a build phase. Verify:
- Select the **Assuage app target ▸ Build Phases**. There should be an
  **"Embed Foundation Extensions"** phase listing **`QLExtension.appex`**.
- If the phase is missing: **+ ▸ New Copy Files Phase**, set **Destination = Plug‑ins**,
  then **+** and add `QLExtension.appex`.
- Also confirm **Build Phases ▸ Dependencies** on the app lists `QLExtension`
  (adding the embed usually creates this automatically).

## 2. Swap in the provided files
- **Delete** the generated `PreviewViewController.swift` and the generated
  `.storyboard` (we render SwiftUI programmatically — no storyboard).
- **Add** these to the `QLExtension` target (check the target on add):
  - `QLExtension/PreviewViewController.swift`
  - `QLExtension/AgeFilePreview.swift`

## 3. Point build settings at the provided Info.plist / entitlements
Target **`QLExtension` ▸ Build Settings**:
- `INFOPLIST_FILE = QLExtension/Info.plist`
- `CODE_SIGN_ENTITLEMENTS = QLExtension/QLExtension.entitlements`
- `MACOSX_DEPLOYMENT_TARGET` = same as the app (macOS 26).

My `Info.plist` uses `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).PreviewViewController`
(no storyboard key), so it works regardless of the target name.

## 4. Link the core library
`QLExtension` ▸ **General ▸ Frameworks and Libraries ▸ +** ▸ add **`AssuageCore`**.

## 5. Share the info-view files with the extension
**File Inspector ▸ Target Membership**, check **`QLExtension`** for each (they
stay in the app target too — don't uncheck Assuage):
- `Assuage/Views/AgeFileInfoView.swift`
- `Assuage/Support/AgeFileInfo+UI.swift`
- `Assuage/Support/DecryptionCapability+UI.swift`
- `Assuage/Support/Identity+UI.swift`

They import only `SwiftUI` + `AssuageCore`, so they compile cleanly in the
extension.

## 6. Build & test
- Build and run **Assuage** once (embeds + registers the extension).
- In Finder, select a `.age` file and press **space**.
- Force a refresh during development: `qlmanage -r && qlmanage -r cache`.

## Notes
- `import Quartz` provides `QLPreviewingController`; `import QuickLookUI` is
  equivalent if your SDK prefers it.
- Sandboxed, read-only — header info only, no keychain or decryption.

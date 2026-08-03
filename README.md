# Markdown Quick Look

A small macOS app + Quick Look preview extension that renders `.md` files
(and `.markdown`, `.mkd`, `.mkdn`, `.mdwn`, `.mdown`, `.mdtxt`, `.mdtext`) when
you press Space on them in Finder.

Rendering is done with [marked](https://github.com/markedjs/marked) (bundled,
MIT licensed) and [github-markdown-css](https://github.com/sindresorhus/github-markdown-css)
(bundled, MIT licensed), so previews look like GitHub-rendered Markdown and
automatically follow light/dark mode.

No Xcode, no Apple Developer account, no App Store — everything is compiled
with the Swift compiler that ships with Command Line Tools and ad-hoc signed
for local use only.

## Build & install

```sh
./build.sh
rm -rf ~/Applications/MarkdownQuickLook.app
cp -R build/MarkdownQuickLook.app ~/Applications/
open ~/Applications/MarkdownQuickLook.app   # launch once so macOS registers it
```

If Quick Look doesn't pick it up immediately:

```sh
qlmanage -r
qlmanage -r cache
```

Then, if needed, enable it under **System Settings → General → Login Items &
Extensions → Quick Look**.

## Test without Finder

```sh
qlmanage -p path/to/file.md
```

## How it's built (for future reference / after a macOS update breaks it)

- `Sources/App` — the tiny host app. Its only job is to exist in
  `/Applications` (or `~/Applications`) so macOS has somewhere to find and
  register the embedded extension.
- `Sources/Extension` — the actual Quick Look preview extension
  (`PreviewViewController`, a `QLPreviewingController` that hosts a
  `WKWebView`) and `MarkdownRenderer`, which reads the file, inlines local
  images as base64 data URIs (so the preview stays self-contained even
  though the extension is sandboxed), and stuffs it all into
  `Resources/template.html` alongside the bundled `marked.min.js` and
  `github-markdown.css`.
- `Plists/Extension-Info.plist` declares the extension point
  (`com.apple.quicklook.preview` — note: *not* `...preview-extension`,
  which is an older/wrong identifier that silently fails to register) and a
  custom UTI for the various Markdown file extensions.
- `Plists/Extension.entitlements` sandboxes the extension
  (`com.apple.security.app-sandbox`) and grants network client access
  (`com.apple.security.network.client`). Both are required — Quick Look's
  `pkd` daemon flat-out refuses to load an unsandboxed preview extension,
  and without the network entitlement WebKit's GPU/Networking helper
  processes crash on launch inside the sandboxed extension.
- `build.sh` compiles both targets directly with `swiftc` (the extension is
  linked with `-e _NSExtensionMain`, the entry-point override Xcode normally
  wires up invisibly for app extensions), assembles the `.app`/`.appex`
  bundle structure by hand, and ad-hoc code signs both.

## Troubleshooting

- **`error: no such module 'QuickLookUI'` (or similar) when running
  `./build.sh`**: Xcode is installed but not selected as the active
  developer directory (common right after installing Xcode fresh — having
  it in `/Applications` isn't enough). Fix:
  ```sh
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  ```
  Then re-run `./build.sh`. `build.sh` now checks for this up front and
  prints this same fix if it detects the problem.

## Known limitations

- Local images referenced by relative path are inlined as base64 at preview
  time; this only works if the extension's sandbox can read that file (same
  folder as the `.md` file — should generally work).
- No Finder icon/thumbnail preview (only the spacebar Quick Look panel) —
  that would need a separate `QLThumbnailProvider` extension target.
- Ad-hoc signed apps can occasionally need re-registering
  (`pluginkit -a ~/Applications/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookExtension.appex`)
  after a macOS update.

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
  bundle structure by hand, and ad-hoc code signs both. Each target is built
  for `arm64` and `x86_64` and `lipo`'d into a universal binary, against the
  `macos11.0` deployment target that `LSMinimumSystemVersion` advertises —
  without an explicit `-target`, `swiftc` builds for the *host* macOS and the
  bundle silently refuses to load on anything older than the build machine.

## Security model

Previewed files are untrusted input: pressing Space in Finder is enough to
run them through `marked`, which does **not** sanitize embedded raw HTML.
Everything the preview needs is inlined by `MarkdownRenderer`, so no remote
fetch is ever legitimate, and `Resources/template.html` carries a
Content-Security-Policy that denies all of them (`default-src 'none'`, with
`data:` images and inline script/style only). Without it, a `.md` file can:

- silently fetch remote images, stylesheets and iframes (tracking pixels that
  fire on preview, reporting when and where you previewed a file);
- execute arbitrary JavaScript via handlers such as
  `<img src=x onerror="fetch('https://…?d='+…)">`, since the extension holds
  `com.apple.security.network.client`.

`PreviewViewController` also refuses in-panel navigation — a clicked link
opens in your browser instead of replacing the preview with a web page that
has no way back — and suppresses JS-initiated windows, alerts and prompts.

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

- **Local images do not render.** Relative image references are inlined as
  base64 at preview time, but Quick Look's sandbox only grants the extension
  read access to *the previewed file itself* — not to its siblings. Reading
  `logo.png` next to `README.md` fails with "you don't have permission to
  view it", so the image falls back to its alt text. `stat` succeeds and the
  file is visibly present, which makes this look like a bug in the inlining
  code; it isn't.

  Granting the extension broader read access does fix it, at the cost of
  weakening the sandbox — add to `Plists/Extension.entitlements`:

  ```xml
  <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
  <array>
      <string>/</string>
  </array>
  ```

  That lets the extension read anything under `~`. Only consider it because
  the preview can no longer talk to the network (see the CSP in
  `Resources/template.html`) — without that Content-Security-Policy, a
  hostile `.md` file could name any path on disk and beacon the contents out.
- No Finder icon/thumbnail preview (only the spacebar Quick Look panel) —
  that would need a separate `QLThumbnailProvider` extension target.
- Ad-hoc signed apps can occasionally need re-registering
  (`pluginkit -a ~/Applications/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookExtension.appex`)
  after a macOS update.

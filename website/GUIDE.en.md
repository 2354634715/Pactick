# Local website preview and maintenance

[简体中文](GUIDE.md)

`website/` is a standalone static introduction to the Android client, local use, and optional synchronization. It links to GitHub, release assets, and project documentation. It does not access an app workspace or sync API and does not replace the server management interface.

## Preview locally

Node.js 18 or later is required. From the repository root, run:

```powershell
node website/server.mjs
```

Open [the local preview](http://127.0.0.1:4187). It listens only on loopback; press `Ctrl+C` to stop. No npm installation or build is required.

If the port is in use, the command exits with an error. Choose another port:

```powershell
node website/server.mjs 4188
```

You can also open `website/index.html` or `website/index.en.html` directly. Language switching uses ordinary links and needs no JavaScript. Prefer the local HTTP preview when checking resource responses and security headers.

## Files and behavior

| File | Purpose |
| --- | --- |
| `index.html`, `index.en.html` | Chinese and English pages with matching feature scope, version, downloads, and documentation in the corresponding language |
| `styles.css` | Shared colors, system fonts, responsive layout, and interaction states |
| `app.js` | Switches the Today, Calendar, and Focus illustrations; supports arrow keys, Home, and End |
| `assets/pactick-icon.png` | Existing project icon copied from `client/assets/branding/pactick_icon.png` |
| `server.mjs` | Local preview with an explicit allowlist for the two HTML pages, shared CSS/JavaScript, and project icon; does not serve other repository, configuration, or documentation files |

The pages retain the warm paper background, dark text, serif headings, red primary actions, and blue-green links. Body text and controls use system sans-serif fonts. Layout follows the project's web design guide; the client and promotional video keep their own visual systems.

Illustrations contain fixed sample data. They are not app screenshots and cannot create tasks or start focus. With JavaScript disabled, Today remains visible; language links, downloads, section links, documentation, and native disclosure elements continue to work.

There are no analytics scripts, external fonts, CDNs, or background requests. GitHub links and release downloads need network access. The page does not choose or download files automatically.

## Maintain release links

The pages target `v0.3.0-preview.3` using the agreed artifact names. Their source can be fixed before publication. Check each destination after upload; the presence of a link does not prove that its download is available.

| Item | Page target |
| --- | --- |
| Android client | `v0.3.0-preview.3`, build 8; Android 8.0 / API 26 or later |
| APK | `pactick-0.3.0-preview.3-build8-release.apk`; the page displays “Universal APK,” with actual size and SHA-256 available from the final Release asset and checksum file |
| This release's assets | Android APK, full source, and `SHA256SUMS.txt`; no new server binaries are promised |
| Older Windows/Linux servers | `v0.3.0-preview.1`, x86-64; linking an ended, unassigned focus session in a synchronized workspace requires upgrading the server from preview.3 source |

Versions are fixed in both HTML files and are not refreshed through the GitHub API. Older server downloads still point to [preview.1](https://github.com/2354634715/Pactick/releases/tag/v0.3.0-preview.1), with their version and upgrade requirement next to the links. Do not substitute `releases/latest` for a checked prerelease asset URL. The pages do not duplicate the APK's hash or size. “See SHA256SUMS.txt” links directly to this release's checksum file. This allows source to be fixed before the signed build without changing the page when that build produces a new digest.

Complete the release links in this order:

1. After publication, check actual Release asset URLs, platforms, architectures, sizes, and `SHA256SUMS.txt`. Do not copy hashes or sizes into the pages. If an artifact name must change, update its links before fixing the next candidate source. A release page is not an APK file URL.
2. Compare both APK entry points on `index.html` and `index.en.html`, including version, build, and checksum-file link. Each page's two `data-download="android"` links must point to the same file.
3. Check whether server artifacts changed and keep their separate version information. Windows/Linux server managers must not be described as desktop clients.
4. After publication, check the preview.3 tag's guides, license, migration and server-upgrade documents, and anchors. The English page should use English documentation. Maintain both versions of this guide when preparing later versions.
5. Check language switching in both directions, downloads, all illustrations, disclosures, keyboard use, and narrow-screen wrapping. Language links, downloads, documentation, and disclosures must remain usable without JavaScript, with Today as the default illustration.

Deleting, renaming, or restricting a GitHub asset can break a fixed link. The page does not bypass GitHub/browser download restrictions or verify downloaded files automatically. Users compare their actual APK with this release's checksum file. A filename alone does not establish the identity of a file that fails verification.

## Delivery scope

Website source and local preview commands are included in this release's source archive. This task does not register a site or deploy a server.

Site runtime assets are `index.html`, `index.en.html`, `styles.css`, `app.js`, and `assets/`. The local server, this guide, and local validation records are not runtime assets. No site is deployed. Any future hosting needs its own cache, HTTPS, and response-header configuration; the CSP in `server.mjs` applies only to its local HTTP responses. The preview accepts GET/HEAD only and returns 405 for other methods. Paths outside its allowlist return 404; do not replace it with a static server for the entire repository.

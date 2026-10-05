# Granite State Report for iPhone

A native iPhone client for the GSR Drop Box, the upload endpoint behind the four tip pages on granitestatereport.com. A source picks a drop box, adds a note, files, photos, video, a scan or a voice note, and presses Send. The app speaks the same protocol as the site's own page script, so the editor sees app submissions in the same Drop Box and the same Gmail notices as web ones.

What it does:

- **Send tab.** The four drop boxes in the site's order: quick tip (`tips`), Tell Us Your Story (`story`), Nothing to See Here (`nothing`), Inside the Building (`inside`). Quick capture for photo or video, document scan (one PDF), and voice note. A "Not sent yet" list of drafts and interrupted sends.
- **Latest tab.** The 20 newest posts from the site's public WordPress REST API, opened in `SFSafariViewController`.
- **Contact tab.** Signal username (copy), mailing address (copy), phone, email, policy links, and a button that deletes everything the app holds.
- **Share extension**, "Send to GSR": up to 50 images, movies or files, one URL, or text, from any app. Send from the sheet or leave it for the app.
- **Home Screen quick actions** and **App Shortcuts** (Siri, Spotlight, Shortcuts, Action Button): Send a Tip, Scan a Document, Record a Video.
- **Metadata cleaning.** Photos and videos lose location, make, model, software and capture time before upload. The cleaned copy is read back and checked; a file that still carries any of it is held back until the sender removes it or chooses Send as is. Documents are never touched.
- **Resumable uploads.** Progress is saved after every chunk. A dropped connection is retried. A send stopped by a closed app or a dead battery waits under "Not sent yet" and resumes where it stopped when the sender presses Send again; the app never restarts a send on its own, so a source who force-quits to stop one is not overruled. On iOS 26 and later, Send also starts a continued-processing background task with system progress.
- **Outbox on disk** in the App Group container, excluded from backups, file protection until first unlock. Each submission's folder is deleted when the drop box confirms it.
- No accounts, no analytics, no third-party packages. iOS 17+, iPhone only, portrait, light mode. Home Screen name: GSR.

## Layout

```
ios/
  project.yml              XcodeGen spec: both targets, Info.plist keys, entitlements, scheme
  App/Sources/             app target (GSR): tabs, router, quick actions, App Shortcuts, BackgroundSender
  App/Resources/           asset catalog, PrivacyInfo.xcprivacy
  ShareExtension/          share extension target (GSRShare) and its privacy manifest
  GSRKit/                  Swift package, three libraries
    Sources/GSRKit/        drop box client, uploader, outbox, feed, form catalog (plain Foundation, builds on Linux)
    Sources/GSRMedia/      photo and video cleaning (ImageIO, AVFoundation; empty off Apple platforms)
    Sources/GSRUI/         compose screen, pickers, theme, AppGroup (iOS only)
    Tests/                 GSRKitTests (Linux and Mac), GSRMediaTests (Mac)
    forms.json             the four forms as read off the live pages
  tools/forms_from_site.py rebuilds or checks forms.json against the site
  tools/mock_drop_server.py local stand-in for the drop box API, used by tests
  reference/gsr-dropbox-1.0.0.js  the site's own drop box script: the protocol reference
```

XcodeGen writes `GSR.xcodeproj`, both `Info.plist` files and both `.entitlements` files from `project.yml`. None of them are committed. Edit `project.yml`, then run `xcodegen generate` again.

## The drop box protocol

Base URL: `https://granitestatereport.com/wp-json/gsr-drop/v1/` (the `api` value in `forms.json`). Every call is a POST. `DropClient` mirrors `reference/gsr-dropbox-1.0.0.js` request for request; read that file before changing anything here.

| Call | Body | Reply |
|---|---|---|
| `start` | JSON `{form, website}`. `website` is the page's honeypot and is always `""`. | `{token, chunk, maxFile, maxFiles, maxTotal}` |
| `add` | JSON `{token, name, size, type}` | `{id}`, number or string, sent back exactly as received |
| `chunk?token=&file=&offset=` | raw bytes, `application/octet-stream` | `{received}` |
| `remove` | JSON `{token, file}` | |
| `finish` | JSON `{token, main, fields}` | |

- `fields` carries every key the form has: text fields and selects as strings, checkboxes as JSON booleans. That is what the page posts.
- Limits before the server answers are the page's: 4 MiB chunks, 2 GiB per file, 50 files, 10 GiB per send. The server's values from `start` win.
- Errors are WordPress `{code, message}`. 409 with `received`: resync the offset. 410: the session is gone, start a new one and upload again (at most twice). 507: storage full, stop. 429, other 5xx, or no response: retry with the page's backoff, 2, 4, 8 up to 30 seconds, eight tries. Any other 4xx fails that file, or from `start` or `finish` the whole send, with the server's own message.
- Like the page, the app uploads two files at a time. Where it differs, all in the sender's favor:
  - the page uploads while the visitor reads; the app uploads nothing until Send;
  - the app saves progress after every chunk, and on a 410 it uploads again in a new session instead of losing the files;
  - a file that gives up because the connection kept dropping stops the send before `finish`, and goes back in line for the next press, so a note never closes without its file;
  - `finish` is not repeated blind: if an earlier `finish` with the same token went unanswered and the box then answers 410, the box most likely has the submission, and the sender is told rather than the whole thing going twice;
  - files the sender removes, or that the box refused, are `remove`d before `finish`; a reply that arrives after the sender's × never puts a removed file back;
  - files the box refused (over a limit) move to a new draft after the send instead of being deleted;
  - every key the page has is sent, but nothing is sent when every file was refused and there is no note.
- Names the app gives its own files (camera, scans, voice notes) are a word and a random tag, never a date or time, because the name travels with the file.
- Every request sends `User-Agent: GSR-iOS/<version>` and `Accept: application/json`, from an ephemeral `URLSession` with no cookies and no cache. No `Origin` header.

The server is the GSR Drop Box plugin on the WordPress.com site. It is not in this repo. If the plugin's script changes version, diff it against `reference/gsr-dropbox-1.0.0.js` and update `DropClient` and `mock_drop_server.py` together.

## Build on a Mac

Xcode 26 (CI selects Xcode 26.6 when the runner has it) and XcodeGen 2.46 or later.

```
brew install xcodegen
cd ios
xcodegen generate
open GSR.xcodeproj
```

Pick a team under Signing & Capabilities, or set `DEVELOPMENT_TEAM` in `project.yml`, or pass `DEVELOPMENT_TEAM=<team id>` to `xcodebuild`. Simulator builds run unsigned. Without a signed App Group, `AppGroup.outbox()` falls back to the process's own Application Support folder: the app works, but the app and the share extension stop seeing each other's drafts.

Launch arguments used for App Store screenshots: `-GSRScreenshotTab latest|contact`, `-GSRScreenshotForm tips|story|nothing|inside`.

Apple's submission page says that from April 2027, uploads must be built with the iOS 27 SDK. Move the workflow to Xcode 27 before then.

## Tests

**Linux.** Swift 5.9 or later. CI uses the `swift:6.2` image.

```
cd ios/GSRKit && swift test
```

To run the real HTTP code too, start the stand-in server first. Without `GSR_MOCK_DROP_URL`, `LiveTransportTests` skip.

```
python3 ios/tools/mock_drop_server.py --port 8787 &
cd ios/GSRKit && GSR_MOCK_DROP_URL=http://127.0.0.1:8787/wp-json/gsr-drop/v1/ swift test
```

No Swift installed: `docker run --rm -v "$PWD/ios/GSRKit":/pkg -w /pkg swift:6.2 swift test` from the repo root.

On Linux, GSRMedia and GSRUI compile empty, so the photo and video cleaning tests do not run there.

**Mac.** `cd ios/GSRKit && swift test` runs everything, including the HEIC, JPEG, PNG and video cleaning tests. In Xcode, Product > Test on the GSR scheme runs the same two test targets.

**CI** (`.github/workflows/ios.yml`): `core` runs the Linux tests with the mock server; `app` runs on `macos-26`, generates the project, runs `swift test`, builds for the simulator and for a device (unsigned), and takes screenshots (artifact `ios-screenshots-<run number>`, saved as JPEG with no alpha channel, as App Store Connect requires); `forms` checks the forms against the site; `testflight` archives and uploads, manual only.

## Keeping the forms in step with the site

The server files each submission under its form name and stores whatever field keys the page sends. The app has to send the same form names, `data-k` keys and option values as the pages, so nothing in `forms.json` is typed by hand.

`tools/forms_from_site.py` reads the `.gsrdb` box on `/tips/`, `/share-your-story/`, `/inside-the-building/` and `/nothing-to-see-here/`: form name, field keys, kinds, labels, options and defaults, the Send button's words, the consent line, and the "read first" sections the app shows word for word above Send. It writes `GSRKit/forms.json` and `GSRKit/Sources/GSRKit/FormsJSON.generated.swift` (the same JSON compiled in, so no resource bundle is needed).

```
python3 ios/tools/forms_from_site.py --write                 # rebuild from the live pages
python3 ios/tools/forms_from_site.py --check                 # exit 1 if the pages changed
python3 ios/tools/forms_from_site.py --html-dir DIR --check  # use saved <slug>.html files
```

The `forms` job runs `--check` every Monday at 13:41 UTC, and on pushes to master and pull requests that touch `ios/`. On pull requests it never blocks. It compares labels and read-first text as well as keys, so a wording edit on a page fails it too. When it fails: run `--write`, review the diff, run the tests, ship an app update. Installed copies keep sending the old keys and values until people update, so after renaming a field on the site, expect entries under the old key for a while.

## Identifiers

| What | Value | Where |
|---|---|---|
| App bundle ID | `com.granitestatereport.app` | `project.yml`, target GSR |
| Share extension | `com.granitestatereport.app.share` | `project.yml`, target GSRShare |
| App Group | `group.com.granitestatereport.app` | `project.yml` (both entitlements), `GSRKit/Sources/GSRUI/AppGroup.swift` |
| Background task IDs | `com.granitestatereport.app.send.*` permitted; each send registers `<bundle id>.send.<8 chars>` | `project.yml` `BGTaskSchedulerPermittedIdentifiers`, `App/Sources/BackgroundSender.swift` |
| Quick action types | `com.granitestatereport.app.tip`, `.scan`, `.video` | `project.yml` `UIApplicationShortcutItems`, `App/Sources/AppModel.swift` |
| Version | `MARKETING_VERSION` 1.0.0; CI build number is `<run number>.<run attempt>` | `project.yml`, `ios.yml` |

### If the bundle ID changes

1. `project.yml`: `PRODUCT_BUNDLE_IDENTIFIER` for both targets (the extension's must start with the app's ID and a dot), the App Group in both entitlement blocks, the `BGTaskSchedulerPermittedIdentifiers` wildcard, and the three `UIApplicationShortcutItemType` values.
2. `GSRKit/Sources/GSRUI/AppGroup.swift`: `AppGroup.id`.
3. `App/Sources/AppModel.swift`: the three case strings in `AppRouter.handleShortcut`. They must match the shortcut types in `project.yml` exactly.
4. `App/Sources/BackgroundSender.swift` builds its identifiers from `Bundle.main.bundleIdentifier`, so it follows on its own. The Info.plist wildcard does not: it is hardcoded in `project.yml`, and if it no longer matches, the identifiers BackgroundSender builds are not permitted. The literal there is only a fallback for a nil bundle ID.
5. `.github/workflows/ios.yml`: the screenshot step's `simctl launch` and `simctl terminate` use the bundle ID.
6. Apple's side: a new App ID for each target, the App Group, and an App Store Connect record that uses the new ID.

Then `xcodegen generate`.

## Releasing

The path from a merged PR to the App Store, with no Mac, is in `docs/GSR_iOS_App_Launch_Checklist_v1_2026-10-05.md`. Store copy and privacy answers: `docs/GSR_iOS_App_Store_Listing_v1_2026-10-05.md`. Privacy policy text for the site: `docs/GSR_iOS_App_Privacy_Policy_Update_v1_2026-10-05.md`.

# Granite State Report iPhone app: launch checklist

Version 1 · 2026-10-05 · Granite State Report

The path from the app's pull request to the App Store. No Mac is needed: GitHub Actions builds, signs and uploads the app, and everything else happens in a web browser and on your iPhone. Do the steps in order. Anything marked VERIFY could not be confirmed from Apple's published pages, the app's code, or the site, and needs checking before you rely on it.

Companion documents: `GSR_iOS_App_Store_Listing_v1_2026-10-05.md` (store copy, privacy answers, review notes) and `GSR_iOS_App_Privacy_Policy_Update_v1_2026-10-05.md` (policy text for the site). The developer's notes are in `ios/README.md`.

## 0. Merge the pull request

- [ ] Check that the "Build and test (macOS)" and "Core tests (Linux)" jobs passed on the pull request.
- [ ] Merge it into `master`. GitHub shows the Run workflow button only for workflows on the default branch, so step (f) waits on this.

## (a) Join the Apple Developer Program

- [ ] Enroll at developer.apple.com/programs, or in the Apple Developer app on your iPhone. You need an Apple Account with two-factor authentication turned on.
- [ ] Pay the fee: 99 USD a year.

Decide who the seller is before you start, because it shows on the App Store under the app's name.

- **Individual.** The App Store shows your legal name as the seller. Fastest to set up.
- **Organization.** Needed to show "Granite State Report" as the seller. That takes a registered legal entity (a corporation, an LLC, a nonprofit) with a D-U-N-S Number from Dun & Bradstreet. A DBA or trade name is not accepted. VERIFY whether Granite State Report is registered as an entity today, and how long a D-U-N-S Number takes.

If there is no entity yet, enroll as an individual and live with your name on the listing. Whether to form a company is a business question. The app does not need one. App Store Connect has an app transfer process for moving an app to another account later; VERIFY its criteria before counting on it.

## (b) Sign the agreements

- [ ] Sign in at appstoreconnect.apple.com as the Account Holder.
- [ ] In the Business section, accept the latest agreement. App Store Connect will not let you create an app record until you do.
- [ ] Skip the Paid Applications Agreement, banking, and tax forms. The app is free and sells nothing.

## (c) Register the IDs and create the app record

The workflow's automatic signing can register App IDs on its own. The app record it cannot create, and the first upload fails without one. App Store Connect's New App form lists only bundle IDs that are already registered, so register them by hand first.

In the developer portal (developer.apple.com/account > Certificates, Identifiers & Profiles > Identifiers):

- [ ] App Group: `group.com.granitestatereport.app`
- [ ] App ID, explicit: `com.granitestatereport.app`, description "Granite State Report". Turn on App Groups and assign the group above.
- [ ] App ID, explicit: `com.granitestatereport.app.share`, description "Send to GSR". Turn on App Groups and assign the same group.

In App Store Connect > Apps > + > New App:

- [ ] Platform: iOS
- [ ] Name: Granite State Report (if the name is taken, App Store Connect says so here)
- [ ] Primary language: English (U.S.)
- [ ] Bundle ID: `com.granitestatereport.app`
- [ ] SKU: anything unique to you, such as `GSR-IOS-1`. Nobody else sees it.
- [ ] User access: Full Access

## (d) Make an App Store Connect API key

The workflow signs in to Apple with this key.

- [ ] App Store Connect > Users and Access > Integrations > App Store Connect API > Team Keys. The first time, the Account Holder has to request access and accept the terms.
- [ ] Generate a key. Name: "GSR GitHub Actions". Access: **Admin**.
- [ ] Download the `.p8` file. Apple lets you download it once. Keep it somewhere private until step (e), then delete the local copy.
- [ ] Write down the Key ID (in the key's row) and the Issuer ID (above the table).

Why Admin: developers report that cloud signing from the command line fails with an App Manager key and works with Admin. Apple does not document this; it comes from user reports. Admin is a powerful key. It lives only in GitHub's encrypted secrets, and you can revoke it on the same page at any time and make a new one.

## (e) Add the repository secrets

GitHub > the BlogPostPreviewer repository > Settings > Secrets and variables > Actions > New repository secret. Add four:

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | The Key ID from step (d) |
| `ASC_ISSUER_ID` | The Issuer ID from step (d) |
| `ASC_KEY_P8` | The whole `.p8` file: open it in a text editor and paste everything, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines. A base64 copy of the file also works; the workflow tells them apart. |
| `APPLE_TEAM_ID` | Your 10-character Team ID, from developer.apple.com/account > Membership details |

## (f) Build and upload

- [ ] GitHub > Actions > **iOS app** (left column) > **Run workflow**.
- [ ] Branch: `master`. Tick "Archive and upload a build to TestFlight". Run.

The run tests the code on Linux and macOS, builds the app, takes screenshots, and only then archives, signs and uploads. If any secret is missing it stops at once and names it. The build number is the run number, a dot, and the attempt (for example `7.1`), so every upload is new to Apple. When it finishes, the run summary says the build was uploaded. It shows up in App Store Connect > TestFlight once Apple has processed it.

If signing fails, check in this order: the app record exists with exactly `com.granitestatereport.app`; the key's access is Admin; `APPLE_TEAM_ID` is the team that owns the key.

The run also leaves an artifact, `ios-screenshots-<run number>`, with the five App Store screenshots. Download it for step (h).

## (g) Test it on your own iPhone with TestFlight

- [ ] App Store Connect > the app > TestFlight > Internal Testing > + to make a group, add yourself, add the build.
- [ ] Install TestFlight from the App Store on your iPhone and accept the invitation. Internal builds skip Beta App Review. Each build expires 90 days after upload.

**This is the server's first real test.** The GSR Drop Box plugin on WordPress.com is the backend. It answered a non-browser request in testing (an invalid-form probe got the plugin's own JSON "Unknown form." error back, with no Origin header sent), but it has never received a full submission from the app. Your first send is that test. Open the Drop Box in WordPress admin and your Gmail before you start. If a send fails, the app shows the server's own error message. Copy it exactly; it tells the developer whether the plugin refused the request or something else went wrong.

Test checklist. Note what arrived for each.

- [ ] **Quick tip with a photo.** Send a Tip, a short note, one photo from Photos that has a location (Photos shows a map under it). Confirm the entry in the Drop Box and the Gmail notice with the photo attached.
- [ ] **Location removed.** Download that photo from the Drop Box entry, not from Gmail, so you are checking what the server holds. Open it on the phone in Files or Photos and look at its info: no map, no camera model. Compare with the original in Photos, which shows both. On a computer, ExifTool shows the same thing in more detail.
- [ ] **Share sheet from Photos.** Pick three photos and a video, tap Share, then Send to GSR. If it is not in the row of apps, tap More and turn it on. Switch "Send to" to Nothing to See Here and send from the sheet. Then share one more photo, tap "Finish in app", open GSR, and finish it from "Not sent yet".
- [ ] **Scan.** Send tab > Scan a document, three pages. One PDF should arrive in Nothing to See Here.
- [ ] **Voice note.** Record 20 seconds. The audio file should arrive and play.
- [ ] **Large video, app in the background.** Pick or record a long video, several hundred megabytes. Press Send and go to the Home Screen right away. On iOS 26 and later the system shows the upload's progress. Come back later. The video should arrive whole and play to the end. The Gmail notice carries files only when they total under 15 MB, so check the Drop Box.
- [ ] **Airplane mode mid-upload.** Start another large send. At about a third, turn on airplane mode. The file's row says "Connection hiccup, retrying". Turn airplane mode off within a minute. The upload should carry on from where it stopped, not from zero, and the file should arrive whole.
- [ ] **Longer outage.** Do it again and leave airplane mode on for six minutes. After about two and a half minutes of retries the send stops with "Could not reach Granite State Report. Check your connection." The note has not gone, and the file waits for the next press. Turn airplane mode off and press the send button. It should resume from where it stopped, not restart, and the note should arrive with the file.
- [ ] **Closed mid-send.** Start a send and swipe the app away. Reopen it. Nothing restarts on its own. "Not sent yet" shows it as stopped while sending; tap Finish, then the send button, and it resumes where it stopped.
- [ ] **Fields.** Send Tell Us Your Story with a name, an email, a town, a choice under "What are you sending?", and "GSR may contact me" ticked. Compare the entry with one sent from the web page: same field names, the box as ticked.
- [ ] **Text only.** A note with no files.
- [ ] **Shortcuts.** Long-press the app icon: Send a Tip, Scan a Document, Record a Video. Say "Send a tip to GSR" to Siri.
- [ ] **Contact tab.** Copy the Signal username, call, email, open each policy link. Then "Delete everything the app is holding" and confirm "Not sent yet" is empty.
- [ ] **App switcher.** With a draft open, swipe up to the app switcher. It should show the masthead, not your draft.
- [ ] **Latest.** Stories load and open.

Record one full send with Screen Recording from Control Center and keep the video. App Review can watch it instead of sending a test tip.

## (h) Fill in the App Store listing

Publish the privacy policy update on the site first. Guideline 5.1.1 requires the linked policy to cover what the app collects, and the live policy does not cover the app. It is also out of date for the website: it still says the forms are run by Jetpack. Text: `GSR_iOS_App_Privacy_Policy_Update_v1_2026-10-05.md`.

Then, in App Store Connect, from `GSR_iOS_App_Store_Listing_v1_2026-10-05.md`:

- [ ] **App Information:** name, subtitle, category News, content rights.
- [ ] **The 1.0 version page:** promotional text, description, keywords, support URL, marketing URL, copyright, screenshots (the workflow saves them as JPEG, ready to upload).
- [ ] **App Privacy:** privacy policy URL and the nutrition-label answers. Settle the two open questions in that section first.
- [ ] **Accessibility:** if App Store Connect asks what the app supports (VoiceOver, Larger Text and the rest), claim only what you have tried on your own phone. VERIFY whether it is required at submission.

### Age rating

Apple's questionnaire now gives ratings of 4+, 9+, 13+, 16+ and 18+. These are recommended answers. **Publisher to confirm each one.**

| Question | Answer | Why |
|---|---|---|
| Parental controls | No | |
| Age assurance | No | |
| Unrestricted web access | No (VERIFY) | No address bar and no search. The app opens fixed pages (stories, the site, the policy pages, signal.org) in Safari's in-app view. Links on those pages can lead elsewhere, which is why this is a judgment call. Answering Yes makes the app 16+. |
| User-generated content | No | Submissions go only to the editor and are never shown to anyone else. |
| Social media | No | |
| Messaging and chat | No (VERIFY) | Sending to the newsroom is one way. Users cannot reach each other. |
| Advertising | No | |
| Profanity or crude humor | None | |
| Horror or fear themes | None | |
| Alcohol, tobacco, or drug use or references | Infrequent | The Latest tab and the NH Bill Tracker it links to carry news on bills about cannabis, alcohol and drugs. |
| Medical or treatment information | None | |
| Health or wellness topics | None | |
| Mature or suggestive themes | Infrequent | Apple's definition names real-world crimes and political strife, which is what accountability reporting covers. |
| Sexual content or nudity; graphic sexual content | None | |
| Cartoon or fantasy violence | None | |
| Realistic violence | None (VERIFY) | Stories describe crimes in words; Apple's examples are depictions. |
| Prolonged graphic or sadistic violence | None | |
| Guns or other weapons | None (VERIFY) | |
| Gambling, simulated gambling, contests, loot boxes | None | |

Expected result: **13+**. Apple's table puts infrequent alcohol, tobacco or drug references at 13+; infrequent mature themes alone would be 9+. 13+ also matches the privacy policy, which says the site is not directed to children under 13. App Store Connect computes the rating from the answers; check that it says 13+ before you save.

### Where to sell it: United States only for version 1

- [ ] Pricing and Availability: Free. Availability: United States only.

Why:

1. **The audience is here.** The newsroom covers New Hampshire public bodies. The tip pages are written around New Hampshire and federal law (RSA 98-E, RSA 275-E, 5 U.S.C. § 2302), and the privacy policy says the site is published for a New Hampshire audience.
2. **The EU asks for a trader decision.** To sell in the European Union, App Store Connect asks whether you are a "trader" under the Digital Services Act. A trader's address, phone number and email are shown on the EU product page after Apple verifies them (VERIFY the current details in App Store Connect Help, "Manage European Union Digital Services Act trader requirements"). Whether a free app from a one-person newsroom makes you a trader is a legal question this checklist cannot answer. US-only takes it off the table. App Store Connect may still show the trader question; with no EU storefronts selected, the app is not affected (VERIFY the prompt's current wording).
3. **Export rules.** Apple's encryption page says an app distributed outside the U.S. and Canada is a U.S. export of encryption, and an app with exempt encryption "might" owe a year-end self-classification report. US-only avoids that.
4. **Other storefronts add their own steps.** App Store Connect has separate compliance pages for China mainland and Korea, among others.

Availability can be widened later in App Store Connect without a new build.

## (i) App Review information

- [ ] Paste the App Review notes from the listing document.
- [ ] Sign-in required: No.
- [ ] Contact name (VERIFY: whose), phone (603) 931-9264, email granitestatereport@gmail.com.
- [ ] Attach the screen recording from step (g), or delete the sentence that mentions it.
- [ ] While the app is in review, watch the Drop Box for a note marked "App Review test".

## (j) Submit

- [ ] On the 1.0 version page, under Build, pick the build you tested in step (g).
- [ ] Version release: **Manually release this version**. That gives you one more real send from the App Store build before anyone hears about it.
- [ ] Add for Review, then Submit.
- [ ] When it is approved: release it, install it from the App Store, send one real note, and confirm it arrives.
- [ ] Then tell people. If the tip pages get an App Store link, each page gets a version-log entry, as the site's rule requires.

## Known caveats

- **Signing certificates pile up.** GitHub's macOS runners start empty every time. Developers report that automatic signing on such runners can create a new Apple Development certificate on each archive run, and Apple caps how many a team can hold (VERIFY the current number). Every few months, open Certificates, Identifiers & Profiles > Certificates and revoke the old development certificates the workflow made. That does not affect the app on the App Store.
- **The Admin key.** The requirement comes from user reports, not Apple's documentation. If Apple changes it, an App Manager key may work; test before you downgrade.
- **The server.** The first TestFlight send is the first full app submission the plugin has ever received. Nothing goes to App Review until that works.
- **Xcode version.** Apple's submission page says that from April 2027, uploads must be built with the iOS 27 SDK. The workflow uses Xcode 26.6 today. The developer needs to move it to Xcode 27 before then.
- **The forms check.** Every Monday the workflow compares the app's four forms with the live pages. A red "Drop box forms still match the site" job means a page changed and the app needs an update. Installed copies keep sending the old fields until people update, so change field names on the site with care.
- **TestFlight builds expire** after 90 days. Run the workflow again for a fresh one.
- **The app is not anonymous,** and every send screen, the store description and the review notes say so. Keep it that way in every update.

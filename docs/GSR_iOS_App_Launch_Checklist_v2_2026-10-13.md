# Granite State Report iPhone app: launch checklist

Version 2 · 2026-10-13 · Granite State Report

The path from the app's pull request to the App Store. No Mac is needed: GitHub Actions builds, signs and uploads the app, and everything else happens in a web browser and on your iPhone. Anything marked VERIFY could not be confirmed from Apple's published pages, the app's code, or the site, and needs checking before you rely on it.

Companion documents: `GSR_iOS_App_Store_Listing_v2_2026-10-13.md` (store copy, privacy answers, review notes) and `GSR_iOS_App_Privacy_Policy_Update_v2_2026-10-13.md` (policy text for the site). The developer's notes are in `ios/README.md`.

## What changed from version 1

- The app now covers every GSR Drop Box on the site: eight, up from four. New: Granite State Archive, Send Research Files, Wild New Hampshire, Something You Can't Explain.
- New Listen tab: the Audio Articles and Podcast pages, played in the app.
- The site changed what the drop box emails say (counts and sizes only, no files) and now says files are encrypted on arrival. Test items 1 and 6 changed to match.
- The test plan grew from 15 items to 23. Items 1 to 15 are the original list, updated. Items 16 to 23 test the new features.
- Steps (a) to (e) are marked done, going by your message. Step 0 and the steps from (f) on are what is left.

## Where you are

You said you enrolled in the Apple Developer Program, created the app record for `com.granitestatereport.app`, and added the four GitHub secrets. Two things are still open:

- **Individual or organization?** Your message left that blank. It decides the seller name on the App Store (your legal name, or the registered entity's) and the copyright line in the listing. Nothing in the build depends on it.
- **The first real send.** Your message said "Here is what happened on the first real send" and stopped there. No result came through. Test item 1 below is that send. Send back what happened (see "What to send back" at the end).

## 0. Merge the pull request

GitHub shows the Run workflow button only for workflows on the default branch. The workflow file is on the pull request's branch, not on `master`, so no TestFlight run is possible until the pull request is merged.

- [ ] Open pull request #12 on GitHub. Check that "Build and test (macOS)" and "Core tests (Linux)" show green on the newest commit.
- [ ] It is a draft. Press **Ready for review**, then **Merge pull request**, then **Confirm merge**.

The merge also starts a normal build on `master`. Let it run; it is the same check the pull request had.

## (a) to (e): done

Going by your message, these are finished. If any upload fails at signing, check them in this order.

- [x] (a) Apple Developer Program enrollment. VERIFY: individual or organization (see above).
- [x] (b) The latest agreement accepted in App Store Connect > Business. App Store Connect will not create an app record without it.
- [x] (c) App ID `com.granitestatereport.app` with App Groups on, App ID `com.granitestatereport.app.share` with App Groups on, App Group `group.com.granitestatereport.app` assigned to both, and the app record in App Store Connect with bundle ID `com.granitestatereport.app`.
- [x] (d) An App Store Connect API team key with **Admin** access.
- [x] (e) Repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`.

Two details that commonly go wrong: the share extension's App ID must also have App Groups turned on with the same group, and `ASC_KEY_P8` must hold the whole `.p8` file, including the BEGIN and END lines.

## (f) The TestFlight run

1. [ ] On github.com, open the BlogPostPreviewer repository and tap **Actions**.
2. [ ] In the left column (on a phone: the workflow menu at the top), pick **iOS app**.
3. [ ] Press **Run workflow**. A small form opens.
4. [ ] Branch: `master`. Tick **Archive and upload a build to TestFlight**. Press the green **Run workflow**.
5. [ ] The run appears at the top of the list within a few seconds. Open it.

What the run does, in order:

| Job | What it does | If it goes red |
|---|---|---|
| Core tests (Linux) | Runs the app's protocol, upload and page-reading tests | A code problem. Send the run link. |
| Build and test (macOS) | Runs every test again on a Mac, builds the app and the share extension, takes the App Store screenshots | A code problem. Send the run link. |
| Upload to TestFlight | Waits for the macOS job, then archives, signs, and uploads | See below |

The upload job's steps, and what a failure in each means:

- **Check the secrets are set.** Fails at once if any of the four secrets is missing, and names it. Fix the secret and run again.
- **App Store Connect key.** Writes the key file from `ASC_KEY_P8`. A failure here usually means the secret holds part of the file.
- **Archive.** Builds and signs the app. A signing failure here points at step (c) or (d): the app record's bundle ID, App Groups on both App IDs, the key's Admin access, or `APPLE_TEAM_ID` belonging to a different team than the key.
- **Sign and upload to App Store Connect.** Sends the build to Apple. When it succeeds, the run's summary page says "Uploaded build N.1", where N is the run number.
- **Remove the key.** Deletes the key file from the runner whether the run passed or failed.

The upload job never runs on its own. It runs only when you press Run workflow with the box ticked.

After the run:

6. [ ] In App Store Connect > the app > **TestFlight**, the build shows as Processing. Apple emails the Account Holder when it is ready. VERIFY how long processing takes for you; Apple gives no fixed time.
7. [ ] The app's Info.plist declares that it uses no encryption beyond HTTPS (`ITSAppUsesNonExemptEncryption` false), so App Store Connect should not stop the build with a Missing Compliance prompt. If it does, answer that the app uses only exempt encryption (HTTPS through Apple's own networking).
8. [ ] The run also leaves an artifact, `ios-screenshots-<run number>`, with seven App Store screenshots. Download it from the bottom of the run page for step (h). Artifacts are kept 30 days.

## (g) Install it and run the test plan

- [ ] App Store Connect > the app > TestFlight > **Internal Testing** > **+** to make a group (for example "Newsroom"). Add yourself. Add the build.
- [ ] Install **TestFlight** from the App Store on your iPhone, open the invitation email on the phone, and accept it. Install GSR from TestFlight. Internal builds skip Beta App Review. Each build expires 90 days after upload.

**Before you start.** Every test send goes to the real drop box and sends the real notice to both Gmail accounts. Start every test note with **TEST** so the entries are easy to find and delete afterward. Open the Drop Box in WordPress admin on a computer before you start; you check each send there.

**The server's first real test.** The GSR Drop Box plugin answered a non-browser request in testing (an invalid-form probe got the plugin's own "Unknown form." error back), but it has never received a full submission from the app. Item 1 is that test. If a send fails, the app shows the server's own error message under the Send button. Screenshot it, or copy it exactly; it tells the developer whether the plugin refused the request or something else went wrong.

### The test plan

Items 1 to 15 are the original list, updated where the app or the site changed. Items 16 to 23 test what is new in this version.

1. [ ] **Quick tip with a photo.** Send a Tip, the note "TEST quick tip", one photo from Photos that has a location (Photos shows a map under it). Confirm the entry in the Drop Box with the photo attached. The Gmail notice should now give counts and sizes only: no photo, no file name, no note text. *Changed: in version 1 the notice carried the photo.*
2. [ ] **Location removed.** Download that photo from the Drop Box entry. Open it on the phone in Files or Photos and look at its info: no map, no camera model. Compare with the original in Photos, which shows both. On a computer, ExifTool shows the same thing in more detail. If the download will not open, the encryption on arrival may be the cause; note it and tell the developer (VERIFY how the Drop Box serves encrypted files).
3. [ ] **Share sheet from Photos.** Pick three photos and a video, tap Share, then Send to GSR. If it is not in the row of apps, tap More and turn it on. The "Send to" menu should list all eight drop boxes. Switch it to Nothing to See Here and send from the sheet. Then share one more photo, tap "Finish in app", open GSR, and finish it from "Not sent yet". *Changed: eight drop boxes in the menu.*
4. [ ] **Scan.** Send tab > Scan a document, three pages. One PDF should arrive in Nothing to See Here.
5. [ ] **Voice note.** Record 20 seconds. The audio file should arrive and play.
6. [ ] **Large video, app in the background.** Pick or record a long video, several hundred megabytes. Press Send and go to the Home Screen right away. On iOS 26 and later the system shows the upload's progress. Come back later. The video should arrive whole in the Drop Box and play to the end. *Changed: the Gmail notice never carries files now, so the Drop Box is the only place to check.*
7. [ ] **Airplane mode mid-upload.** Start another large send. At about a third, turn on airplane mode. The file's row says "Connection hiccup, retrying". Turn airplane mode off within a minute. The upload should carry on from where it stopped, not from zero, and the file should arrive whole.
8. [ ] **Longer outage.** Do it again and leave airplane mode on for six minutes. After about two and a half minutes of retries the send stops with "Could not reach Granite State Report. Check your connection." The note has not gone, and the file waits for the next press. Turn airplane mode off and press the send button. It should resume from where it stopped, and the note should arrive with the file.
9. [ ] **Closed mid-send.** Start a send and swipe the app away. Reopen it. Nothing restarts on its own. "Not sent yet" shows it as stopped while sending; tap Finish, then the send button, and it resumes where it stopped.
10. [ ] **Fields.** Send Tell Us Your Story with a name, an email, a town, a choice under "What are you sending?", and "GSR may contact me" ticked. Compare the entry with one sent from the web page: same field names, the box as ticked.
11. [ ] **Text only.** A note with no files.
12. [ ] **Shortcuts.** Long-press the app icon: Send a Tip, Scan a Document, Record a Video. Say "Send a tip to GSR" to Siri.
13. [ ] **Contact tab.** Tap "Open the chat in Signal": Signal should open to the GraniteStateReport.09 chat. Copy the username, call, email, open each policy link. Then "Delete everything the app is holding" and confirm "Not sent yet" is empty. *Changed: the Signal button is new.*
14. [ ] **App switcher.** With a draft open, swipe up to the app switcher. It should show the masthead, not your draft.
15. [ ] **Latest.** Stories load and open. Stories that have a narration show a "Listen" line under them; tap one and it plays. The GSR tools list sits under the stories and each opens its page. *Changed: Listen buttons and the tools list are new.*
16. [ ] **Wild New Hampshire.** Open it from the Send tab. At the top: "Animal hurt, someone in danger, or a crime?" with the Fish and Game numbers. Under Files, the cleaning switch should be **off**, with a line saying the page asks for the original file. Attach a photo with a location. Under Quick details fill in When, Where, and What you think it is. Leave the note empty. Press "Send it to GSR". In the Drop Box, the entry is filed under the tips form and the note reads:

    ```
    [Wildlife]
    When: <what you typed>
    Where: <what you typed>
    Animal: <what you typed>
    Sent from: /wildlife/ (iPhone app)
    ```

    Download the photo: it should still have its location, because cleaning was off. Then send one from the /wildlife/ page in a browser and compare: the only difference in the note should be "(iPhone app)".
17. [ ] **Something You Can't Explain.** Pick the "In the sky" chip, fill in When and Which way you were facing, and add the note "TEST sky". The note in the Drop Box starts with `[Unexplained · In the sky]`, then the details, then the Sent from line, a blank line, and "TEST sky". Tap the chip twice and it should clear.
18. [ ] **Tap-to-call and page links.** On Wild New Hampshire, tap "(603) 271-3361". The phone asks whether to call. **Press Cancel.** Do not place the call. Then tap "list of licensed rehabilitators": the Fish and Game page opens inside the app.
19. [ ] **Send Research Files.** Attach a spreadsheet or PDF from Files and send. The Drop Box files it under the tips form with your note as typed and no label lines. The website's Research Files page does the same, so this is expected. If you want research entries labeled, that is a change to the site's page, and the app would follow it.
20. [ ] **Granite State Archive.** Read "What happens next" first: an archive submission is meant for publication. Send a record that is already public, or delete the entry right after. Fill in the source, the kind of record, and tick "GSR may contact me". The Drop Box should file it under the archive form, with those fields.
21. [ ] **Listen: an audio article.** Listen tab > Audio articles. The page's note on the voices is at the top, word for word. Play one. Lock the phone: it keeps playing, and the Lock Screen shows the title with pause, skip 15 seconds, and a scrubber. Unlock, set 1.5×, pause halfway, close the app from the app switcher, reopen: the row says "Resumes at" the time you stopped, and play starts there. Try the voice filter and the search box.
22. [ ] **Listen: a podcast episode.** Listen tab > Podcast. The "Made by AI, checked by the newsroom" note is at the top. Open an episode: the listener's note, the articles discussed, and "Read the transcript" all show. Play it, then open the player from the bar above the tabs and drag the scrubber.
23. [ ] **Headphones out.** Play anything through headphones, then unplug them or turn the Bluetooth headphones off. Playback should pause instead of switching to the speaker.

Record one full send with Screen Recording from Control Center and keep the video. App Review can watch it instead of sending a test tip.

### What to send back

For any item that fails, send:

- the item number;
- a screenshot of the screen, or the exact words of any error;
- for items 16, 17, 19 and 20, the note and fields exactly as the Drop Box shows them;
- if a GitHub run failed, the link to the run.

Then delete the TEST entries from the Drop Box and Gmail.

## (h) Fill in the App Store listing

Publish the privacy policy update on the site first. Guideline 5.1.1 requires the linked policy to cover what the app collects. The live policy (last updated October 11, 2026) does not cover the app, still says the forms are run by Jetpack, and still says files are emailed to Gmail. Text: `GSR_iOS_App_Privacy_Policy_Update_v2_2026-10-13.md`.

Then, in App Store Connect, from `GSR_iOS_App_Store_Listing_v2_2026-10-13.md`:

- [ ] **App Information:** name, subtitle, category News, content rights.
- [ ] **The 1.0 version page:** promotional text, description, keywords, support URL, marketing URL, copyright, screenshots (the workflow saves them as JPEG, ready to upload).
- [ ] **App Privacy:** privacy policy URL and the nutrition-label answers. Settle the open questions in that section first.
- [ ] **Accessibility:** if App Store Connect asks what the app supports (VoiceOver, Larger Text and the rest), claim only what you have tried on your own phone. VERIFY whether it is required at submission.

### Age rating

Apple's questionnaire gives ratings of 4+, 9+, 13+, 16+ and 18+. These are recommended answers. **Publisher to confirm each one.**

| Question | Answer | Why |
|---|---|---|
| Parental controls | No | |
| Age assurance | No | |
| Unrestricted web access | No (VERIFY) | No address bar and no search. The app opens fixed pages (stories, the site, the tools, the policy pages, links inside the drop box pages, signal.org) in Safari's in-app view. Links on those pages can lead elsewhere, which is why this is a judgment call. Answering Yes makes the app 16+. |
| User-generated content | No | Submissions go only to the editor and are never shown to anyone else. |
| Social media | No | |
| Messaging and chat | No (VERIFY) | Sending to the newsroom is one way. Users cannot reach each other. |
| Advertising | No | |
| Profanity or crude humor | None | |
| Horror or fear themes | None (VERIFY) | Something You Can't Explain takes paranormal footage, but the app shows none; it shows the page's text. |
| Alcohol, tobacco, or drug use or references | Infrequent | The Latest tab, the Listen tab and the NH Bill Tracker carry news on bills about cannabis, alcohol and drugs. |
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

1. **The audience is here.** The newsroom covers New Hampshire public bodies. The tip pages are written around New Hampshire and federal law, and the privacy policy says the site is published for a New Hampshire audience.
2. **The EU asks for a trader decision.** To sell in the European Union, App Store Connect asks whether you are a "trader" under the Digital Services Act. A trader's address, phone number and email are shown on the EU product page after Apple verifies them (VERIFY the current details in App Store Connect Help). Whether a free app from a one-person newsroom makes you a trader is a legal question this checklist cannot answer. US-only takes it off the table.
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
- **Encryption on arrival.** The app's safety note repeats the site's new sentence, "Files are encrypted as they arrive, and the notice gives counts and sizes only." The app cannot see the server. VERIFY that both are true before the app ships with that sentence in it.
- **Xcode version.** Apple's submission page says that from April 2027, uploads must be built with the iOS 27 SDK. The workflow uses Xcode 26.6 today. The developer needs to move it to Xcode 27 before then.
- **The weekly checks.** Every Monday the workflow compares the app's eight drop boxes with the live pages, and reads the Audio Articles and Podcast pages with the app's own code. A red "Drop box forms still match the site" or "Audio Articles and Podcast pages still read" job means a page changed and the app needs an update. Installed copies keep sending the old fields until people update, so change field names on the site with care.
- **The Quick details label.** On the sighting pages the site's script writes `[Wildlife]` or `[Unexplained]` and a "Sent from" line into the note, and the app copies that format. If you change the script's format, the forms check fails until the app is updated to match.
- **The Listen tab reads the pages.** If the Audio Articles or Podcast page changes its layout so the app cannot find the note about how recordings are made, the app shows nothing from that page and offers a link to it instead. It never shows the recordings without the note.
- **TestFlight builds expire** after 90 days. Run the workflow again for a fresh one.
- **The app is not anonymous,** and every send screen, the store description and the review notes say so. Keep it that way in every update.

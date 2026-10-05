# Granite State Report iPhone app: App Store listing

Version 1 · 2026-10-05 · Granite State Report

The words for App Store Connect, field by field. Paste from inside the boxes. Every count below was taken by script from the exact text in the box: characters for every field, bytes for keywords. Anything marked VERIFY is a fact this document could not confirm from the app's code, the site, or Apple's published pages.

## At a glance

| Field | Limit | This text |
|---|---|---|
| Name | 30 characters | 20 |
| Subtitle | 30 characters | 27 |
| Promotional text | 170 characters | 169 |
| Description | 4,000 characters | 3492 |
| Keywords | 100 bytes | 97 |
| App Review notes | | 2531 |
| Support URL | | https://granitestatereport.com/tips/ |
| Marketing URL | | https://granitestatereport.com/ |
| Privacy Policy URL | | https://granitestatereport.com/privacy-policy/ |
| Primary category | | News |
| Copyright | | 2026 Granite State Report (VERIFY: legal owner name) |

## Name (20 of 30)

```text
Granite State Report
```

The Home Screen shows the shorter display name, GSR, and Siri phrases use it ("Send a tip to GSR"). App Store names are one per app, so App Store Connect refuses a name another app already uses. VERIFY that "Granite State Report" is free when you create the record.

## Subtitle (27 of 30)

```text
Send tips, files, and video
```

Alternate if you would rather lead with the state (23 of 30): `New Hampshire news tips`

## Promotional text (169 of 170)

```text
Something wrong in a New Hampshire public body? Send Granite State Report a tip, records, photos, video, or a voice note. Nothing leaves your phone until you press Send.
```

Promotional text sits above the description and can be changed at any time without a new build. Use it for news about the app, such as a new drop box.

## Description (3492 of 4,000)

```text
Something wrong in a New Hampshire public body? Tell Granite State Report.

Granite State Report is an independent newsroom in Northfield, New Hampshire. This app is its tip line. It sends to the same drop boxes as the tip pages on granitestatereport.com, and the editor reads everything that comes in.

THIS APP IS NOT ANONYMOUS
Read this before you send anything. What you send is stored on the site's server with the host, WordPress.com, and a notice is emailed to the newsroom's Gmail account, with the files attached when they total under 15 MB. The host logs IP addresses. Never use a work phone, work email, or work Wi-Fi. Your employer can see what crosses them.

For anything sensitive, use Signal or the mail, not this app. Signal is the best mix of safe and easy. Mail leaves the least digital trail. Both are on the app's Contact tab.

WHAT YOU CAN SEND
- Words, photos, video, documents, voice notes, or any other file type, up to 2 GB each and 50 at a time
- Paper documents, scanned with the camera into one PDF
- Anything from Photos, Files, Mail, or any other app: tap Share, then Send to GSR
Nothing has to be typed. Leave the contact box blank to stay unnamed; without it, there is no way to write back.

FOUR DROP BOXES, THE SAME AS THE WEBSITE
- Quick tip. Short on time? It reaches the same editor.
- Tell Us Your Story. Something a town, agency, court, school, or police department did to you or in front of you.
- Nothing to See Here. A memo, email, contract, or report from a public body.
- Inside the Building. For people who work in New Hampshire government and saw waste, misconduct, or a broken law. Read what the law says about speaking up first.

WHAT THE APP DOES WITH YOUR FILES
- Nothing leaves your phone until you press Send.
- Location, phone model, and the time taken come out of photos and videos before anything uploads, unless you turn that off. Documents keep their own details, such as author names and edit history. The app cannot clean those.
- Big files go up in pieces. If the connection drops, the app keeps trying. If a send stops, it waits on your phone and picks up where it left off when you press Send again. On iOS 26 and later, a send can keep going after you leave the app.
- Once the drop box confirms a send, the app deletes its copy. Drafts you have not sent stay inside the app, left out of iCloud and computer backups, until you send or delete them.
- No account, no ads, and no analytics of its own.

ALSO IN THE APP
- The latest stories from granitestatereport.com
- Every way to reach the editor: Signal, mail, phone, and email
- Home Screen and Siri shortcuts to send a tip, scan a document, or record a video

HOW WHAT YOU SEND IS HANDLED
The editor reads it. Granite State Report is one reporter in Northfield. Nobody else opens the submissions. Your name stays out of anything published unless you say in writing that it can be used. Nothing is published on one person's word: tips are checked against records and people, and the agency is asked to respond.

GSR will refuse any demand to identify a confidential source, and will fight it. That protection is qualified: a court can, in some cases, order disclosure. The best protection is information GSR never had, so send only what is needed to check the story.

Granite State Report does not pay for tips, is not your lawyer, and gives no legal advice. Do not send classified national-security information, another person's medical records, or anything involving a child.
```

Rules this text follows, and any edit has to keep following:

- It never calls the app anonymous, secure, or safe. It says the opposite in its second section, in the tips pages' own words: the site says "The online forms are not anonymous" and "For anything sensitive, use Signal or the mail, not the form." The app's own safety note says "This app is not anonymous."
- "Signal is the best mix of safe and easy. Mail leaves the least digital trail." is the site's sentence, word for word.
- The handling section repeats the Send a Tip page (v1.3, October 2, 2026). If that page changes, change this to match.
- Other companies' names appear only where the text has to say where data goes or what the app works with (WordPress.com, Gmail, Signal, iCloud, Siri). None are in the keywords. Guideline 2.3.7 bars padding metadata with trademarked terms.

## Keywords (97 of 100 bytes)

```text
tip line,whistleblower,public records,Right-to-Know,91-A,New Hampshire,NH,documents,newsroom,scan
```

Comma-separated, no spaces after commas. Words already in the name and subtitle (Granite, State, Report, tips, files, video) are left out because those fields already carry them. Brand names such as Signal are left out on purpose.

## URLs

- **Support URL:** https://granitestatereport.com/tips/ . It lists every way to reach the editor. Guideline 1.5 asks for an easy way to contact you at the support URL.
- **Marketing URL:** https://granitestatereport.com/
- **Privacy Policy URL:** https://granitestatereport.com/privacy-policy/ . The live policy does not cover the app yet, and it still says the forms are run by Jetpack. Publish the update in `GSR_iOS_App_Privacy_Policy_Update_v1_2026-10-05.md` before you submit. Guideline 5.1.1 requires the linked policy to cover what the app collects. The app's Contact tab already links to this URL.

## Category

- **Primary:** News. The app's Info.plist already declares `public.app-category.news`.
- **Secondary:** leave it blank. It is optional, and no second category fits.

## Copyright

```text
2026 Granite State Report
```

VERIFY: legal owner name. This line should name whoever owns the app. If you enroll as an individual, that is you, under your legal name, unless Granite State Report is a registered entity that owns the newsroom's work. Match whatever the site's own copyright line says.

## Content rights

App Store Connect asks whether the app contains, shows, or accesses third-party content. The Latest tab shows the newsroom's own stories and their featured images from granitestatereport.com. Answer No unless any featured image is licensed from someone else. VERIFY against the images on recent stories.

## App Privacy (the nutrition label)

These answers match `ios/App/Resources/PrivacyInfo.xcprivacy` and `ios/ShareExtension/PrivacyInfo.xcprivacy`, which declare the same ten types.

In App Store Connect: App Privacy > Get Started > "Do you or your third-party partners collect data from this app?" **Yes.** Then select:

| Data type | Why the app collects it | Used for | Linked to the user | Tracking |
|---|---|---|---|---|
| Contact Info > Name | Tell Us Your Story asks "Your name"; Nothing to See Here asks "A name to call you" | App Functionality | Yes | No |
| Contact Info > Email Address | The email fields on Tell Us Your Story and Nothing to See Here | App Functionality | Yes | No |
| Contact Info > Phone Number | The contact boxes on the quick tip and Inside the Building ask for "personal email, Signal, or phone" | App Functionality | Yes | No |
| User Content > Photos or Videos | Camera, Photos, and the share sheet | App Functionality | Yes | No |
| User Content > Audio Data | Voice notes, and the sound on videos | App Functionality | Yes | No |
| User Content > Other User Content | The note, the free-text fields, documents, and scans | App Functionality | Yes | No |
| Contact Info > Other User Contact Info | The contact boxes invite a Signal username | App Functionality | Yes | No |
| User Content > Emails or Text Messages | Nothing to See Here asks for pasted emails and chats; the share sheet takes text from Mail | App Functionality | Yes | No |
| Location > Coarse Location | The town, agency, and "where" fields | App Functionality | Yes | No |
| Location > Precise Location | Photos and videos sent with "Remove hidden details" turned off keep their GPS location | App Functionality | Yes | No |

For each type, tick **App Functionality** and nothing else. Answer **Yes** to "linked to the user's identity" and **No** to "used for tracking".

**Why linked.** Apple counts data as linked unless it is stripped of identifiers before collection, and it counts anything that privacy laws call personal information as linked. A GSR submission is stored whole, with whatever name or contact the sender gave, so the editor can read it and write back, and the host logs the IP address. Nothing is de-identified, and nothing can be without defeating the point. Answering "not linked" would claim an anonymity the app does not offer, and the description says so in plain words.

**Why no tracking.** The app has no ads, no analytics, and no third-party code, and nothing it sends goes to an ad network or a data broker.

**Why the last four.** They over-declare on purpose. A Signal username is "other information that can be used to contact the user outside the app" in Apple's words. A field that asks for a specific kind of data (pasted emails) needs that type declared. Town fields place the sender roughly, and a photo sent with cleaning turned off places them exactly. Declaring a type the app may collect is safe; leaving one out is what gets apps flagged.

### Settle these before you submit

1. **Web pages inside the app.** The Latest and Contact tabs open granitestatereport.com in Safari's in-app view, and the site runs Google Analytics. Apple's guidance says data collected through web views must be declared, unless the app is only letting the user browse the open web. It does not say how that applies to Safari's in-app view. VERIFY. If you decide it counts, the privacy policy's own description of Google Analytics (pages viewed, rough location, device type) points to Usage Data > Product Interaction and Location > Coarse Location, used for Analytics.
2. **IP addresses.** Apple says to declare IP addresses according to how you use them. The newsroom does not use them to locate or identify anyone, so nothing is declared for them. VERIFY whether the GSR Drop Box plugin stores the sender's IP with each entry. If it does, and anyone ever uses it, revisit this answer.

## App Review notes (2531 characters)

Paste into App Review Information > Notes.

```text
Granite State Report is a one-person independent newsroom in Northfield, New Hampshire. This app is its tip line: people use it to send the editor tips, documents, photos, videos, and voice notes about New Hampshire public bodies.

NO LOGIN. The app has no accounts. Every feature works without signing in.

WHERE SUBMISSIONS GO. Everything sent goes to the newsroom's own drop box on granitestatereport.com, the same endpoint the site's four tip pages use (https://granitestatereport.com/wp-json/gsr-drop/v1/). Only the editor reads submissions. They are never shown to other users. There is no public posting, no feed of user content, and no messaging between users.

HOW TO TEST WITHOUT FILING A FAKE TIP
1. On the Send tab, tap Send a Tip (any of the four drop boxes works the same way).
2. Type "App Review test" in the note. Attach a photo if you like. Leave the contact box blank.
3. Press "Send the tip". The app uploads, shows "Sent. Thank you.", and deletes its copy.
The editor expects test notes during review and discards anything marked "App Review test". If you would rather not send anything, the attached screen recording shows a full send from a TestFlight build, start to finish.

NATIVE FEATURES
- Camera (photo and video), document scanner (VisionKit), and voice recorder. The camera and microphone are requested only when the user opens those tools.
- Photos and files come through the system pickers (PhotosPicker, document picker), so the app never asks for photo library access.
- Share extension: "Send to GSR" in the share sheet.
- Before upload, the app removes location and device metadata from photos and videos and checks the result.
- Background: UIBackgroundModes "processing" and the BGTaskSchedulerPermittedIdentifiers entry (com.granitestatereport.app.send.*) serve one purpose. On iOS 26 and later, pressing Send starts a BGContinuedProcessingTask so a large upload keeps going after the user leaves the app, with progress and a stop control shown by the system. Nothing runs in the background unless the user pressed Send.
- Home Screen quick actions and App Shortcuts open a drop box directly.

LATEST TAB. The newsroom's own stories, read from the site's public WordPress REST API and opened in SFSafariViewController.

PRIVACY. No analytics, no advertising, no third-party SDKs. Every send screen says plainly that the app is not anonymous, and the app points people with sensitive material to Signal or the mail.

CONTACT. Granite State Report, (603) 931-9264, granitestatereport@gmail.com
```

Also in App Review Information:

- **Sign-in required:** No.
- **Contact:** first and last name (VERIFY: whose), phone (603) 931-9264, email granitestatereport@gmail.com.
- **Attachment:** the screen recording of a full send, made during the TestFlight test in the launch checklist. If you do not attach one, delete the sentence about it from the notes.
- Keep the sentence "The editor expects test notes during review and discards anything marked App Review test" only if it is true. Watch the Drop Box while the app is in review.

## Export compliance

The app's only encryption is HTTPS through Apple's `URLSession`. There is no other cryptography in the code and no third-party library. `project.yml` sets `ITSAppUsesNonExemptEncryption` to false, which Apple's page on encryption export rules describes as the right setting when an app uses only exempt encryption, and gives HTTPS through `URLSession` as the typical exempt case. With that key in the Info.plist, App Store Connect does not ask the encryption questions for each build.

The same Apple page says an app using exempt encryption "might" owe the U.S. government a year-end self-classification report, and ties export rules to distribution outside the U.S. and Canada. With United States-only availability (see the launch checklist), that should not arise. VERIFY before widening availability.

## Screenshots

Every run of the iOS app workflow's macOS job takes five screenshots of the real simulator build on an iPhone 17 Pro Max and uploads them as the artifact `ios-screenshots-<run number>` (Actions > the run > Artifacts, kept 30 days). They are 1320 x 2868 pixels, portrait, one of the 6.9-inch sizes App Store Connect accepts. A 6.9-inch set is enough: App Store Connect scales it for smaller iPhones.

| File | Shows | Use |
|---|---|---|
| `1-send.jpg` | Send tab: masthead, "Capture it now", the first drop boxes | First |
| `2-quick-tip.jpg` | Send a Tip, with "Before you send anything" and "This app is not anonymous" at the top, then the file buttons | Second |
| `3-documents.jpg` | Nothing to See Here, same layout | Third |
| `5-contact.jpg` | Contact: Signal username, the mailing address | Fourth |
| `4-latest.jpg` | Latest stories | Last, or leave out |

- **Alpha channel.** Apple's screenshot spec says images "can't include alpha channels or transparencies". Simulator screenshots come out as PNGs with one, so the workflow converts them to JPEG before saving the artifact. Upload them as they are.
- **Latest changes with the news.** That shot shows whatever stories were newest when the workflow ran. Guideline 2.3.8 says screenshots must suit a 4+ audience whatever the app's rating, so look at the images in it before you use it.
- The status bar reads 9:41 with full signal and battery, set by the workflow.
- On the Send tab shot, Photo or video and Scan a document are grayed out because the simulator has no camera. On a phone they are live. If that looks wrong as the first image, lead with `2-quick-tip.jpg` instead.

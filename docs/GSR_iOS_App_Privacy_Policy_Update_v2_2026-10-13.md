# Granite State Report iPhone app: privacy policy update

Version 2 · 2026-10-13 · Granite State Report

Paste-ready text for granitestatereport.com/privacy-policy/ so the policy covers the iPhone app and catches up with the website. This is drafting help, not legal advice.

## What changed from version 1

- The live policy was revised on October 11, 2026, but its forms entry was not. It still says the forms are run by Jetpack and that files are emailed. The drop box pages changed again on October 10 and 11. Item 1 below now uses their current wording.
- The Archive question is settled: the Granite State Archive's "Submit a record" box is a GSR Drop Box (form `archive`), per that page's own version log.
- Eight drop boxes are named, up from four.
- The app section covers the Quick details lines, the two drop boxes that start with photo cleaning off, and the Listen tab.
- New: an ElevenLabs entry under Third-party services. The site's article pages load ElevenLabs' player, and the policy does not name it.

## First: the policy is out of date for the website

The live policy (Last updated October 11, 2026) says, under Information you choose to give: "The site's contact and submission forms, including the document-upload form on the Granite State Archive page, are run by Jetpack (Automattic). What you type and any file you attach are stored on WordPress.com with the site's form records and are also emailed to the newsroom's Gmail account." Under Third-party services it says WordPress.com and Jetpack provide "the comment, sharing, subscription, and contact-form features, including file uploads."

The drop box pages say otherwise:

- The Archive's version log: "October 2, 2026: the Jetpack upload form, capped at one file of 20 MB, was replaced with the GSR Drop Box." The tips pages logged the same change that day.
- The Archive's version log: "October 10, 2026: added a not-anonymous warning saying submissions are stored on this site's server and notices are emailed to the newsroom's Gmail account and to the editor's personal Gmail account."
- The same log: "October 11, 2026: files are now encrypted on the server as they arrive, and notice emails carry counts and sizes only, never the files, file names, or anything typed."

So the policy is wrong about the website in three ways: the forms are not Jetpack's, files are not emailed, and a second Gmail account gets the notice. The policy's own opening says what happens next: "If a practice described here ever stops matching what the site does, the site is wrong and this page will be corrected." Fix the website and the app in one revision.

The site's article pages also load ElevenLabs' audio player (the script `https://elevenlabs.io/player/audioNativeHelper.js` and a player from `elevenlabs.io/player/`, under the byline), and the Audio Articles page plays 181 of its 187 recordings from `eleven-public-cdn.elevenlabs.io` (the other six, and every podcast episode, are on granitestatereport.com; counted October 13, 2026). The policy's Third-party services list does not name ElevenLabs. Item 3 adds it.

## What Apple requires of the policy

App Store guideline 5.1.1(i) says the policy linked from App Store Connect and from inside the app must:

- say what data the app collects, how it collects it, and all uses of it;
- confirm that any third party the app shares data with gives the same or equal protection as the policy;
- explain retention and deletion, and how a user can revoke consent or ask for deletion.

The text below covers each. The third-party sentence is the one you have to decide on (item 4 under "Confirm before publishing").

## 1. Replace the "Forms and document uploads" paragraph

Under Information you choose to give, replace the whole Forms and document uploads entry with the text below. Bracketed notes are for you; take them out before publishing.

> **Forms and document uploads.** The drop boxes on Send a Tip, Send Research Files, Tell Us Your Story, Something You Can't Explain, Wild New Hampshire, Inside the Building, Nothing to See Here, and the Granite State Archive are run by the GSR Drop Box on this site, which replaced the Jetpack forms on October 2, 2026. The forms are not anonymous. What you type and any file you attach are stored on this site's server with the host, WordPress.com (Automattic), and kept in the site's private Drop Box. Files are encrypted as they arrive. A notice is emailed to the newsroom's Gmail account and to the editor's personal Gmail account, which Google hosts under its own terms; the notice gives counts and sizes only: no files, no file names, nothing you typed. Like every page load, sending a form leaves your IP address, browser, and the time with the hosting platform. Files you drop on other pages of this site are held in your own browser only until the Nothing to See Here page opens, then cleared. The editor reads what comes in, and nobody else opens the submissions. It is used for reporting: checked against records and people before anything is published, and your name stays out of anything published unless you say in writing that it can be used. If you leave a way to reach you, the editor uses it only to ask about what you sent. [VERIFY: Inside the Building promises this; confirm it holds for every drop box and the app.] Granite State Report will refuse any demand to identify a confidential source, and will fight it, but a court can, in some cases, order disclosure. A document you submit for the archive is meant for publication: it is read, checked, redacted as that page describes, then posted publicly and permanently, and the entry may say where it came from. If you want a document held in confidence or your name kept off it, say so in the message before you send it. What you send stays in the newsroom's files until it is no longer needed for the story; ask if you want it deleted sooner. [VERIFY: publisher to confirm. The newsroom has not set a fixed period, and this sentence extends the archive wording to every submission.] To ask, write or call the editor. If you sent an email address, write from that address so the request can be matched. If you left no contact details, say which drop box you used, roughly when, and enough about what you sent for the editor to find it. For anything sensitive, use Signal or the mail instead of a form; the Send a Tip page explains both.

## 2. Add a new section: "The iPhone app"

Put it after Information you choose to give and before Third-party services on the site. The references to "above" and "below" assume that spot.

> ## The iPhone app
>
> The Granite State Report app for iPhone (it shows as GSR on the Home Screen) sends to the same drop boxes as the forms on this site. Everything under Forms and document uploads above applies to what you send through it, including this: the app is not anonymous.
>
> **What it sends, and when.** Nothing leaves your phone until you press Send. Then the app sends what you put in the drop box: your note, any details you chose to fill in (such as a name, an email address, a phone number or Signal username, a town, or an agency), and the files you attached, which can be photos, videos, voice recordings, scans, and documents. On Wild New Hampshire and Something You Can't Explain, the Quick details you fill in (when, where, and the rest) go at the top of your note, with a line saying it was sent from the app, as the website writes them from those pages. Everything goes over an encrypted connection (HTTPS) straight to this site's server and is handled exactly like a form submission. Each request carries your IP address, as every internet connection does, and names the app and its version.
>
> **What it takes out first.** The app can remove location, phone make and model, camera software, and the time taken from photos and videos before they upload, then check the cleaned copy. This is on unless you turn it off, except on Wild New Hampshire and Something You Can't Explain, which ask for the original file because its date, time, and place are what let the newsroom check it; there it starts off, and you can turn it on. A photo or video the app cannot clean is held back until you remove it or choose to send it as it is. Documents go as they are: author names and edit history stay in them.
>
> **What stays on your phone.** Drafts you have not sent stay inside the app until you send or delete them, and are left out of iCloud and computer backups. Anything sent is deleted from the phone as soon as the drop box confirms it. If the drop box refuses a file (too large, or over the limit for one send), that file stays in a new draft so you can send it next or delete it. The originals in your Photos or Files stay where they were. The Contact tab has a button that deletes everything the app is holding.
>
> **Listening.** The Listen tab plays the newsroom's audio articles and podcast episodes, the same recordings as the Audio Articles and Podcast pages. Most audio articles play from ElevenLabs' servers; the rest, and the podcast episodes, play from this site. Either way, the server sees your IP address when you play one. Where you stopped in each recording is kept in the app on your phone and is not sent anywhere.
>
> **What it does not do.** The app has no account and no ads, runs no analytics or tracking code of its own, and contains no code from advertising or analytics companies. It does not ask for your location or your contacts. It never sees your photo library: you choose photos and files with the iPhone's own pickers, and only what you choose reaches the app. It asks for the camera and microphone only when you take a photo or video, scan a document, or record a voice note. You can turn either off in Settings.
>
> **Stories and pages.** The Latest tab reads the newest stories from this site's public list of posts. Stories and the site's other pages open in Safari's in-app view, where the cookies and third-party services listed below, Google Analytics included, work as they do on the website.
>
> **Calls and email.** Calling or emailing from the app opens your Phone or Mail app, and opening the Signal chat opens Signal. What happens after that is covered under Email and phone above.
>
> **Your choices in the app.** Nothing is sent until you press Send. You can delete a draft, or everything the app holds, at any time. You can turn the cleaning of photos and videos on or off before a send starts. Once something is sent, ask the editor to delete it, as Forms and document uploads describes.
>
> **Children.** The app follows the Children section below. It is not directed to children under 13.

## 3. Smaller edits that go with it

**Date line.** `Policies · Last updated [the date you publish] · Granite State Report`

**Opening paragraph**, second sentence. Replace with:

> This page explains what the site and its iPhone app collect when you read the site, listen to it, comment on it, sign up for anything, or send the newsroom something, why that information exists, who else can see it, and how to get it removed.

**What this covers.** Replace the first sentence with:

> This policy applies to granitestatereport.com, to the Granite State Report app for iPhone, and to email you send to the addresses listed on the site.

**Third-party services, the WordPress.com entry.** Replace with:

> WordPress.com and Jetpack host the site, store what is sent through the GSR Drop Box, run its own traffic statistics, deliver the newsletter, and provide the comment, sharing, and subscription features. Akismet checks comments for spam, which means the text of a comment and the commenter's IP address are sent to Akismet. Gravatar supplies commenter avatars.

[VERIFY: if any form on the site is still run by Jetpack, such as a contact form, put "and contact-form features" back in.]

**Third-party services, two new entries** after that one:

> Gmail, run by Google, holds the newsroom's email and the editor's personal email, including the notice of each drop box submission, which gives counts and sizes only.

> ElevenLabs hosts most of the audio narrations of articles and provides the player under each article's byline. Article pages load that player, and playing a narration, on the site or in the app, fetches the recording from ElevenLabs' servers, which see your IP address. ElevenLabs' practices are described in its privacy policy.

[VERIFY: whether ElevenLabs' player sets cookies or collects anything beyond the request. Read its privacy policy, add a link, and add a sentence if it does.]

**How long it is kept.** Add at the end:

> Drop box submissions, from the site or the app, are kept until they are no longer needed for the story; ask if you want one deleted sooner. The app keeps nothing on your phone once a send is confirmed.

[VERIFY: same retention sentence as in item 1; confirm once for both.]

**Your choices.** Add after the first sentence:

> In the app, you can delete any unsent draft, or everything the app holds, from the Contact tab. To have a submission deleted after it is sent, see Forms and document uploads.

**Version log.** Add:

> [Date you publish], 2026: the forms and document uploads entry now names the GSR Drop Box, which replaced the Jetpack forms on October 2, 2026, and says what the forms collect, that files are encrypted as they arrive, that notices give counts and sizes only and go to the newsroom's and the editor's Gmail accounts, how it is used, how long it is kept, and how to have it deleted; added a section on the Granite State Report app for iPhone; What this covers now includes the app; the WordPress.com and Jetpack entry under Third-party services now says the site's server stores drop box submissions, and entries were added for Gmail and for ElevenLabs, whose player was in use on article pages and was not named.

## Confirm before publishing

1. **Encryption and the notice.** The text says files are encrypted as they arrive and the notice gives counts and sizes only, because the drop box pages say so. Neither this document nor the app can see the server. Confirm both.
2. **Retention.** The newsroom has not set a fixed retention period. The text uses the policy's existing wording, "until it is no longer needed for the story; ask if you want it deleted sooner", and extends it from archive documents to every submission. Confirm that is what happens, or change it.
3. **Contact use.** "If you leave a way to reach you, the editor uses it only to ask about what you sent" is Inside the Building's promise. Confirm it for every drop box, or cut the sentence.
4. **Equal protection.** Guideline 5.1.1 asks the policy to confirm that third parties who receive app data give the same or equal protection. The policy says providers handle data "under their own terms", which may not satisfy a reviewer. A sentence you could add under Who else sees it, if you are satisfied it is true after reading the companies' terms: "Automattic, which runs WordPress.com, Google, which runs Gmail, and ElevenLabs, which hosts most narrations, hold what reaches them under their own privacy terms, which protect it at least as well as this policy does." VERIFY before adding.
5. **The IP address.** The text says each request carries the IP address and the host logs it, which matches the drop box pages. VERIFY whether the GSR Drop Box plugin also stores the IP with each entry. If it does, say so in item 1.
6. **Publish before submitting the app.** The policy has to cover the app on the day App Review reads it.

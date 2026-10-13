# GSR iPhone app: what the site changed, and what the app does about it

Version 1 · 2026-10-13 · Granite State Report

Checked against the live site on October 13, 2026, by reading the pages and the drop box API directly. Pull request #12, branch `claude/gsr-ios-app`.

## First, two gaps in your message

- **"[individual/organization]"** was left as written. It decides the seller name on the App Store and the copyright line. The build does not depend on it.
- **"Here is what happened on the first real send"** had nothing after it. No result reached me. The launch checklist (test item 1) is that send; tell me what happened, word for word, using "What to send back" at the end of the checklist.

## What changed on granitestatereport.com since the app was built (October 5)

| Change on the site | Where it shows | What the app does now |
|---|---|---|
| Three new pages carry the Send a Tip box: Send Research Files, Wild New Hampshire, Something You Can't Explain | `/research-files/`, `/wildlife/`, `/unexplained/`; the Send menu | Three new drop boxes. They go to the server as `tips`, as the pages do. |
| The Granite State Archive's "Submit a record" box is a GSR Drop Box (form `archive`) | `/archive/` | A new drop box, with its seven fields and its "What happens next" (it gets published) shown before Send. |
| A Quick details panel on the two sighting pages writes a label at the top of the note (`[Wildlife]`, `When: ...`, `Sent from: /wildlife/`) | The site's `gsr-sight-js` script | The app writes the same lines, adding "(iPhone app)" to the Sent from line, so you can tell app sends apart. Same fields, same chips, same button words. |
| The sighting pages ask for "the original file" because it carries the date, time, and place | `/wildlife/`, `/unexplained/` | On those two boxes, photo and video cleaning starts off, with the reason under the switch. The sender can turn it on. Everywhere else it starts on. |
| Wild New Hampshire puts Fish and Game, Operation Game Thief, and USDA numbers first | `/wildlife/` | Shown at the top of that screen. The numbers dial on tap. |
| Drop box warning, October 10 and 11: notices go to the newsroom's Gmail and the editor's personal Gmail; files are encrypted on arrival; notices give counts and sizes only | Nothing to See Here v2.3; the Archive's version log | The app's safety note, the store description, and the policy draft use the new wording. The old "files attached under 15 MB" line is gone everywhere. |
| Audio Articles page: 187 recordings, 181 in a voice clone of your voice, 6 synthetic | `/audio-library/` | New Listen tab, with the page's note on the voices at the top, word for word. |
| Podcast page: 27 episodes, AI hosts, listener's notes, transcripts | `/podcast/` | Same tab. Each episode shows its listener's note, the articles discussed, and the transcript. |
| The Send menu lists GSR tools | Site-wide menu | Listed under the stories on the Latest tab. |
| A Signal username link on the Send a Tip page | `/tips/` | Contact tab: "Open the chat in Signal". |
| Page text versions: Send a Tip, Tell Us Your Story, Inside the Building 1.3 to 1.5; Nothing to See Here 2.1 to 2.3 | Page bylines | Read-first text regenerated from the pages. |
| Nothing changed in the upload API or the site's upload script | `wp-json/gsr-drop/v1`, `dropbox.js` | No protocol change needed. |

## Things on the website you may want to fix

These are site issues, not app issues. I changed nothing on the site.

1. **The privacy policy is wrong about the drop boxes.** Revised October 11, it still says the forms are run by Jetpack and that "any file you attach" is emailed to Gmail. The drop box pages say the opposite since October 2 and October 11. Draft fix: `GSR_iOS_App_Privacy_Policy_Update_v2_2026-10-13.md`.
2. **The policy does not name ElevenLabs.** Article pages load `elevenlabs.io/player/audioNativeHelper.js` and an ElevenLabs player under the byline, and 181 of the 187 audio articles play from `eleven-public-cdn.elevenlabs.io`. The draft adds an entry.
3. **A third email address.** The site-wide "Reach the editor" menu says "Email dexterdow@granitestatereport.com". The Send a Tip page body and the footer say granitestatereport@gmail.com. Your standing instructions list granitestatereport@gmail.com as GSR-facing and dexterdow33@gmail.com as editor-direct, and do not mention the granitestatereport.com address. The domain does have mail service (its MX records point to Titan). The app keeps granitestatereport@gmail.com, matching the Send a Tip page. Tell me if the domain address should replace it.
4. **Research Files sends are unlabeled.** The site's Quick details script does not run on `/research-files/`, so those sends arrive as plain tips. The app does the same. If you want them labeled, change the site's script and the app follows.

## What I could not verify

- That files are encrypted on arrival and that the notice gives counts and sizes only. The app repeats the site's sentence; I cannot see the server.
- Whether the Drop Box admin serves encrypted files back as normal downloads (test item 2 checks it).
- That the iOS parts compile, until the macOS CI job finishes. Status is in the pull request.

## Next-step prompt

Paste this into the next conversation after you run the checklist:

```text
GSR iOS app, PR #12 in dexterdow33/BlogPostPreviewer. I enrolled as [individual / organization: pick one]. I merged PR #12 and ran the TestFlight workflow: [run link]. Test plan results from docs/GSR_iOS_App_Launch_Checklist_v2_2026-10-13.md, items 1-23: [pass/fail per item; for each failure, the exact error text or a screenshot; for items 16, 17, 19, 20, the note and fields as the Drop Box shows them]. Fix what failed, then take me through steps (h) to (j).
```

# Refined M4 and new modules M8 to M13

This document covers two things:

- **M4 AI Audiobook Creation**, refined from AP1's M4 AI module. It now has
  FR7 and FR62 to FR64, and use cases UC4.1 to UC4.4.
- **New modules M8 to M13**, added after AP1. They have FR28 to FR61 and use
  cases UC8.1 to UC13.5.

The other AP1 modules and requirements are not repeated here. Each
requirement has an acceptance check so it can be tested.

Every module has at least 4 functional requirements and at least 4 use cases.
The first draft had ten modules (old M8 to M17), and six of them had fewer
than 4 requirements. Those six were merged with modules that do similar work.
The FR numbers did not change.

| New module | Made from (first draft) | FRs | Use cases |
|---|---|---|---|
| M8 Background Music Studio | M8 Music intelligence (3), M9 Music taste (2), M10 Piano composer (1) | 6 | 6 |
| M9 Interactive and Al-Quran Audiobooks | M11 Interactive branching audiobooks (3), M12 Al-Quran audio pack (3) | 6 | 5 |
| M10 Community Hub | M13 Community hub (6) | 6 | 6 |
| M11 Accounts and Onboarding | M14 Personal accounts and starter library (2), M15 Interactive guide (2) | 4 | 5 |
| M12 AI Adaptive Settings (smart tips) | M16 AI adaptive settings (6), which takes over the adaptive settings part of AP1's M4 | 6 | 5 |
| M13 Book Recommendations | M17 Book recommendations (6) | 6 | 5 |

Why these merges:

- **M8** brings every part of background music into one module: making a
  track (upload or piano), checking that it is safe and tagging it, and
  learning which music the listener likes.
- **M9** covers the two new kinds of book the reader can play. Both change
  how a book is made and played compared with a normal linear audiobook.
- **M11** covers a user's first minutes in the app: signing up, getting the
  starter books and being shown around by the guide.

Actors: **Caregiver**, **Child**, **Independent user** (a teenager using
the app alone), **Member** (a caregiver who has joined the community).
**Gemini** and the phone's **music apps** (YouTube, YouTube Music) are
secondary actors.

## Module names

All 13 modules now have names that say what the module does. The AP1
modules keep their numbers and scope; only the names changed (M4 also lost
its adaptive settings part to M12).

| Module | Name now | Name in the AP1 report |
|---|---|---|
| M1 | Login and Guardian PIN | General Module |
| M2 | Child Profiles and Settings | Personalisation Settings Module |
| M3 | Content Library and Upload | Content Management Module |
| M4 | AI Audiobook Creation | AI Module |
| M5 | Audiobook Player and Read-along | Audio Playback Engine |
| M6 | Background Music Library | Background Music Module |
| M7 | Listening Insights | Listening Insights Module |
| M8 | Background Music Studio | (new) |
| M9 | Interactive and Al-Quran Audiobooks | (new) |
| M10 | Community Hub | (new) |
| M11 | Accounts and Onboarding | (new) |
| M12 | AI Adaptive Settings | (new) |
| M13 | Book Recommendations | (new) |

## M4 AI Audiobook Creation (was M4 AI module)

In AP1, M4 did two jobs:

1. **Making content with Gemini:** stories, illustrations and narration
   (FR7, UC-6).
2. **Adaptive settings:** Gemini analysed listening behaviour and suggested
   sensory settings (FR14, UC-10).

The second job is now its own module, M12 AI Adaptive Settings. M12 does it
with rules, learning from the caregiver's choices, and a Gemini review step
(FR50 to FR55, UC12.1 to UC12.5).

M4 now covers only AI content creation: Gemini writes the story text, draws
the illustrations and speaks the narration. Its old name, "AI module", no
longer described it, so it is now called **AI Audiobook Creation**. Its
requirements and use cases have changed as follows:

| AP1 item | Now |
|---|---|
| FR7 Gemini generates an audiobook from raw text | Refined below, and split into FR7, FR62, FR63 and FR64 |
| FR14 Gemini analyses listening and suggests sensory settings | Moved to M12, replaced by FR50 to FR55 |
| FR15 (M7) accept, edit or dismiss AI suggestions | The tips shown are now M12's, and acting on them is FR55. M7 still shows the listening insights. |
| UC-6 Generate Audiobook from Text | Refined as UC4.1 |
| UC-10 Analyse Listening Behaviour | Moved to M12 as UC12.2 View smart tips |

### Functional requirements

| ID | Requirement | Acceptance check |
|---|---|---|
| FR7 | The system shall use Gemini to write a paged, autism-friendly audiobook from a caregiver's topic or pasted text, as a normal or interactive (M9) book, using the caregiver's page count, language (English or Malay) and difficulty (Easy: 1 sentence per page, Medium: 2, Hard: 3 to 5). | Generate one book at each difficulty. Each has the chosen number of pages, the right number of sentences per page, and the chosen language. |
| FR62 | The system shall, when the caregiver asks for pictures, draw a soft, calm illustration for every page with Gemini (pastel colours, no text, nothing scary). The book stays marked as being made until all pictures are done, and page 1's picture becomes the cover. | Generate with pictures on. The book shows as being made, then every page has a picture and the cover is page 1's. |
| FR63 | The system shall turn each page's text into narration with Gemini text-to-speech in the chosen narrator voice. Each clip is saved the first time it is made, so the same text is never made twice. | Play a page twice. The second play uses the saved clip and starts without waiting for Gemini. |
| FR64 | The system shall save a generated book as private to the caregiver and let them edit, add or delete pages before a child reads it. When Gemini is not set up or story writing fails, the system shall show a clear message and save no book. | Edit a generated page, and the change shows in playback. With Gemini turned off, generating shows a message and no new book appears. |

### Use cases

| ID | Use case | Actor | What happens | FRs |
|---|---|---|---|---|
| UC4.1 | Generate an audiobook with AI | Caregiver, Gemini | Enters a topic or pastes text, picks page count, language, difficulty and format; Gemini writes the pages. Refines AP1 UC-6. | FR7, FR64 |
| UC4.2 | Add illustrations to a book | Caregiver, Gemini | Turns pictures on; Gemini draws one calm picture per page in the background and the book is ready when all are done. | FR62 |
| UC4.3 | Hear a page narrated | Child or Caregiver, Gemini | Plays a page; its narration is made in the chosen voice, or the saved clip is used. Included by AP1 UC-8 Play Audiobook. | FR63 |
| UC4.4 | Review and edit a generated book | Caregiver | Reads the generated pages, then edits, adds or deletes pages before the child reads the book. | FR64 |

## M8 Background Music Studio

### Functional requirements

| ID | Requirement | Acceptance check |
|---|---|---|
| FR28 | The system shall let a caregiver upload their own music (MP3, MP4, WAV and other common formats), convert it to MP3, and keep it private to that caregiver. | Upload a WAV and an MP4 file; both play as MP3 in the picker, and a second account cannot see them. |
| FR29 | The system shall measure each track's tempo (BPM), beat steadiness, loudness swing and any sudden jump of 10 dB or more, and flag tracks that may be a sensory risk. | Analyse a calm track and a track with a sudden loud jump; only the second is flagged. |
| FR30 | The system shall use Gemini to listen to each track twice and keep a genre only when both listens agree, otherwise mark it unsure. Emotion tags and sensory notes shall be stored with the track. | Tag a labelled track; the stored genre matches both listens, or the track is marked unsure when they disagree. |
| FR31 | The system shall, with permission, count the genres of songs played on YouTube and YouTube Music, keeping only the genre counts on the phone. | Allow access and play songs; only genre counts are stored, on the phone. Without permission, nothing is read. |
| FR32 | The system shall turn the listener's music taste into a score for each background-music genre and pass it to the book recommender (M13), so audiobooks whose music suits the listener rank higher. | With access allowed, a book whose music matches the top genre ranks higher. Without access, recommendations still appear. |
| FR33 | The system shall provide an in-app C major piano that records a melody and saves it as an MP3 file, ready to use as background music. | Record a short melody and save it; the MP3 plays back and can be chosen as background music. |

### Use cases

| ID | Use case | Actor | What happens | FRs |
|---|---|---|---|---|
| UC8.1 | Upload a music track | Caregiver | Picks an audio or video file; the system converts it to MP3 and adds it to their private music library. | FR28 |
| UC8.2 | Check a track for sensory risk | Caregiver | Opens a track; the system shows its tempo, steadiness and loudness, and warns if it has a sudden loud jump. | FR29 |
| UC8.3 | Tag a track with AI | Caregiver, Gemini | Asks for tags; Gemini listens twice and the agreed genre, emotion tags and sensory notes are saved. | FR30 |
| UC8.4 | Allow music taste tracking | Caregiver or Independent user, music apps | Grants access; the phone counts the genres of songs played and keeps only the counts. | FR31 |
| UC8.5 | Match books to music taste | Caregiver or Independent user | Opens recommendations; books whose background music suits their taste rank higher. | FR32 |
| UC8.6 | Compose a melody on the piano | Child or Caregiver | Plays and records a melody, then saves it as an MP3 that can be used as background music. | FR33 |

## M9 Interactive and Al-Quran Audiobooks

### Functional requirements

| ID | Requirement | Acceptance check |
|---|---|---|
| FR34 | The system shall allow a caregiver to create an interactive audiobook in which a page can ask a question with 2 to 4 answer choices. | Create a book with a question page; saving is refused with fewer than 2 or more than 4 choices. |
| FR35 | The system shall support two kinds of answer page after a question: a shared page that reads the child's chosen answer in place of {choice}, and a split question with a separate page for each of its 2 choices, after which the story joins back. | Play both kinds; the shared page speaks the chosen answer, and each split choice opens its own page before the story continues. |
| FR36 | The system shall let the child answer a question by tapping a choice during playback, and continue the story along that choice. | In Child Mode, tap each choice in turn; the next page always matches the choice tapped. |
| FR37 | The system shall let a caregiver download and remove individual Al-Quran chapters, showing the storage size of each chapter and of downloading all of them. | Download one chapter, check the size shown, remove it and confirm the space is freed. |
| FR38 | The system shall play a downloaded chapter without internet, one page per verse, turning the page as each verse is recited and jumping the recitation when the child swipes to another verse. | With the phone offline, play a chapter; pages follow the recitation and a swipe moves the audio to that verse. |
| FR39 | The system shall show the sources and licences of the recitation audio and images used in the pack. | Open the Al-Quran tab; the sources and licences are listed at the end. |

### Use cases

| ID | Use case | Actor | What happens | FRs |
|---|---|---|---|---|
| UC9.1 | Create an interactive audiobook | Caregiver | Writes the story, adds question pages with 2 to 4 choices, and picks a shared or split answer page for each. | FR34, FR35 |
| UC9.2 | Answer a story question | Child | Taps a choice during playback; the story carries on along that choice. | FR35, FR36 |
| UC9.3 | Download or remove Al-Quran chapters | Caregiver | Sees each chapter's size, downloads the chapters the child needs, and removes them to free space. | FR37 |
| UC9.4 | Listen to an Al-Quran chapter offline | Child | Plays a downloaded chapter with no internet; pages follow each verse, and a swipe moves the recitation. | FR38 |
| UC9.5 | View pack sources and licences | Caregiver | Opens the Al-Quran tab and reads where the audio and images come from. | FR39 |

## M10 Community Hub

### Functional requirements

| ID | Requirement | Acceptance check |
|---|---|---|
| FR40 | The system shall let a caregiver choose to join the community, and invite another family with a shareable invite code. Only signed-in members can see community content. | Join, create a code, redeem it on a second account; the two become friends. Signed-out requests to the feed are refused. |
| FR41 | The system shall let members search for other members, send, accept or decline friend requests, and remove friends. | Run each action between two test accounts and check both friend lists. |
| FR42 | The system shall let members chat one-to-one with a friend or in a group, sending text, an audiobook or both, and show the number of unread messages. | Send each message type in a direct and a group chat; the unread count rises and clears when the chat is opened. |
| FR43 | The system shall let members share an audiobook, text or both to a members-only feed, and like, react to and comment on posts. Members can delete their own posts and comments. | Post each type, react and comment from a second account, then delete them as the author. |
| FR44 | The system shall let a member save a private copy of an audiobook shared in the feed or a chat into their own library. | Save a shared book; it appears in the library, and editing the copy leaves the original unchanged. |
| FR45 | The system shall let members mark another member as a favourite, mute them or block them. Favourite chats are pinned on top, muted chats show no unread alert, and a blocked member can no longer message them and their posts are hidden. | Set each flag on a test account and check the chat list, the unread dot, messaging and the feed. |

### Use cases

| ID | Use case | Actor | What happens | FRs |
|---|---|---|---|---|
| UC10.1 | Join the community and invite a family | Caregiver | Opts in, creates an invite code and shares it; the other family redeems it and both become friends. | FR40 |
| UC10.2 | Manage friends | Member | Searches for members, sends, accepts or declines requests, and removes friends. | FR41 |
| UC10.3 | Chat with friends | Member | Sends text, an audiobook or both in a direct or group chat, and sees unread counts. | FR42 |
| UC10.4 | Post and react in the feed | Member | Shares a book or text to the feed, likes, reacts and comments, and deletes their own posts. | FR43 |
| UC10.5 | Save a shared audiobook | Member | Saves a private copy of a book from the feed or a chat into their library. | FR44 |
| UC10.6 | Favourite, mute or block a member | Member | Pins a friend's chat, silences their alerts or blocks them so they can't send messages. | FR45 |

## M11 Accounts and Onboarding

### Functional requirements

| ID | Requirement | Acceptance check |
|---|---|---|
| FR46 | The system shall offer two account types at sign-up: a caregiver account with child profiles and Child Mode, and an independent account for a teenager who uses the app alone, with all features in one taskbar and no Child Mode. | Register one of each; the independent account opens straight to its own taskbar with no PIN switch. |
| FR47 | The system shall give every new account its own copy of six starter audiobooks (three normal, three interactive), so the library is never empty. | Register a new account; six books are in the library, and deleting one does not affect other accounts. |
| FR48 | The system shall show a first-run tour led by the Paige mascot for each account type (caregiver, child, independent) and on the upload screen, pointing out each part of the screen. | Sign in with a fresh account of each type; the tour starts once and highlights each tab. |
| FR49 | The system shall move hands-on tour steps on by themselves when the user does the action (for example picking a mood, playing a note or recording), and let the user skip the tour or replay it later. | During the child tour, pick a mood and play a note; each step advances without tapping Next. Skip, then replay from the mascot. |

### Use cases

| ID | Use case | Actor | What happens | FRs |
|---|---|---|---|---|
| UC11.1 | Register a caregiver account | Caregiver | Signs up as a caregiver, adds child profiles, and finds six starter books in the library. | FR46, FR47 |
| UC11.2 | Register an independent account | Independent user | Signs up alone, lands on their own taskbar with no Child Mode, and finds six starter books. | FR46, FR47 |
| UC11.3 | Take the first-run tour | Caregiver, Child or Independent user | Paige points out each part of the screen; hands-on steps move on when the user does the action. | FR48, FR49 |
| UC11.4 | Follow the upload guide | Caregiver or Independent user | On first opening the upload screen, Paige walks through making a book. | FR48 |
| UC11.5 | Skip or replay the tour | Caregiver, Child or Independent user | Skips the tour, then replays it later from the mascot. | FR49 |

## M12 AI Adaptive Settings (smart tips)

This is the adaptive settings part of AP1's M4 AI module (FR14, UC-10),
taken out and rebuilt as its own module.

### Functional requirements

| ID | Requirement | Acceptance check |
|---|---|---|
| FR50 | The system shall record, for each listening session, the pages reached, the times the child went back a page, pauses, Next taps, and any reading speed, text size or narrator voice the child changed during the book. | Read a book, go back one page and change the speed; the saved session shows the back count and the new speed. |
| FR51 | The system shall find setting tips with rules over the child's last 30 days of listening, counting recent sessions more (7-day half-life), and give each tip a strength and a short reason in English and Malay. | Unit tests: lots of going back and pausing gives a slower reading speed tip, and a child who keeps making the words bigger gets a text size tip. |
| FR52 | The system shall learn which kinds of tips work, for each child and across all families, from the caregiver's choice (apply, edit or skip) and from whether listening got better after 3 more sessions, and rank the tips by it (Thompson sampling). | Skip one kind of tip several times; it stops appearing. Apply a tip and add 3 better sessions; it is counted as helped. |
| FR53 | The system shall send the ranked shortlist to Gemini, which picks at most 3 tips and rewrites their reasons in simple words. Only listening numbers, current settings and the child's age are sent, never names. | With Gemini on, at most 3 tips are shown with simple reasons. |
| FR54 | The system shall not let Gemini add tips or change suggested values, and shall still show the learned tips when Gemini is off or fails. | Turn Gemini off; tips still appear in the learned order. A tip id that Gemini makes up is ignored. |
| FR55 | The system shall let the caregiver apply, edit or skip each tip, and show each tip's reason and how often that kind of tip helped before. No setting shall change without the caregiver's action. | Skip a tip; the child's settings stay the same. Apply one; only that setting changes. Each tip shows its reason and a "helped" count. |

### Use cases

| ID | Use case | Actor | What happens | FRs |
|---|---|---|---|---|
| UC12.1 | Listen to a book (session recorded) | Child | Reads a book as usual; pages, going back, pauses and setting changes are saved for that session. | FR50 |
| UC12.2 | View smart tips | Caregiver, Gemini | Opens the child's tips; the system ranks them, Gemini picks up to 3 and simplifies the reasons, or the learned list shows if Gemini is off. | FR51, FR52, FR53, FR54 |
| UC12.3 | Apply a tip | Caregiver | Applies a tip; only that one setting changes for the child. | FR55 |
| UC12.4 | Edit or skip a tip | Caregiver | Changes a tip's value before applying it, or skips it; the choice teaches the system which tips to show next. | FR52, FR55 |
| UC12.5 | See whether tips helped | Caregiver | Reads each tip's reason and how often that kind of tip helped after 3 more sessions. | FR52, FR55 |

## M13 Book Recommendations

### Functional requirements

| ID | Requirement | Acceptance check |
|---|---|---|
| FR56 | The system shall rate each book a child has read from how it was read in the last 90 days: finished counts as liked, stopping early as not liked, and re-reading as a strong like. | Finish one book and stop another early; the first is rated higher. |
| FR57 | The system shall suggest books similar to the ones the child liked, by category, topic, tags, level, language and background music (content-based filtering with TF-IDF). | Unit test: a child who likes one topic gets another book on that topic first, and books like ones they stopped early rank lower. |
| FR58 | The system shall suggest books that children with the same taste liked (item-item collaborative filtering), using listening from all families without showing other children's details. | Unit test: when two children who read book A also liked book B, a child who liked A gets B suggested. |
| FR59 | The system shall give a new child with no history popular books that fit today's mood, and rely more on the child's own taste as their history grows. | A new child's list is not empty and its picks fit the chosen mood. |
| FR60 | The system shall adjust picks for today's mood, a difficulty just right for the child, their age and, if allowed, their music taste (FR32). It shall keep the list varied (MMR), move books just finished down, and leave out books still being made. | Finish a book; it moves down the list. The top 3 are not all the same kind. Unit tests for mood, difficulty and music taste pass. |
| FR61 | The system shall recommend only from the family's own library and only for their own children, and show one short reason with each pick, on the Insights page and as Today's pick on the child's home. | Each pick shows a reason. Asking for another family's child is refused. |

### Use cases

| ID | Use case | Actor | What happens | FRs |
|---|---|---|---|---|
| UC13.1 | Finish or stop a book | Child | Reads a book to the end, stops early or reads it again; the system rates the book from this. | FR56 |
| UC13.2 | View recommended books | Caregiver | Opens Insights and sees a varied list of picks, each with a short reason. | FR57, FR58, FR60, FR61 |
| UC13.3 | Open Today's pick | Child | Sees one suggested book on their home screen and starts it. | FR60, FR61 |
| UC13.4 | Choose today's mood | Child | Picks a mood; the suggested books change to fit it. | FR59, FR60 |
| UC13.5 | Get picks for a new child | Caregiver | Adds a child with no history and still sees popular books that fit the mood. | FR59 |

## Traceability

| Module | Requirements | Use cases | Built by |
|---|---|---|---|
| M4 AI Audiobook Creation (was AI module) | FR7, FR62 to FR64 | UC4.1 to UC4.4 | AP1 module (adaptive settings moved to M12) |
| M8 Background Music Studio | FR28 to FR33 | UC8.1 to UC8.6 | Tiew Yi Xu |
| M9 Interactive and Al-Quran Audiobooks | FR34 to FR39 | UC9.1 to UC9.5 | Tiew Yi Xu |
| M10 Community Hub | FR40 to FR44 / FR45 | UC10.1 to UC10.5 / UC10.6 | Soh Chang Zheng / Tiew Yi Xu |
| M11 Accounts and Onboarding | FR46, FR48, FR49 / FR47 | UC11.1 to UC11.5 | Soh Chang Zheng / Tiew Yi Xu |
| M12 AI Adaptive Settings (smart tips) | FR50 to FR55 | UC12.1 to UC12.5 | Soh Chang Zheng |
| M13 Book Recommendations | FR56 to FR61 | UC13.1 to UC13.5 | Soh Chang Zheng |

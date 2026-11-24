# New functional requirements FR34 to FR49

These cover the five modules added after AP1 that had no functional
requirement yet (M11 to M15). FR28 to FR33 already cover the music modules
(M8 to M10). Each requirement has an acceptance check so it can be tested.

## M11 Interactive branching audiobooks

| ID | Requirement | Acceptance check |
|---|---|---|
| FR34 | The system shall allow a caregiver to create an interactive audiobook in which a page can ask a question with 2 to 4 answer choices. | Create a book with a question page; saving is refused with fewer than 2 or more than 4 choices. |
| FR35 | The system shall support two kinds of answer page after a question: a shared page that reads the child's chosen answer in place of {choice}, and a split question with a separate page for each of its 2 choices, after which the story joins back. | Play both kinds; the shared page speaks the chosen answer, and each split choice opens its own page before the story continues. |
| FR36 | The system shall let the child answer a question by tapping a choice during playback, and continue the story along that choice. | In Child Mode, tap each choice in turn; the next page always matches the choice tapped. |

## M12 Al-Quran audio pack

| ID | Requirement | Acceptance check |
|---|---|---|
| FR37 | The system shall let a caregiver download and remove individual Al-Quran chapters, showing the storage size of each chapter and of downloading all of them. | Download one chapter, check the size shown, remove it and confirm the space is freed. |
| FR38 | The system shall play a downloaded chapter without internet, one page per verse, turning the page as each verse is recited and jumping the recitation when the child swipes to another verse. | With the phone offline, play a chapter; pages follow the recitation and a swipe moves the audio to that verse. |
| FR39 | The system shall show the sources and licences of the recitation audio and images used in the pack. | Open the Al-Quran tab; the sources and licences are listed at the end. |

## M13 Community hub

| ID | Requirement | Acceptance check |
|---|---|---|
| FR40 | The system shall let a caregiver choose to join the community, and invite another family with a shareable invite code. Only signed-in members can see community content. | Join, create a code, redeem it on a second account; the two become friends. Signed-out requests to the feed are refused. |
| FR41 | The system shall let members search for other members, send, accept or decline friend requests, and remove friends. | Run each action between two test accounts and check both friend lists. |
| FR42 | The system shall let members chat one-to-one with a friend or in a group, sending text, an audiobook or both, and show the number of unread messages. | Send each message type in a direct and a group chat; the unread count rises and clears when the chat is opened. |
| FR43 | The system shall let members share an audiobook, text or both to a members-only feed, and like, react to and comment on posts. Members can delete their own posts and comments. | Post each type, react and comment from a second account, then delete them as the author. |
| FR44 | The system shall let a member save a private copy of an audiobook shared in the feed or a chat into their own library. | Save a shared book; it appears in the library, and editing the copy leaves the original unchanged. |
| FR45 | The system shall let members mark another member as a favourite, mute them or block them. Favourite chats are pinned on top, muted chats show no unread alert, and a blocked member can no longer message them and their posts are hidden. | Set each flag on a test account and check the chat list, the unread dot, messaging and the feed. |

## M14 Personal accounts and starter library

| ID | Requirement | Acceptance check |
|---|---|---|
| FR46 | The system shall offer two account types at sign-up: a caregiver account with child profiles and Child Mode, and an independent account for a teenager who uses the app alone, with all features in one taskbar and no Child Mode. | Register one of each; the independent account opens straight to its own taskbar with no PIN switch. |
| FR47 | The system shall give every new account its own copy of six starter audiobooks (three normal, three interactive), so the library is never empty. | Register a new account; six books are in the library, and deleting one does not affect other accounts. |

## M15 Interactive guide

| ID | Requirement | Acceptance check |
|---|---|---|
| FR48 | The system shall show a first-run tour led by the Paige mascot for each account type (caregiver, child, independent) and on the upload screen, pointing out each part of the screen. | Sign in with a fresh account of each type; the tour starts once and highlights each tab. |
| FR49 | The system shall move hands-on tour steps on by themselves when the user does the action (for example picking a mood, playing a note or recording), and let the user skip the tour or replay it later. | During the child tour, pick a mood and play a note; each step advances without tapping Next. Skip, then replay from the mascot. |

## Traceability

| Module | Requirements |
|---|---|
| M8 Music intelligence | FR28, FR29, FR30 |
| M9 Music taste and recommendations | FR31, FR32 |
| M10 Piano composer | FR33 |
| M11 Interactive branching audiobooks | FR34 to FR36 |
| M12 Al-Quran audio pack | FR37 to FR39 |
| M13 Community hub | FR40 to FR45 |
| M14 Personal accounts and starter library | FR46, FR47 |
| M15 Interactive guide | FR48, FR49 |

# Codebase Guide — Audiobook for Autism

A deep, beginner-friendly tour of the whole project: what each folder does, the
layers a request passes through, and three complete "follow the code" walkthroughs
that go from a button tap on the phone all the way to the database and back.

**How to use this document**
1. Read **§1 Big Picture** and **§2 The Two Mental Models** once.
2. Read **§3 The Request Lifecycle** — this is the backbone everything hangs on.
3. Do **§4 Three Walkthroughs** with the files open beside you.
4. Keep **§5 Frontend folders** and **§6 Backend folders** as reference.
5. Use **§7 Reading order** and **§8 cheat sheet** day-to-day.

---

## 1. The Big Picture

The project is **two separate programs** that talk over the internet:

```
┌──────────────────────────┐        HTTP request (JSON)       ┌──────────────────────────┐
│   frontend/  (Flutter)   │  ──────────────────────────────► │   backend/  (Laravel)    │
│   the app on the phone   │                                  │   server + MySQL database │
│   draws screens,         │  ◄────────────────────────────── │   stores data, checks     │
│   plays audio, sends      │        JSON reply                │   logins, calls Gemini AI │
│   requests                │                                  │                           │
└──────────────────────────┘                                  └──────────────────────────┘
        Dart language                                                 PHP language
```

- **frontend/** — the Flutter app. Everything the user sees and taps. Written in Dart.
- **backend/** — the Laravel server. Holds the database, checks who is allowed in,
  and calls Google Gemini for AI stories, pictures, and voices. Written in PHP.

They never share memory or code. They only meet at **HTTP**: the app sends a request
to a URL like `POST /api/auth/login`, the server runs some PHP, and sends back JSON
like `{ "status": "SUCCESS", "data": { ... } }`. **Understand that one seam and the
whole system makes sense.**

Two kinds of user:
- **Caregiver** (parent / teacher) — logs in with a 4-digit PIN, manages children,
  uploads or AI-generates books, views insights.
- **Child** — uses a simple "Child Mode" (no login) to pick a mood and listen.

---

## 2. The Two Mental Models

Before tracing code, hold these two pictures in your head.

### 2a. The frontend is a stack of layers

A tap travels **down** through these layers, and data comes back **up**:

```
   ┌─ pages/      WHAT YOU SEE     — screens & buttons (Widgets)
   │      │  calls
   ▼      ▼
   ┌─ state/      WHAT'S REMEMBERED — login, profiles, settings (live in memory)
   │      │  calls
   ▼      ▼
   ┌─ services/   HOW WE TALK       — builds the HTTP request, sends it
   │      │  returns
   ▼      ▼
   ┌─ models/     THE SHAPE OF DATA — turns JSON text into Dart objects
   └──────────────────────────────────────────────────────────────────
   (audio/, theme/, i18n/, widgets/, navigation/, config/ are helpers used by any layer)
```

- **pages/** never builds HTTP itself — it asks **state/** or **services/**.
- **services/** is the *only* place that knows the server exists.
- **models/** is the translator both sides agree on.

### 2b. The backend is also a stack of layers

Every request enters at the top and flows down:

```
   routes/api.php         THE MAP        — "this URL → that controller method"
        │
        ▼
   Middleware             THE GUARD      — SessionAuthMiddleware checks the login token
        │
        ▼
   Controllers/Api/       THE LOGIC      — validate input, do the work, return JSON
        │           │
        ▼           ▼
   Models/        Services/              — Models = database tables; Services = Gemini AI
        │
        ▼
   database (MySQL)       THE STORAGE    — the actual saved rows
```

---

## 3. The Request Lifecycle (the backbone)

Here is the **exact journey of every single request**, with the file that owns each
step. Memorise this and you can place any line of code in the system.

```
 PHONE (frontend/)                          SERVER (backend/)
 ─────────────────                          ─────────────────
 1. User taps a widget
    pages/.../some_page.dart
        │
 2. Page calls a state or service method
    state/..._state.dart  OR
    services/database_service.dart
        │
 3. database_service builds + sends HTTP
    services/database_service.dart  ._post(...)
        │   POST https://host/api/<path>   (JSON body, Bearer token header)
        └──────────────────────────────────────►
                                            4. Laravel matches the URL
                                               routes/api.php
                                                   │
                                            5. Auth check runs first
                                               Http/Middleware/SessionAuthMiddleware.php
                                                   │  (valid token? attach the caregiver)
                                            6. Controller method runs
                                               Http/Controllers/Api/XxxController.php
                                                   │  - validate the input
                                                   │  - read/write the database via Models/
                                                   │  - (maybe) call Services/GeminiService
                                                   │  - build the JSON envelope
                                            7. Reads/writes a table
                                               Models/Xxx.php  ↔  MySQL
                                                   │
        ◄──────────────────────────────────────┘
        │   { "status": "SUCCESS", "data": {...} }
 8. database_service wraps the reply
    services/api_service.dart  (ApiResponse)
        │
 9. JSON becomes a Dart object
    models/xxx.dart  (Xxx.fromJson)
        │
10. State updates, screen rebuilds
    state/..._state.dart  →  pages/.../some_page.dart
```

**The standard reply shape** (every endpoint returns this — defined in
`backend/app/Http/Controllers/Api/ApiController.php`):

```jsonc
{ "status": "SUCCESS",          // or "ERROR"
  "message": "Login successful",
  "data": { ... },               // the useful payload (may be absent)
  "error_code": "INVALID_PIN",   // only on errors
  "timestamp": "2026-06-13 10:30:00" }
```

---

## 4. Three Walkthroughs (follow these with files open)

### Walkthrough A — Caregiver logs in (the simplest full loop)

```
1. SCREEN          frontend/lib/pages/shared/login_page.dart
   The caregiver types a PIN and taps "Sign in". _submit() runs and calls:
        context.read<AuthState>().login(pin: ..., email: ...)

2. STATE           frontend/lib/state/auth_state.dart
   login() forwards to the network layer:
        DatabaseService.loginWithPin(pin: ..., email: ...)

3. NETWORK         frontend/lib/services/database_service.dart   → loginWithPin()
   Builds the request and POSTs it:
        POST /api/auth/login   body: { "pin": "1234", "email": "..." }
   On success it also saves the returned session token to the phone
   (_persistSession → SharedPreferences) so future requests are logged in.

   ───────── crosses the internet ─────────

4. MAP             backend/routes/api.php
        Route::post('/auth/login', [AuthController::class, 'loginWithPin']);
   (Login is PUBLIC — it is NOT inside the session.auth group, because you
   don't have a token yet.)

5. LOGIC           backend/app/Http/Controllers/Api/AuthController.php → loginWithPin()
   - Validates the PIN format.
   - Finds the matching Caregiver and checks the PIN.
   - Creates a session token, returns it + the caregiver info as JSON.

6. DATA            backend/app/Models/Caregiver.php
   Represents the `caregivers` table; verifyPin() checks the hashed PIN.

   ───────── reply crosses back ─────────

7. WRAP            frontend/lib/services/api_service.dart   (ApiResponse)
   Standardises the reply into success/data/message.

8. OBJECT          frontend/lib/models/caregiver.dart   (Caregiver.fromJson)
   Turns the JSON into a Caregiver object.

9. UI UPDATES      AuthState sets status = signedIn and notifies listeners.
   frontend/lib/pages/shared/auth_gate.dart is watching AuthState — it now
   shows CaregiverShell (the main app) instead of LoginPage.
```

### Walkthrough B — Child listens to a story (read this to learn the player)

```
1. LIST            frontend/lib/pages/child/story_library_page.dart
   Child taps a book → pushes AudioPlayerPage with the book's id.

2. PLAYER          frontend/lib/pages/child/audio_player_page.dart
   initState() → _loadAudiobook() asks for the full book:
        DatabaseService.getAudiobookData(id)

3. NETWORK         frontend/lib/services/database_service.dart  → getAudiobookData()
        POST /api/audiobooks/{id}

4. GUARD           backend/app/Http/Middleware/SessionAuthMiddleware.php
   Checks the Bearer token (this route IS protected). If the token is near
   expiry it quietly extends it ("sliding expiry").

5. LOGIC           backend/app/Http/Controllers/Api/AudiobookController.php
        getAudiobookData() loads the book + its pages, builds absolute URLs
        for images/audio (mediaUrl), returns JSON.

6. DATA            backend/app/Models/Audiobook.php  +  AudiobookPage.php
   A book HAS MANY pages.

7. OBJECT          frontend/lib/models/audiobook.dart   (Audiobook.fromJson)
   The player now holds the pages, image URLs, and audio URL.

8. PLAYBACK        frontend/lib/audio/audio_engine.dart
   When the child taps Listen, the player either:
     • plays the caregiver's uploaded recording, OR
     • asks Gemini to speak the page (TtsController) — see Walkthrough notes.
   It also drives the read-along word highlighting and auto page-flip.

9. SAVE THE SESSION  When the child leaves, the player reports what happened:
   DatabaseService.recordListeningSession(...) →
   POST /api/listening-history/record →
   backend ListeningHistoryController → ListeningHistory model →
   listening_history table  (duration, mood, pauses, skips).
```

### Walkthrough C — Caregiver generates a book with AI (the most complex path)

```
1. SCREEN          frontend/lib/pages/caregiver/upload_content_page.dart
   Caregiver types a topic, picks page count + language, taps "Generate".

2. NETWORK         frontend/lib/services/database_service.dart
        POST /api/content/generate   body: { topic, page_count, language, ... }

3. LOGIC           backend/app/Http/Controllers/Api/ContentManagementController.php
        generateContent():
          a. Calls GeminiService.generateStory(...) → gets title + pages text.
          b. Saves the Audiobook with status = "processing".
          c. Dispatches a background job to draw the pictures.

4. AI              backend/app/Services/GeminiService.php
        generateStory()  → Gemini writes the story (text).
        downloadImage()  → Gemini draws each page's picture (slow, ~12s each).

5. BACKGROUND      backend/app/Jobs/GenerateAudiobookImages.php
   Draws every page image one by one, then flips the book to "available".
   (This is why a new book first shows a "Generating…" badge.)

6. POLLING         frontend/lib/pages/caregiver/content_management_page.dart
   While any book is "processing", the list quietly re-checks every few
   seconds (calls /api/content/list) until the pictures are done, then the
   book appears finished — no manual refresh needed.
```

> **The AI suggestions feature** (Insights tab) follows the same shape:
> `insights_page.dart` → `database_service.analyseListening()` →
> `/api/insights/{child}/analyse` → `InsightsController.analyse()` →
> `GeminiService.analyseListening()` → saved in the `AiSuggestion` model.

---

## 5. Frontend folders (`frontend/lib/`) — detailed

> Mental model reminder: **pages → state → services → models**, with
> audio/theme/i18n/widgets/navigation/config as shared helpers.

### `main.dart` — the ignition
The first code that runs. It:
1. Sets up the global image cache size.
2. Registers the four global **state** objects (`LanguageState`, `AuthState`,
   `ProfilesState`, `SettingsState`) with `MultiProvider` so any screen can read them.
3. Builds the `MaterialApp` and shows `AuthGate` as the first screen.

### `config/` — the address book
One file, `app_config.dart`: the backend URL the app talks to (e.g. an emulator uses
`10.0.2.2:8000`, a real phone uses the PC's Wi-Fi IP). **If the app can't reach the
server, check here first.**

### `pages/` — every screen (the biggest folder)
Each file is one screen (a Flutter "Widget"). Grouped by who uses it:

```
pages/
├── shared/   before we know the user
│   ├── auth_gate.dart           watches AuthState → shows LoginPage or the app.
│   │                            Also refreshes profiles on sign-in.
│   ├── login_page.dart          PIN sign-in / register.
│   └── guardian_pin_dialog.dart the PIN popup that guards leaving Child Mode.
│
├── caregiver/   the parent/teacher side (5 tabs + dialogs)
│   ├── caregiver_shell.dart         the bottom tab bar holding the 5 tabs.
│   ├── caregiver_dashboard_page.dart  Home tab: totals + child cards + logout.
│   ├── profiles_page.dart           list children; add / edit / remove.
│   ├── add_child_dialog.dart        the popup to add OR edit a child.
│   ├── child_profile_actions.dart   shared edit/delete buttons + confirm dialogs.
│   ├── content_management_page.dart  the library: list / search / filter / edit / delete.
│   ├── upload_content_page.dart     upload a book OR generate one with AI (big file).
│   ├── edit_content_page.dart       edit a book's details and each page.
│   ├── insights_page.dart           charts + AI suggestions (big file).
│   └── settings_page.dart           per-child narration & sensory settings.
│
└── child/   the calm, simple child side (3 tabs)
    ├── child_shell.dart         bottom nav: Home / Library / Exit.
    ├── child_home_page.dart     mood picker + "Today's pick" button.
    ├── story_library_page.dart  browse stories.
    └── audio_player_page.dart   THE PLAYER: pages, read-along, controls (biggest file).
```

### `state/` — the app's live memory (the `provider` pattern)
These objects stay alive while the app runs and hold shared data. When their data
changes they call `notifyListeners()`, and any screen watching them rebuilds.

| File | Remembers |
|---|---|
| `auth_state.dart` | Who is logged in; sign-in / sign-out. |
| `profiles_state.dart` | The caregiver's children, the active child, today's mood. |
| `settings_state.dart` | The settings for the child being configured / in Child Mode. |
| `language_state.dart` | The chosen language (English / Bahasa Malaysia). |

> **Why this matters:** a screen reads state with `context.watch<AuthState>()`
> (rebuild when it changes) or `context.read<AuthState>()` (just call a method).

### `services/` — the only door to the backend
| File | Job |
|---|---|
| `database_service.dart` | **Every** network call lives here. One static method per endpoint (`loginWithPin`, `getAudiobookData`, `generateContent`, …). The private `_post()` adds the token, sends JSON, and handles errors. |
| `api_service.dart` | The `ApiResponse` wrapper — a tidy `{ success, message, data }` so callers don't parse raw JSON. |

> **Rule:** if you add a new backend endpoint, you add a matching method here, and
> nowhere else in the app should call `http` directly.

### `models/` — the shape of the data
Plain Dart classes that mirror the backend's JSON. Each has a `fromJson()` that reads
a `Map` into typed fields (and sometimes `toJson()` to send data back).

| File | Represents |
|---|---|
| `caregiver.dart` | The logged-in caregiver. |
| `child_profile.dart` | A child. |
| `user_settings.dart` | Narration / sensory settings. |
| `audiobook.dart` | A book **and** its pages (`AudiobookPage`). |
| `content_item.dart` | A book as shown in the caregiver's library list. |
| `content_summary.dart` | The counts on the Content tab (totals). |
| `insights_overview.dart` | Everything the Insights charts need. |
| `ai_suggestion.dart` | The AI tips for a child (and each tip item). |
| `music_track.dart` | A background-music track. |
| `_json_helpers.dart` | Small safe-parsing helpers used by all the others. |

### Shared helpers (used by any layer)
| Folder | Job |
|---|---|
| `audio/` | `audio_engine.dart` wraps the `just_audio` package to play sound. |
| `widgets/` | Small reusable UI pieces: `soft_card`, `soft_chip`, `stat_card`, `back_pill`, `app_snackbar`, `empty_state`, `bgm_picker_sheet`. |
| `theme/` | `app_colors.dart` (the palette) and `app_theme.dart` (overall look). |
| `i18n/` | `app_strings.dart` (all EN + MS text) and `i18n.dart` (the `context.tr('key')` helper). |
| `navigation/` | `app_routes.dart` (route names) and `app_navigation_service.dart` (navigate from anywhere). |

---

## 6. Backend folders (`backend/`) — detailed

Laravel has a fixed layout. You mostly care about **routes, controllers, models,
services, jobs, migrations**. Everything else is framework plumbing.

### `routes/api.php` — the map (start here when reading the backend)
Lists every URL and which controller method handles it. Two groups:
- **Public** (no login): `/auth/register`, `/auth/login`, `/test`.
- **Protected** (inside `Route::middleware('session.auth')`): everything else —
  profiles, settings, content, audiobooks, history, insights, tts, music.

Reading this file top to bottom gives you the whole feature list in ~5 minutes.

### `app/Http/Controllers/Api/` — the logic (where the work happens)
One controller per feature area. Each method follows the same recipe:
**validate input → do the work (DB and/or AI) → return the JSON envelope.**

| Controller | Handles |
|---|---|
| `ApiController.php` | Base class. Shared `successResponse()` / `errorResponse()` + logging. Every controller extends it. |
| `AuthController.php` | Register, login, logout, "who am I" (me), verify PIN. |
| `ChildProfileController.php` | Create / list / update / delete children **and** their per-child settings. |
| `SettingsController.php` | The caregiver account's own settings + change PIN. |
| `ContentManagementController.php` | The library: list, summary, upload, **AI-generate**, edit, delete, and per-page add/update/delete. |
| `AudiobookController.php` | Fetch one full book (pages + media URLs) for the player. |
| `ListeningHistoryController.php` | Save a finished listening session; list a child's history. |
| `InsightsController.php` | The charts **and** AI suggestions (analyse / accept / dismiss). |
| `TtsController.php` | Turn a page of text into a spoken clip via Gemini. |
| `MusicTrackController.php` | List / filter the background-music tracks. |

### `app/Http/Middleware/` — the guard
`SessionAuthMiddleware.php` runs **before** every protected controller. It reads the
`Authorization: Bearer <token>` header, finds the matching caregiver, rejects the
request if the token is missing/expired, and extends a near-expiry token. It also
attaches the caregiver to the request so controllers know who is calling.

### `app/Models/` — one class per database table
Each model defines its fields and its links to other tables (relationships). This is
where "a caregiver has many children" is expressed in code.

| Model | Table |
|---|---|
| `Caregiver` | `caregivers` |
| `ChildProfile` | `child_profiles` |
| `CaregiverSettings` | `caregiver_settings` |
| `ChildSettings` | `child_settings` |
| `Audiobook` | `audiobooks` |
| `AudiobookPage` | `audiobook_pages` |
| `ListeningHistory` | `listening_history` |
| `AiSuggestion` | `ai_suggestions` |
| `MusicTrack` | `music_tracks` |

### `app/Services/` — outside-world work
`GeminiService.php` is the single place that calls Google Gemini:
- `generateStory()` — writes the story text.
- `downloadImage()` — draws a page picture.
- `generateSpeech()` — makes a voice clip (cached so the same text isn't redone).
- `analyseListening()` — turns a child's stats into setting suggestions.

Keeping all AI here means the rest of the backend doesn't need to know how Gemini works.

### `app/Jobs/` — background work
`GenerateAudiobookImages.php` runs *after* a request returns, so the caregiver isn't
left staring at a frozen screen for a minute while pictures are drawn. It marks the
book "available" when all pages have images.

### `database/migrations/` — the database blueprint
Each file creates or changes one table. Run with `php artisan migrate`. Read these to
learn exactly what columns exist. (Files named `create_cache_table` /
`create_jobs_table` are standard Laravel — you can ignore them.)

### `config/` and `storage/`
- `config/` — settings. `services.php` holds the Gemini API key reference; `database.php`
  the DB connection.
- `storage/` — uploaded files, generated images, cached voices, and the **log file**
  at `storage/logs/laravel.log` (every `logEvent` line lands here — your best
  debugging window into what the server did).

---

## 7. The Database in One Picture

```
caregivers ─────┬───────────────► child_profiles ──┬──► child_settings
   │            │                                   ├──► listening_history ──► audiobooks
   └──► caregiver_settings                          └──► ai_suggestions          │
                                                                       audiobook_pages
   music_tracks   (stand-alone; an audiobook may point to one for background music)
```

"A caregiver **has many** children. A child **has** settings, history, and AI tips.
A book **has many** pages." Deleting a caregiver auto-deletes everything beneath it
(`cascadeOnDelete` in the migrations).

---

## 8. Suggested Reading Order (first day)

1. This guide → then `README.md` (how to run it).
2. `frontend/lib/main.dart` — watch the app boot.
3. `frontend/lib/pages/shared/auth_gate.dart` — the login-vs-app switch.
4. `backend/routes/api.php` — skim every endpoint (the whole feature map).
5. **Do Walkthrough A (login)** with files open — it's the shortest full loop.
6. Then Walkthrough B (player) and C (AI generate).
7. Only now open the big files (`audio_player_page`, `upload_content_page`,
   `insights_page`) — and **jump to methods**, don't read top to bottom.

---

## 9. "Where do I change…?" cheat sheet

| I want to… | Go to |
|---|---|
| Change a button label / any text | `frontend/lib/i18n/app_strings.dart` |
| Change a colour | `frontend/lib/theme/app_colors.dart` |
| Change how a screen looks/behaves | the matching file in `frontend/lib/pages/…` |
| Add / change a network call (phone) | `frontend/lib/services/database_service.dart` |
| Add / change an endpoint (server) | `backend/routes/api.php` + the controller |
| Change what fields a thing has | the `models/` file (both sides) + a migration (backend) |
| Change an AI prompt | `backend/app/Services/GeminiService.php` |
| See what the server is doing | `backend/storage/logs/laravel.log` |
| Change the server address the app uses | `frontend/lib/config/app_config.dart` |
| Change who is allowed past login | `backend/app/Http/Middleware/SessionAuthMiddleware.php` |

---

## 10. One-line glossary

- **Widget** — a piece of UI in Flutter (a screen, a button, a card).
- **Provider / state** — an object that holds shared data and tells screens to refresh.
- **Endpoint** — one server URL + method (e.g. `POST /api/auth/login`).
- **Controller** — the PHP method that handles one endpoint.
- **Model** — a class that maps to one database table.
- **Migration** — a file that builds/changes a database table.
- **Middleware** — code that runs before a controller (here: the login check).
- **Serialize / fromJson** — turning data into JSON text and back into objects.
- **Token** — the secret string that proves a caregiver is logged in.
```

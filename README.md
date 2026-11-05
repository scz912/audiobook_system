# Audiobook for Autism

An autism-friendly audiobook system for children, with a separate caregiver dashboard for content management, profiles, and listening insights. Built as a Flutter mobile app backed by a Laravel REST API.

The child-side experience focuses on **calm pacing, predictable navigation, and a real storybook feel** — pages with embedded illustrations, gentle book-flip transitions, and synchronised word highlighting that follows the narrator's voice so the child can read along.

The system supports **English and Bahasa Malaysia** for both the UI and AI-generated story content, and uses Google's **Gemini API** for AI-narrated voices, AI-generated stories with illustrations, and (optionally) for analysing listening behaviour.

---

## Table of Contents

1. [Highlights](#highlights)
2. [Architecture](#architecture)
3. [Modules](#modules)
4. [Tech Stack](#tech-stack)
5. [Project Structure](#project-structure)
6. [Prerequisites](#prerequisites)
7. [Backend Setup (Laravel)](#backend-setup-laravel)
8. [Frontend Setup (Flutter)](#frontend-setup-flutter)
9. [Testing on a Physical Phone](#testing-on-a-physical-phone)
10. [Building a Release APK](#building-a-release-apk)
11. [Database Schema](#database-schema)
12. [REST API Reference](#rest-api-reference)
13. [In-App User Flow](#in-app-user-flow)
14. [Troubleshooting](#troubleshooting)
15. [Academic Context](#academic-context)

---

## Highlights

- **Two user modes in one app** — a calm child mode and a full caregiver dashboard, gated by a 4-digit Guardian PIN.
- **Storybook reading experience** — sentence-based pagination, embedded illustration per page, 3-D book-flip transitions with a spine-side shadow (and a reduced-motion fallback), plus a yellow word-by-word highlight box while the narrator speaks.
- **Three playback paths** —
  - Gemini AI narration (server-rendered, cached per page), the default for AI-generated and text-only books;
  - A caregiver's own whole-book audio recording, with a **page-boundary marking editor** at upload time so the storybook auto-flips along with the recording;
  - Pre-recorded MP3 / WAV files attached at upload.
- **Five Gemini narrator voices** — Calm Female (Kore), Gentle Female (Leda), Warm Male (Orus), Friendly Child (Puck), Soothing Elder (Charon).
- **Bilingual UI + AI stories** — English / Bahasa Malaysia toggle in caregiver Settings; AI-generated stories are written in the chosen language; Gemini TTS speaks both natively.
- **Per-child sensory settings** — narrator voice, reading speed, volume, **text size**, reduced animations, auto-play, read-along; configured separately per child via a child selector in the Settings tab.
- **AI-generated audiobooks** — caregiver types a topic; Gemini generates a sensory-friendly story split into 4–6 short pages with a one-line illustration prompt per page; illustrations rendered via `gemini-2.5-flash-image` (downscaled to ≤ 768² JPEG on save).
- **Caregiver insights** — overall + per-child scope chip, six stat cards (total minutes, sessions, completion %, top mood, avg session length, current daily streak), last-7-days bar chart, mood breakdown, top stories, last-10-sessions activity feed.
- **UUID-first data model** — every business entity uses a 36-character UUID primary key, with `ON DELETE CASCADE` keeping the family tree consistent.
- **Autism-friendly UI primitives** — large touch targets, soft pastel palette, themed `AppSnackbar`, reduced-animation and read-along switches.

---

## Architecture

```
   ┌───────────────────────────────┐               ┌──────────────────────────────┐
   │  Flutter app (frontend/)      │   HTTPS/HTTP  │  Laravel API (backend/)      │
   │                               │  ──────────►  │                              │
   │  • Provider state             │     JSON      │  • Session middleware        │
   │  • Named routes + nav service │  ◄──────────  │  • UUID Eloquent models      │
   │  • just_audio + audio_session │   Bearer tkn  │  • MySQL (XAMPP)             │
   │  • Bilingual i18n (en / ms)   │               │  • GeminiService client      │
   └───────────────────────────────┘               └────────────┬─────────────────┘
                                                                │
                                                                ▼
                                                   ┌──────────────────────────────┐
                                                   │  Google Gemini API           │
                                                   │  • gemini-2.5-flash (text)   │
                                                   │  • gemini-2.5-flash-image    │
                                                   │  • gemini-2.5-flash-preview- │
                                                   │      tts (narration)         │
                                                   └──────────────────────────────┘
```

- Authentication is **PIN-based** — caregiver registers with a 4-digit PIN; the backend hashes it with bcrypt and issues a 24-hour sliding session token.
- The Flutter app stores the session token in `SharedPreferences` and attaches it as a Bearer header on every protected request.
- **Narration runs server-side** through Gemini's Speech Generation API; the backend caches each rendered clip on disk by SHA-1 of `(voice|text)` so the same page is never regenerated. The client plays the cached URL through `just_audio`.
- The backend's `mediaUrl` helper builds URLs from the **incoming request's host** (not `APP_URL`), so the emulator at `10.0.2.2:8000` and a real phone on Wi-Fi both get URLs they can reach without any `.env` tweaks.

---

## Modules

| Module | Responsibility |
|---|---|
| **M1 General Module** | Caregiver registration, PIN login, PIN change, Guardian-PIN gate on Child Mode exit. Issues + validates the 24-hour Bearer session token. |
| **M2 Personalisation Settings** | Create / view / update / delete child profiles. Per-child sensory settings (narrator voice, reading speed, volume, text size, reduced animations, auto-play, read-along) stored in a dedicated `child_settings` row keyed by `child_id`. App language toggle (en / ms). |
| **M3 Content Management** | Manual upload (per-page text + image + cover, optional whole-book audio with page-boundary marks); AI generation (Gemini text + illustrations); browse / search / filter (type, age, language); caregiver preview using the same player the child sees. |
| **M4 AI Module** | Wraps Gemini API calls — story generation (`gemini-2.5-flash`), illustration generation (`gemini-2.5-flash-image`, downscaled + JPEG-compressed via GD on save), narration synthesis (`gemini-2.5-flash-preview-tts`, cached server-side). |
| **M5 Audio Playback Engine** | Storybook UI (sentence-paginated, embedded illustrations, 3-D book-flip with spine shadow). Word-by-word read-along (yellow highlight box). Audio sources: Gemini TTS (per-page cached WAV) or caregiver's whole-book recording (pages auto-flip at exact marked boundaries, or fall back to a word-count heuristic if unmarked). |
| **M6 Listening Insights** | Records per-session metadata (duration, position, mood, completion). Caregiver dashboard with overall + per-child filtering, last-7-days chart, top stories, recent activity feed, average session length, current streak. |

---

## Tech Stack

**Frontend (`frontend/`)**
- Flutter 3 / Dart 3
- `provider` for state management
- `just_audio` + `audio_session` for all audio playback (TTS clips and pre-recorded files)
- `file_picker` for caregiver audio upload + the in-form boundary editor's preview
- `image_picker` for cover / per-page illustrations
- `http` for REST calls
- `shared_preferences` + `flutter_secure_storage` for session persistence
- `google_fonts` (Nunito) for typography
- `pin_code_fields` for PIN entry UI
- Custom in-house i18n in [`lib/i18n/`](frontend/lib/i18n/) — flat `en` / `ms` Maps, no codegen, `context.tr('key')` everywhere

**Backend (`backend/`)**
- PHP 8.2+ / Laravel 11
- MySQL via XAMPP
- UUIDs via Laravel's `HasUuids` trait
- Custom session-token middleware (no Sanctum)
- Google Gemini API for text + image + TTS generation
- PHP `gd` extension (recommended — used to downscale AI-generated images from 1024² PNG to ≤ 768² JPEG when saving, ~7–10× smaller files)

---

## Project Structure

```
audiobook_system/
├── backend/                           ← Laravel API
│   ├── app/
│   │   ├── Models/                    ← Caregiver, ChildProfile, CaregiverSettings,
│   │   │                                ChildSettings, Audiobook, AudiobookPage,
│   │   │                                ListeningHistory
│   │   ├── Services/
│   │   │   └── GeminiService.php      ← Gemini text / image / TTS client
│   │   ├── Jobs/
│   │   │   └── GenerateAudiobookImages.php
│   │   └── Http/
│   │       ├── Controllers/Api/       ← ApiController (base) + Auth, ChildProfile,
│   │       │                            Settings, Audiobook, ContentManagement,
│   │       │                            ListeningHistory, Insights, Tts
│   │       └── Middleware/            ← SessionAuthMiddleware
│   ├── database/migrations/           ← UUID schema (caregivers, child_profiles,
│   │                                    caregiver_settings, child_settings,
│   │                                    audiobooks, audiobook_pages, listening_history)
│   ├── storage/app/public/            ← uploads/covers, uploads/audio, uploads/pages, tts
│   └── routes/api.php                 ← All `/api/*` endpoints
│
├── frontend/                          ← Flutter mobile app
│   └── lib/
│       ├── config/                    ← API base URL
│       ├── i18n/                      ← AppStrings (en / ms) + BuildContext.tr
│       ├── navigation/                ← AppNavigationService + AppRoutes
│       ├── models/                    ← JSON shapes mirroring backend resources
│       ├── services/                  ← DatabaseService (REST client)
│       ├── state/                     ← AuthState, ProfilesState, SettingsState,
│       │                                LanguageState
│       ├── theme/                     ← AppColors + AppTheme (Nunito)
│       ├── widgets/                   ← SoftCard, SoftChip, BackPill, StatCard,
│       │                                AppSnackbar, EmptyState
│       ├── audio/                     ← AudioEngine wrapper around just_audio
│       └── pages/
│           ├── shared/                ← AuthGate, LoginPage, GuardianPinDialog
│           ├── caregiver/             ← Dashboard, Profiles, ContentManagement,
│           │                            UploadContent (incl. PageBoundariesEditor),
│           │                            Settings, Insights, AddChildDialog
│           └── child/                 ← ChildShell, ChildHome, StoryLibrary,
│                                        AudioPlayerPage
│
└── README.md                          ← This file
```

---

## Prerequisites

- **PHP 8.2+** and **Composer** — bundled with XAMPP on Windows.
- **MySQL 5.7+** — bundled with XAMPP.
- **PHP `gd` extension** — used for image downscaling. In XAMPP, uncomment `extension=gd` in `C:\xampp\php\php.ini` and restart Apache. Without it the system still works, but generated images stay at 1024² PNG (~1.4 MB each) and load noticeably slower on the emulator.
- **Flutter 3.x** — `flutter doctor` should report no critical errors.
- **Android Studio** with an emulator, **or** a physical Android phone with USB debugging enabled.
- **Google Gemini API key** — get one at https://aistudio.google.com/. Image generation requires a **billing-enabled** key (the free tier returns quota 0 for `gemini-2.5-flash-image`); text + TTS work on the free tier.
- (Optional) **VS Code** with Dart / Flutter and PHP extensions.

---

## Backend Setup (Laravel)

```powershell
cd c:\xampp\htdocs\audiobook_system\backend

# 1. Install PHP dependencies
composer install

# 2. Copy the env file and generate an app key
copy .env.example .env
php artisan key:generate

# 3. Create the database in phpMyAdmin (http://localhost/phpmyadmin)
#    Name: autism_audiobook

# 4. Edit .env:
#       DB_DATABASE=autism_audiobook
#       DB_USERNAME=root
#       DB_PASSWORD=
#       GEMINI_API_KEY=<your_gemini_key>
#       GEMINI_TEXT_MODEL=gemini-2.5-flash         # default
#       GEMINI_IMAGE_MODEL=gemini-2.5-flash-image  # default (needs billing)

# 5. Run migrations
php artisan migrate:fresh

# 6. Link storage so uploaded/generated media is served statically
php artisan storage:link

# 7. Start the API bound to your LAN so a phone can reach it
php artisan serve --host=0.0.0.0 --port=8000
```

`APP_URL` does **not** need to point at a specific host — the controllers build media URLs from the **incoming request's host**, so the same backend serves correct URLs to the emulator (via `10.0.2.2:8000`) and to real devices on Wi-Fi without any `.env` tweaks.

---

## Frontend Setup (Flutter)

```powershell
cd c:\xampp\htdocs\audiobook_system\frontend

# 1. Install Dart/Flutter dependencies
flutter pub get

# 2. Tell the app where the API lives — edit lib/config/app_config.dart
#    For an Android emulator: http://10.0.2.2:8000/api
#    For a physical phone on the same Wi-Fi: http://<your-pc-LAN-IP>:8000/api

# 3. Confirm a device is connected
flutter devices

# 4. Run on the connected device (debug)
flutter run

# OR run a release build directly to the connected device
flutter run --release
```

---

## Testing on a Physical Phone

1. Confirm the phone and the PC are on the **same Wi-Fi network**.
2. On the PC, find the Wi-Fi adapter's IPv4 address:
   ```powershell
   ipconfig
   ```
3. Put that IP in [frontend/lib/config/app_config.dart](frontend/lib/config/app_config.dart):
   ```dart
   static const String databaseApiUrl = 'http://192.168.x.x:8000/api';
   ```
4. Start the API bound to all interfaces:
   ```powershell
   cd c:\xampp\htdocs\audiobook_system\backend
   php artisan serve --host=0.0.0.0 --port=8000
   ```
5. Open Windows Firewall once (run PowerShell as Administrator):
   ```powershell
   New-NetFirewallRule -DisplayName "Laravel Dev 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
   ```
6. On the phone's browser, visit `http://<your-PC-IP>:8000` — the Laravel welcome page should appear. If it doesn't, the firewall is still blocking.
7. Run `flutter run --release` with the phone connected over USB.

The Android manifest already grants `INTERNET` permission and sets `usesCleartextTraffic="true"`, so plain-HTTP LAN traffic works on Android 9+.

---

## Building a Release APK

```powershell
cd c:\xampp\htdocs\audiobook_system\frontend

# Single universal APK
flutter build apk --release

# Smaller per-architecture APKs
flutter build apk --release --split-per-abi
```

Output lands in `build\app\outputs\flutter-apk\`. Copy the APK to the phone, allow "Install unknown apps" in the file-manager settings, and tap the file.

---

## Database Schema

All tables use **UUID (`char(36)`) primary keys**.

| Table | Primary key | Notable foreign keys | Purpose |
|---|---|---|---|
| `caregivers` | `caregiver_id` | — | Caregiver accounts; bcrypt-hashed PIN, session token, sliding 24-hour expiry. |
| `child_profiles` | `child_id` | `caregiver_id` | Each child supervised by a caregiver (name, age, avatar emoji + colour, favourite genre). |
| `caregiver_settings` | `setting_id` | `caregiver_id` (unique) | Account-level settings (PIN-related and historical defaults). |
| `child_settings` | `setting_id` | `child_id` (unique) | **Per-child** sensory & narration settings — narrator voice, reading speed, volume, `text_scale`, reduced animations, auto-play, read-along. Loaded on child-mode entry. |
| `audiobooks` | `audiobook_id` | — | Story content — title, body text, `language` (`en` / `ms`), optional `audio_file` / `cover_image` paths, status, `is_generated` flag. |
| `audiobook_pages` | `page_id` | `audiobook_id` | One row per storybook page — `page_number`, `text`, `image`, `image_prompt`, `audio_start_ms` (offset in the whole-book recording where this page begins; nullable). |
| `listening_history` | `history_id` | `child_id`, `audiobook_id` | One row per listening session — `duration_seconds`, `last_position_seconds`, `mood`, `completed`. |

All foreign keys use `ON DELETE CASCADE`. Deleting a caregiver cleans the entire family tree of profiles, settings, audiobooks, pages, and history.

Static files (uploaded covers, audio, generated images, cached TTS clips) live under `backend/storage/app/public/` and are served via Laravel's `storage:link` symlink as `/storage/...`.

---

## REST API Reference

Base URL: `http://<host>:8000/api`. Every request is `POST` (multipart only for uploads); responses are always JSON of shape:

```jsonc
{ "status": "SUCCESS" | "ERROR",
  "message": "...",
  "data": { ... },
  "error_code": "OPTIONAL",
  "timestamp": "YYYY-MM-DD HH:mm:ss" }
```

**Public**
| Method | Path | Purpose |
|---|---|---|
| POST | `/test` | Health check. |
| POST | `/auth/register` | Create a caregiver, returns session token + caregiver profile. |
| POST | `/auth/login` | PIN login, returns session token. |

**Protected** — require `Authorization: Bearer <session_token>`.

| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/me` | Current caregiver. |
| POST | `/auth/logout` | Invalidate token. |
| POST | `/auth/verify-pin` | Used by the Guardian PIN dialog. |
| POST | `/settings/` | Get caregiver account settings. |
| POST | `/settings/update` | Patch caregiver account settings. |
| POST | `/settings/change-pin` | Replace PIN. |
| POST | `/child-profiles/` | List children for the caregiver. |
| POST | `/child-profiles/create` | Add a child. |
| POST | `/child-profiles/{childId}/update` | Update a child. |
| POST | `/child-profiles/{childId}/delete` | Delete a child. |
| POST | `/child-profiles/{childId}/settings` | Get this child's per-child sensory settings. |
| POST | `/child-profiles/{childId}/settings/update` | Update this child's sensory settings. |
| POST | `/audiobooks/{audiobookId}` | Fetch one audiobook (with pages + `audio_start_ms`). |
| POST | `/content/summary` | Library totals by type. |
| POST | `/content/list` | Search / filter. Body: `filter_type`, `search`, `category`, `age_group`, `language` (`en` / `ms`), `visibility` (`public` / `private`). |
| POST | `/content/create` | Upload content (multipart) — accepts `cover_image`, `audio_file`, `language`, body fields. `visibility` (`private` or `public`) is required. |
| POST | `/content/{audiobookId}/pages` | Add one page (multipart) — `text`, `image`, optional `audio_start_ms`. |
| POST | `/content/generate` | AI-generate a storybook — body: `topic`, `age_group`, `difficulty`, `page_count`, `language`, `generate_image`, `visibility` (required: `private` or `public`). |
| POST | `/tts/speak` | Render one page of text into a cached Gemini-TTS WAV; returns the URL. |
| POST | `/listening-history/record` | Persist a session. |
| POST | `/listening-history/child/{childId}` | Last 50 sessions for a child. |
| POST | `/insights/overview` | Caregiver insights — optional `child_id` body field scopes everything to that one child. |

---

## In-App User Flow

1. **First launch** — the user lands on the Login screen. Tap *Create a caregiver account* to register.
2. **Caregiver Dashboard** — top-level totals, list of child profiles, prominent *Logout* button.
3. **Profiles tab** — add / edit / remove children.
4. **Content tab** — upload stories (manual or AI), preview any book in the same player the child sees, filter by type / age / language. New books auto-appear in the list when the upload page closes; books still rendering images keep a *Generating…* badge until they're ready.
5. **Upload Content (manual)** — title, cover image, language (en / ms), per-page text + image, plus an optional **whole-book audio recording**. When audio is attached, the **Page Boundaries Editor** appears: tap Play, listen, then tap *Mark* on each page row at the moment that page begins. Marks become the exact page-flip cues the child-side player uses.
6. **Upload Content (AI)** — topic + page count + language; Gemini generates the story + a one-line illustration per page in the chosen language. The book appears in the library with a *Generating…* badge until images finish.
7. **Insights tab** — child-scope chip (All children + one per child), six stat cards (Total Minutes, Sessions, Completion %, Top Mood, Avg Session, Streak), last-7-days bar chart, mood breakdown, top 5 stories, last 10 sessions, per-child summary cards. Tapping a chip refetches insights scoped to that child.
8. **Settings tab** — child selector + per-child cards: Narration (5 voice chips), Reading Speed, Sensory & Playback (reduced animations / auto-play / read-along), Text Size with live preview. Plus an app-wide Language card (en / ms) and a PIN-change card.
9. **Enter Child Mode** — tap *Enter Child Mode* on a profile card → the app switches to the Child Shell with that child's settings loaded.
10. **Child Home** — mood selection, *Today's pick*, *Browse Story Library*.
11. **Story Library** — search by title, filter by category, age range, **language**.
12. **Audio Player** — sentence-paginated storybook with cover illustration; 3-D book-flip page transitions; tap **Listen** to start narration. If the book has a caregiver recording, that plays and pages auto-flip at the marked boundaries; otherwise Gemini TTS narrates each page and the read-along highlight follows the spoken word.
13. **Exit Child Mode** — tap the *Exit* tab → Guardian PIN dialog → return to the Caregiver Dashboard.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| **`SQLSTATE[42S02] ... 'caregivers' doesn't exist`** | Migrations haven't run. `php artisan migrate:fresh` from `backend/`. |
| **Login screen never connects** | Phone can't reach the PC's IP. Visit `http://<pc-ip>:8000` on the phone's browser to verify, then open the firewall (see [Testing on a Physical Phone](#testing-on-a-physical-phone)). |
| **"Could not load this book's audio — using AI narration instead."** | The audio URL came back from the API but `just_audio` couldn't fetch the file. Most often this means `storage/` isn't published — re-run `php artisan storage:link` and confirm the file exists under `backend/storage/app/public/uploads/audio/`. |
| **Validation failed: "audio file field must be a file of type: mp3, wav"** | Pull the latest backend — `audio_file` now validates with `mimetypes:audio/mpeg,audio/wav,…` which accepts every MP3 / WAV / M4A / AAC / OGG variant Android pickers actually return. |
| **AI image generation returns HTTP 429 / quota 0** | `gemini-2.5-flash-image` requires a **billing-enabled** Gemini API key (the free tier returns 0 quota for image generation). Enable billing on the key in Google AI Studio; story text generation continues to work on the free tier in the meantime. |
| **Generated images load slowly on emulator** | Enable PHP's `gd` extension (uncomment `extension=gd` in `C:\xampp\php\php.ini`; restart Apache). On save, Gemini's 1024² PNGs get downscaled to ≤ 768² JPEG (~7–10× smaller). Existing images stay as-is. |
| **"Cleartext HTTP not permitted"** | Only an issue on custom builds; the bundled manifest enables it. If you changed the manifest, restore `android:usesCleartextTraffic="true"`. |
| **Phone shows a raw SQL error in a snackbar** | `APP_DEBUG=true` in `backend/.env` leaks the SQL exception. Set `APP_DEBUG=false` for friendlier "Server Error" messages. |
| **Pages don't auto-flip when audio plays** | The book is either (a) silently falling back to TTS — watch for the orange "Could not load this book's audio" snackbar; or (b) the audio is reachable but the book has no page-boundary marks and the heuristic isn't matching your pacing — re-open the book in Upload → set marks → save. |

---

## Academic Context

This system was developed as a Final Year Project investigating **AI-supported audiobook delivery for autistic learners**. The system analysis and design (use case diagram, module breakdown, functional requirements) is documented separately in the project report; the present README focuses on the deliverable software.

The **Gemini AI integration** is live — text generation, illustration generation, and TTS narration all call the Gemini API at runtime (see [`backend/app/Services/GeminiService.php`](backend/app/Services/GeminiService.php)). The remaining planned-future-work piece is UC-9 *Analyse Listening Behaviour*, which would feed `listening_history` aggregates back into Gemini to suggest sensory-preference adjustments per child — the data is already being recorded; only the analysis call is unwired.

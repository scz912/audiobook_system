# Deploying the backend to Railway

A step-by-step guide to put the Laravel backend + MySQL on Railway so the app
works over the internet (needed for the community modules).

**What you're deploying**
- The **Laravel API** (this `backend/` folder) as a Railway *service*.
- A **MySQL database** as a Railway *plugin*.
- The Flutter app then points at the Railway URL instead of `10.0.2.2`.

Two config files are already committed for you:
- `nixpacks.toml` — tells Railway how to build and start the app.
- `.env.example` — the list of variables to set.

---

## 0. Before you start
1. Push the backend to **GitHub** (Railway deploys from a repo).
2. Create a free account at **railway.app** (sign in with GitHub).
3. Have your **Gemini API key** ready.

> **Monorepo note:** if this backend lives in a repo together with `frontend/`,
> you'll set the service's **Root Directory** to `backend` (Step 2). If the
> backend is its own repo, leave the root directory empty.

---

## 1. Create the project + MySQL
1. In Railway: **New Project → Deploy MySQL** (or **Provision MySQL**).
2. This creates a MySQL service. Open it → **Variables** tab: you'll see
   `MYSQLHOST`, `MYSQLPORT`, `MYSQLDATABASE`, `MYSQLUSER`, `MYSQLPASSWORD`.
   You don't copy these by hand — you'll reference them in Step 3.

---

## 2. Add the backend service
1. In the same project: **New → GitHub Repo →** pick your backend repo.
2. Open the new service → **Settings**:
   - **Root Directory:** `backend` (skip if the backend is its own repo).
   - Railway auto-detects PHP via `composer.json` and uses `nixpacks.toml`.

---

## 3. Set environment variables
Open the backend service → **Variables** → add these (from `.env.example`):

| Variable | Value |
|---|---|
| `APP_ENV` | `production` |
| `APP_DEBUG` | `false` |
| `APP_KEY` | see Step 4 |
| `APP_URL` | your Railway URL (fill after Step 6) |
| `APP_TIMEZONE` | `Asia/Kuala_Lumpur` |
| `DB_CONNECTION` | `mysql` |
| `DB_HOST` | `${{ MySQL.MYSQLHOST }}` |
| `DB_PORT` | `${{ MySQL.MYSQLPORT }}` |
| `DB_DATABASE` | `${{ MySQL.MYSQLDATABASE }}` |
| `DB_USERNAME` | `${{ MySQL.MYSQLUSER }}` |
| `DB_PASSWORD` | `${{ MySQL.MYSQLPASSWORD }}` |
| `QUEUE_CONNECTION` | `sync` |
| `FILESYSTEM_DISK` | `public` |
| `SESSION_DRIVER` | `database` |
| `CACHE_STORE` | `database` |
| `GEMINI_API_KEY` | your key |
| `GEMINI_TEXT_MODEL` | `gemini-2.5-flash` |
| `GEMINI_IMAGE_MODEL` | `gemini-2.5-flash-image` |

> The `${{ MySQL.XXX }}` syntax pulls values straight from the MySQL service, so
> you never paste the password. If your MySQL service isn't named exactly
> "MySQL", change the prefix to match its name.

---

## 4. Generate APP_KEY
On your own computer, in `backend/`:
```
php artisan key:generate --show
```
Copy the printed `base64:...` value into the `APP_KEY` variable on Railway.

---

## 5. Deploy
Railway deploys automatically on every push. The start command (in
`nixpacks.toml`) runs on each deploy:
```
php artisan migrate --force   # creates/updates all tables
php artisan storage:link      # makes uploaded files reachable
php artisan serve             # starts the API on Railway's port
```
Watch the **Deploy Logs** — you should see the migrations run and "server running".

---

## 6. Get your public URL
Backend service → **Settings → Networking → Generate Domain**. You'll get
something like `https://your-app.up.railway.app`.
- Put that (with no trailing slash) into the `APP_URL` variable.
- Test it: open `https://your-app.up.railway.app/api/test` — you should get
  `{"status":"SUCCESS",...}` (send it as POST if GET is blocked; the browser GET
  may 405, that's fine — it means the server is up).

---

## 7. Point the Flutter app at Railway
In `frontend/lib/config/app_config.dart`:
```dart
static const String databaseApiUrl = 'https://your-app.up.railway.app/api';
```
Rebuild the app (full restart, since it's a `const`). Now it talks to the cloud
and works on any device, not just your emulator.

---

## 8. (Important) Keep uploaded files — add a Volume
Railway's disk is **wiped on every redeploy**. Your generated covers, uploaded
audio, and cached voices live in `storage/app/public`, so without a volume they
disappear when you push an update.

Fix: backend service → **Variables/Settings → Volumes → New Volume**, mount path:
```
/app/storage/app/public
```
Now those files survive redeploys. (For a class demo you can skip this and just
regenerate content, but it's one click to do it properly.)

---

## Troubleshooting
- **500 error / "No application encryption key"** → `APP_KEY` not set (Step 4).
- **DB connection refused** → the `DB_*` variables don't match the MySQL service
  name in the `${{ ... }}` references.
- **Build fails on composer** → make sure **Root Directory** is `backend` so
  Railway finds `composer.json`.
- **Images/audio 404 after a while** → add the Volume (Step 8).
- **Seeded data missing** (e.g. music tracks) → run once from the service shell:
  `php artisan db:seed --force`.

---

## Notes
- `QUEUE_CONNECTION=sync` runs the AI image job inline during the request, so you
  don't need a separate worker service. If generation feels slow, you can later
  add a **worker** service with start command `php artisan queue:work` and switch
  `QUEUE_CONNECTION` to `database`.
- `php artisan serve` is fine for a demo. For heavier use, switch to a Dockerfile
  with nginx + php-fpm later — ask and I'll add one.

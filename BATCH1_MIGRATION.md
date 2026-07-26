# Batch 1 — Security & Auth Migration Guide

## What Changed

### Backend

| File | Change |
|---|---|
| `purepick_core/settings.py` | **Deleted** — replaced by `settings/` package |
| `purepick_core/settings/base.py` | New — shared settings for all environments |
| `purepick_core/settings/dev.py` | New — development overrides |
| `purepick_core/settings/prod.py` | New — production hardening (HTTPS, strict CORS) |
| `purepick_core/auth_utils.py` | **New** — argon2 hashing, JWT generation, Google OAuth verification, ownership decorators |
| `purepick_core/views.py` | Rewritten — JWT on all endpoints, argon2 passwords, Google token verification, ownership guards |
| `scanner/views.py` | Rewritten — JWT required, user_id from token, image validation, debug prints removed |
| `scanner/utils.py` | Rewritten — pickle replaced with JSON (security fix) |
| `scanner/urls.py` | Updated — added `/token/refresh/` and `/logout/` endpoints |
| `skin_analysis/views.py` | Rewritten — JWT required, ownership guard, medical disclaimer |
| `requirements.txt` | Updated — added djangorestframework-simplejwt, argon2-cffi, google-auth |
| `.env.example` | Updated — added GOOGLE_CLIENT_ID, DJANGO_SETTINGS_MODULE |
| `manage.py` / `wsgi.py` | Updated — default to `purepick_core.settings.dev` |

### Flutter

| File | Change |
|---|---|
| `lib/services/api_service.dart` | Rewritten — stores/attaches JWT, auto-refresh on 401, configurable base URL, no hardcoded IP |

---

## Setup Steps

### 1. Install new dependencies
```bash
cd backend
pip install djangorestframework-simplejwt==5.3.1 argon2-cffi==23.1.0 google-auth==2.29.0 python-json-logger==2.0.7
```

### 2. Copy and fill .env
```bash
cp .env.example .env
# Edit .env and set:
#   SECRET_KEY  (generate a new one)
#   DB_PASSWORD
#   GEMINI_API_KEY
#   GOOGLE_CLIENT_ID  (from Google Cloud Console)
```

### 3. Run migrations (new JWT blacklist table)
```bash
python manage.py migrate
```

### 4. Run dev server
```bash
DJANGO_SETTINGS_MODULE=purepick_core.settings.dev python manage.py runserver
```

### 5. Flutter — set API base URL
Build with the correct server URL:
```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_DEV_IP:8000/api
# or for release:
flutter build apk --dart-define=API_BASE_URL=https://api.yourdomain.com/api
```

---

## Breaking Changes for Existing Users

- **All existing sessions are invalidated** — users must log in again to get a JWT
- **Existing SHA-256 passwords still work** — they are silently upgraded to argon2 on next login
- **`user_id` no longer accepted in request bodies** for profile/save/delete — backend reads from JWT
- **`save_scan_pkl()` still works but logs a deprecation warning** — migrate to `save_scan_json()`

---

## Security Items Fixed in This Batch

| # | Issue | Fix |
|---|---|---|
| 1 | SHA-256 unsalted passwords | argon2 via Django hashers |
| 2 | No API authentication | JWT Bearer tokens (simplejwt) |
| 3 | IDOR via integer user_id | Ownership guard decorator on all user-scoped endpoints |
| 4 | Google token unverified | google-auth server-side verification |
| 5 | DEBUG=True / ALLOWED_HOSTS='*' | Environment-split settings, prod.py hardens these |
| 6 | CORS_ALLOW_ALL_ORIGINS=True | Explicit CORS_ALLOWED_ORIGINS per environment |
| 7 | Pickle scan storage | Replaced with JSON (no deserialization risk) |
| 8 | No image upload validation | Extension whitelist + 10 MB size cap |
| 9 | Raw Gemini errors exposed | Errors logged, generic message returned to client |
| 10 | Hardcoded LAN IP in Flutter | `--dart-define=API_BASE_URL` configurable at build time |
| 11 | AUTH_PASSWORD_VALIDATORS=[] | Full validator suite enabled in base.py |
| 12 | DB credentials in settings.py | Moved to .env, required via os.environ (hard fail if missing) |

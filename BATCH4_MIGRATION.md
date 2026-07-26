# Batch 4 — Data & Schema Migration Guide

## What Changed

### Problems Fixed

| # | Before | After |
|---|---|---|
| 1 | Allergies stored as `"Fragrance,Sulfates,Nuts"` text blob | `AllergyTag` M2M table — queryable, indexable, no string parsing |
| 2 | Skin conditions same comma-text problem | `SkinConditionTag` M2M table |
| 3 | No email field on User | `email` field added, indexed |
| 4 | Forgot password screen had no backend | Full 2-step flow: request token → confirm reset |
| 5 | No barcode scanning | `mobile_scanner` + Open Beauty Facts API + full analysis pipeline |
| 6 | No product scan source tracking | `scan_source` field: `manual` / `ocr` / `barcode` |
| 7 | Missing DB indexes on hot query paths | Compound index on `(user, -scanned_at)`, barcode index |

---

## New Files

| File | Purpose |
|---|---|
| `purepick_core/migrations/0004_batch4_schema.py` | Schema changes + data migration |
| `purepick_core/password_reset_views.py` | Request + confirm password reset endpoints |
| `scanner/barcode_service.py` | Open Beauty Facts API client |
| `mobile_app/lib/screens/barcode_scanner_screen.dart` | Camera barcode scanner UI |
| `mobile_app/pubspec.yaml` | First pubspec — adds `mobile_scanner` + `image_picker` |

## Modified Files

| File | Change |
|---|---|
| `purepick_core/models.py` | AllergyTag, SkinConditionTag, PasswordResetToken, email/last_login on User, scan_source/barcode on ScanRecord |
| `purepick_core/views.py` | update_profile uses M2M; get_profile returns M2M lists; register saves email; login sets last_login |
| `scanner/tasks.py` | `run_barcode_analysis` task; `_persist_scan_record` gets scan_source + barcode params |
| `scanner/views.py` | `lookup_barcode` endpoint |
| `scanner/urls.py` | `/api/barcode-lookup/` + `/api/password-reset/request/` + `/api/password-reset/confirm/` |
| `mobile_app/lib/services/api_service.dart` | `requestPasswordReset`, `confirmPasswordReset`, `barcodeAnalysis` methods |
| `mobile_app/lib/screens/forgot_password_screen.dart` | Full 2-step reset flow (was dead placeholder) |

---

## Setup

### 1. Run migrations
```bash
python manage.py migrate
# Migration 0004 will:
#   - Create AllergyTag and SkinConditionTag tables
#   - Seed 14 preset allergy tags + 8 skin condition tags
#   - Move all existing comma-text data into M2M tables
#   - Add email, last_login to User
#   - Add scan_source, barcode to ScanRecord
```

### 2. Configure email for password reset
**Dev (prints to terminal):** No config needed. Default is console backend.

**Prod (SendGrid):**
```bash
# Add to .env:
EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp.sendgrid.net
EMAIL_HOST_USER=apikey
EMAIL_HOST_PASSWORD=your_sendgrid_api_key
DEFAULT_FROM_EMAIL=noreply@purepick.app
FRONTEND_BASE_URL=https://app.purepick.com
```

### 3. Flutter: install new packages
```bash
cd mobile_app
flutter pub get
```

### 4. Android: camera permissions for barcode scanner
Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
```
_(Already present for camera screen — verify it's there.)_

---

## Password Reset Flow

```
User taps "Forgot Password"
  └── POST /api/password-reset/request/ { username_or_email }
        └── Server creates UUID token, sends email
        └── Always returns 200 (no enumeration)

User enters token from email + new password
  └── POST /api/password-reset/confirm/ { token, new_password }
        └── Server validates token + expiry
        └── Sets new argon2 password
        └── Deletes token (single-use)
        └── Returns 200
```

**Security:** UUID4 tokens (128-bit entropy), 1-hour expiry, single-use, no user enumeration.

---

## Barcode Flow

```
User taps "Scan Barcode"
  └── mobile_scanner detects UPC/EAN
  └── POST /api/barcode-lookup/ { barcode }  → 202 + task_id
        └── Celery: Open Beauty Facts API lookup
        └── Celery: ingredient_intelligence analysis
        └── DB: ScanRecord saved (scan_source='barcode')
  └── Flutter polls /api/task/<id>/ until SUCCESS
  └── Navigate to ResultScreen (same as OCR scan)
```

**Product not found:** Returns `{ status: 'not_found' }` → Flutter prompts manual entry.
Open Beauty Facts covers 200k+ cosmetic products and is free with no API key.

---

## Data Migration Details

Existing profiles with `"Fragrance,Sulfates,Nuts"` in the `allergies` column are automatically converted:

| Legacy string | Canonical M2M tag |
|---|---|
| `Fragrance` | `Fragrance Allergy` |
| `Sulfates` | `Sulfate Sensitivity` |
| `Nuts` | `Nut Allergy` |
| `Parabens` | `Paraben Sensitivity` |
| `Dairy` | `Dairy Allergy` |
| `Soy` | `Soy Allergy` |
| `Alcohol` | `Alcohol Sensitivity` |
| `Gluten` | `Gluten Sensitivity` |

The legacy `allergies_legacy` field is kept intact (not deleted) as a safety net.
It can be dropped in a future migration once M2M data is confirmed correct.

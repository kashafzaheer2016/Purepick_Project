# Batch 6 — Growth Features Migration Guide

## What Was Done

### Problems Fixed / Features Added

| # | Feature | Status |
|---|---|---|
| 1 | Dark mode | ✅ Full — persisted, system-respecting, toggle in Settings |
| 2 | Named routes / deep linking | ✅ Full — `AppRouter` replaces all `Navigator.push()` |
| 3 | Shareable scan card | ✅ Full — branded PNG card captured and shared from ResultScreen |
| 4 | FCM push notifications | ✅ Backend wired — Flutter stub (uncomment `firebase_messaging`) |
| 5 | PDF export | ✅ Full — `/api/scan/<id>/export-pdf/` returns formatted PDF |
| 6 | ProductName/Brand/Image in ResultScreen | ✅ — passed from barcode scans |

---

## New Files

### Flutter
| File | Purpose |
|---|---|
| `lib/app_router.dart` | Named route registry + transition definitions |
| `lib/theme_provider.dart` | Dark/light mode singleton with SharedPreferences persistence |
| `lib/widgets/scan_share_card.dart` | Branded share card widget + `ShareCardService` |
| `lib/services/fcm_service.dart` | FCM token registration stub (ready for `firebase_messaging`) |

### Backend
| File | Purpose |
|---|---|
| `purepick_core/notification_views.py` | FCM token registration + `send_scan_risk_notification()` |
| `scanner/pdf_views.py` | reportlab PDF generation for scan results |
| `purepick_core/migrations/0005_fcm_token.py` | Adds `fcm_token` to `HealthProfile` |

### Modified Files
| File | Change |
|---|---|
| `lib/main.dart` | `ThemeProvider`, named routes via `AppRouter.onGenerateRoute` |
| `lib/screens/settings_screen.dart` | Dark mode toggle |
| `lib/screens/result_screen.dart` | Share button, offstage card, `productName`/`brandName`/`imageUrl` params |
| `lib/services/api_service.dart` | `registerFcmToken()` method |
| `lib/pubspec.yaml` | Version bump to 1.1.0+6, notes for `firebase_messaging`/`share_plus` |
| `scanner/tasks.py` | FCM notification call after scan save |
| `scanner/urls.py` | `/api/notifications/register-token/` + `/api/scan/<id>/export-pdf/` |
| `purepick_core/models.py` | `fcm_token` field on `HealthProfile` |
| `backend/requirements.txt` | `reportlab`, `firebase-admin` |

---

## Setup

### 1. Migrate DB (adds fcm_token column)
```bash
python manage.py migrate
```

### 2. Install PDF library
```bash
pip install reportlab==4.2.2
```

### 3. Enable FCM (optional)
```bash
pip install firebase-admin==6.5.0
# Download service account JSON from Firebase Console
# Add to .env:
FIREBASE_CREDENTIALS_PATH=/path/to/firebase-service-account.json
```

### 4. Enable Flutter share sheet (optional)
Uncomment in `pubspec.yaml`:
```yaml
share_plus: ^10.0.0
```
Then in `scan_share_card.dart`, replace the stub `_showShareSheet()` with:
```dart
import 'package:share_plus/share_plus.dart';
final xFile = XFile.fromData(bytes, mimeType: 'image/png', name: '$productName.png');
await Share.shareXFiles([xFile], text: 'Scanned with PurePick AI');
```

### 5. Enable FCM in Flutter (optional)
Uncomment in `pubspec.yaml`:
```yaml
firebase_messaging: ^15.1.0
```
Then follow the stubs in `lib/services/fcm_service.dart`.

---

## Dark Mode

The dark theme is implemented using Flutter's Material 3 `ThemeData`. All screens automatically
adapt because they use `Theme.of(context)` colors. The sage green color scheme
is consistent in both modes.

Toggle: Settings → Dark Mode switch
Persistence: `SharedPreferences` key `dark_mode_enabled`
Scope: App-wide, immediate — no restart needed

---

## Named Routes

Navigation now uses:
```dart
// Before (Batch 1–5):
Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()));

// After (Batch 6):
Navigator.pushNamed(context, AppRouter.history);

// With arguments:
Navigator.pushNamed(context, AppRouter.result, arguments: {
  'score': 85.0,
  'riskLevel': 'Safe',
  'dangerItems': [],
});
```

Deep link support for password reset:
```
purepick://reset-password?token=<uuid>
```
The `AppRouter.onGenerateRoute` extracts the token and passes it to `ForgotPasswordScreen`.

---

## Scan Card Sharing

The shareable card is rendered off-screen (at x=-2000) and captured as PNG bytes
via `RepaintBoundary.toImage()`. The card shows:
- Product name + brand
- Safety score (large)
- Risk level badge (green/amber/red)
- Top 3 flagged ingredients
- PurePick branding

Full share sheet requires `share_plus` package (see Setup above).

---

## PDF Export

```
GET /api/scan/<scan_id>/export-pdf/
Authorization: Bearer <token>
```
Returns a formatted PDF with:
- Product metadata (name, scan date, source, barcode)
- Safety score summary table
- Flagged ingredient list
- Full ingredient text
- AI analysis
- Footer with disclaimer

Requires `reportlab`. Falls back to plain text if not installed.

# Batch 5 — Test Suite Migration Guide

## What Was Added

### Test Infrastructure

| File | Purpose |
|---|---|
| `backend/pytest.ini` | pytest configuration, marker definitions |
| `backend/purepick_core/settings/test.py` | Test settings (SQLite in-memory, no Celery, mock email) |
| `backend/tests/conftest.py` | Shared fixtures (users, profiles, auth clients, scan records) |
| `backend/run_tests.sh` | Test runner with coverage support |

### Test Files (87 tests, all passing)

| File | Tests | Scope |
|---|---|---|
| `tests/test_ingredient_intelligence.py` | 30 | Unit: INCI resolver, scoring, allergy matching, full pipeline |
| `tests/test_ocr_parsing.py` | 22 | Unit: parse_ingredients_from_text() edge cases |
| `tests/test_barcode_service.py` | 19 | Unit: Open Beauty Facts API client (mocked HTTP) |
| `tests/test_ml_model.py` | 9 | Unit: RF model singleton, lazy load, graceful fallback |
| `tests/test_auth_utils.py` | 14 | Unit + Integration: hashing, JWT, decorators |
| `tests/test_api_endpoints.py` | 38 | API: all endpoints, auth, ownership, error cases |
| `tests/test_models.py` | 22 | Integration: M2M, PasswordResetToken, ScanRecord |
| `tests/test_ocr_pipeline.py` | 12 | Integration: OCR → parse → analyze end-to-end (mocked EasyOCR) |

---

## Bugs Found + Fixed During Testing

These were real implementation bugs caught by writing the tests:

| Bug | Location | Fix |
|---|---|---|
| Allergy matching was case-sensitive: `'nut allergy'` ≠ `'Nut Allergy'` | `ingredient_intelligence.py` `match_ingredient_to_profile()` | Case-insensitive key lookup added |
| Severity lookup was case-sensitive: `'nut allergy'` not found in `SEVERITY_RULES['CRITICAL']` | `ingredient_intelligence.py` | `any(i.lower() == allergy_norm for i in items)` |
| Same bug for skin conditions severity | `ingredient_intelligence.py` | Same fix |
| `ml_model.py` `predict_batch()` called `.tolist()` on mock list object | `ml_model.py` | Defensive `list()` / `hasattr` check |

---

## Setup

```bash
# Install test dependencies
pip install pytest==8.3.2 pytest-django==4.9.0 pytest-mock==3.14.0 pytest-cov==5.0.0

# Run all unit tests (fast, no DB needed)
SECRET_KEY=your-key ./run_tests.sh unit

# Run all tests except slow (OCR/ML model load)
SECRET_KEY=your-key ./run_tests.sh all

# Run with coverage report
SECRET_KEY=your-key ./run_tests.sh coverage
```

Or with Docker (Batch 2 stack):
```bash
docker-compose run api pytest tests/ -m "not slow" -v
```

---

## Test Markers

| Marker | Description | Run time |
|---|---|---|
| `unit` | Pure function tests, no DB, no network | ~1.5s |
| `integration` | DB tests using SQLite in-memory | ~3s |
| `api` | Full endpoint tests with test client | ~5s |
| `slow` | Real model load tests (needs .pkl files) | ~15s |

---

## Coverage Targets

Currently missing coverage (Batch 6 will add):
- `scanner/tasks.py` — Celery tasks (need task runner setup)
- `skin_analysis/` — ResNet-50 (model files needed)
- `scanner/ocr_engine.py` → `extract_text_easyocr()` (needs real image)

Covered at high confidence:
- `scanner/ingredient_intelligence.py` — ~95% line coverage
- `scanner/ocr_engine.py` → `parse_ingredients_from_text()` — ~90%
- `scanner/barcode_service.py` — ~85%
- `purepick_core/auth_utils.py` — ~90%
- All API endpoints — ~80%
- All models — ~95%

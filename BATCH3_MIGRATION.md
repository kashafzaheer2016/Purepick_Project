# Batch 3 — AI/ML Fixes Migration Guide

## What Changed

### Problems Fixed

| # | Before | After |
|---|---|---|
| 1 | RF model trained but never called — dead code | RF model wired into `ingredient_intelligence.py` via `ml_model.py` |
| 2 | Unknown ingredients silently marked safe | RF classifies unknowns; `high` predictions (≥60% confidence) flagged as `ML_PREDICTED` |
| 3 | Gemini calls blocking (no streaming) | `stream=True` on all Gemini calls — chunks accumulate as they arrive |
| 4 | AI tips regenerated on every request | 6-hour Redis cache; auto-invalidated after any new scan |
| 5 | Prompts could grow unboundedly | 12,000 char token budget guard with head+tail trim strategy |
| 6 | sklearn version mismatch warnings | `python manage.py train_rf_model` retrains with current sklearn |
| 7 | No way to retrain model from Django | `train_rf_model` management command with CV accuracy reporting |

---

## New Files

| File | Purpose |
|---|---|
| `scanner/ml_model.py` | Thread-safe RF model singleton with lazy load + graceful fallback |
| `scanner/management/commands/train_rf_model.py` | Django management command to retrain RF with current sklearn |

## Modified Files

| File | Change |
|---|---|
| `scanner/ingredient_intelligence.py` | `_augment_with_ml()` pass for unresolved ingredients |
| `scanner/ingredient_analyzer.py` | ML-predicted alerts surfaced with amber badge + `ml_augmented` flag |
| `scanner/tasks.py` | Streaming Gemini, tips caching, cache invalidation on scan save |

---

## Setup

### 1. Retrain the RF model (fixes sklearn version mismatch)
```bash
python manage.py train_rf_model
# Output: CV Accuracy: XX.X% ± X.X%
# Re-saves model with current sklearn version — no more warnings
```

### 2. No other migration steps needed
- Redis is already running from Batch 2
- Tips cache is zero-config — falls back gracefully if Redis is unavailable
- ML model load is lazy — Django starts up at full speed

---

## How the ML Pipeline Works

```
Ingredient List
      │
      ▼
resolve_ingredient()        ← INCI alias map (700+ entries)
      │
      ├─ RESOLVED ──► match_ingredient_to_profile()  ← Rule engine (authoritative)
      │
      └─ UNRESOLVED ─► predict_batch()               ← RF model (batch, one call)
                              │
                              ├─ high + conf ≥ 60% ──► flagged (ML_PREDICTED, amber)
                              ├─ moderate            ──► annotated, not flagged
                              └─ safe                ──► annotated, not flagged
```

**Confidence threshold (60%):** The RF model was trained on a small dataset.
Below 60% confidence, false positives outnumber true positives. The threshold
is configurable via `_RF_HIGH_RISK_THRESHOLD` in `ingredient_intelligence.py`.

---

## Tips Cache Behaviour

| Event | Cache Effect |
|---|---|
| `GET /api/ai-tips/<user_id>/` (first time) | Cache MISS → Gemini called → result cached (TTL 6h) |
| `GET /api/ai-tips/<user_id>/` (within 6h) | Cache HIT → Gemini skipped → instant return |
| New scan saved | Cache INVALIDATED → next tips request regenerates |
| Redis unavailable | Cache bypassed silently → Gemini called as normal |

---

## Report Shape Changes (Flutter-visible)

New fields in analyze response:
```json
{
  "ml_augmented": true,
  "model_available": true,
  "allergy_result": {
    "allergy_alerts": [
      {
        "severity": "ML_PREDICTED",
        "match_source": "rf_model",
        "ml_confidence": 0.73,
        "banner": "AI PREDICTED RISK — Contains your concern"
      }
    ]
  }
}
```

Flutter UI should show an amber "AI Predicted" badge when `severity == "ML_PREDICTED"`
and display the confidence percentage in the explanation text.

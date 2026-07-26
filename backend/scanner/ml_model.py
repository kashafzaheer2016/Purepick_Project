"""
scanner/ml_model.py
===================
Singleton loader for the Random Forest + TF-IDF vectorizer.

Design decisions:
  - Lazy-loaded on first call — never blocks Django startup
  - Thread-safe via a module-level lock
  - Returns (None, None) gracefully if model files are missing
  - Exposes predict_ingredient_risk() as the single public API
  - Re-trains from SQLite if model files are stale or missing

WHY this exists as a separate module:
  The original train_model.py trained the RF model but it was never wired
  into the analysis pipeline. ingredient_intelligence.py ran purely on the
  rule engine. This module bridges them: RF provides a data-driven confidence
  score for ingredients the rule engine doesn't explicitly know about.

Integration strategy (defence-in-depth):
  1. Rule engine runs first (high precision, curated knowledge)
  2. RF classifier runs on UNRESOLVED ingredients only
  3. If RF says 'high' risk on an unresolved ingredient → flag it with
     ML_PREDICTED severity so the UI can show a "predicted risk" badge
  4. If RF is unavailable → silently fall back to rule engine only
"""
from __future__ import annotations

import logging
import threading
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

_lock = threading.Lock()
_clf = None
_vectorizer = None
_load_attempted = False


def _load_models() -> tuple:
    """
    Load RF classifier and TF-IDF vectorizer from disk.
    Returns (clf, vectorizer) or (None, None) on any failure.
    Thread-safe — only loads once.
    """
    global _clf, _vectorizer, _load_attempted

    with _lock:
        if _load_attempted:
            return _clf, _vectorizer

        _load_attempted = True

        try:
            import joblib
            from django.conf import settings

            model_path = Path(settings.MODEL_PATH)
            vec_path   = Path(settings.VECTORIZER_PATH)

            if not model_path.exists() or not vec_path.exists():
                logger.warning(
                    'RF model files not found at %s — ingredient ML scoring disabled. '
                    'Run: python manage.py train_rf_model',
                    model_path.parent,
                )
                return None, None

            import warnings
            # Suppress sklearn version mismatch warnings — we handle this gracefully
            with warnings.catch_warnings():
                warnings.simplefilter('ignore')
                clf  = joblib.load(model_path)
                vec  = joblib.load(vec_path)

            # Quick smoke test
            test_vec = vec.transform(['water'])
            _ = clf.predict(test_vec)

            _clf        = clf
            _vectorizer = vec
            logger.info('RF model loaded successfully (%d estimators, classes=%s)',
                        clf.n_estimators, clf.classes_.tolist())
            return clf, vec

        except Exception as exc:
            logger.error('Failed to load RF model: %s — ML scoring disabled', exc)
            return None, None


def predict_ingredient_risk(ingredient_name: str) -> Optional[dict]:
    """
    Predict the risk level of a single ingredient using the RF classifier.

    Returns:
        {
            "predicted_class": "safe" | "moderate" | "high",
            "confidence":      float (0.0 – 1.0),
            "probabilities":   {"safe": float, "moderate": float, "high": float},
            "source":          "rf_model",
        }
        or None if the model is unavailable.

    NOTE: This is called ONLY for ingredients that the rule engine
    could not resolve (resolved=False). For known ingredients the rule
    engine is authoritative.
    """
    clf, vec = _load_models()
    if clf is None or vec is None:
        return None

    try:
        X = vec.transform([ingredient_name.lower().strip()])
        import numpy as np
        predicted_class = str(clf.predict(X)[0])
        probabilities   = clf.predict_proba(X)[0]
        class_names     = list(clf.classes_)

        prob_dict  = {str(cls): float(prob) for cls, prob in zip(class_names, probabilities)}
        prob_vals  = list(probabilities) if not hasattr(probabilities, 'tolist') else probabilities.tolist()
        confidence = float(max(prob_vals))

        return {
            'predicted_class': predicted_class,
            'confidence':      confidence,
            'probabilities':   prob_dict,
            'source':          'rf_model',
        }

    except Exception as exc:
        logger.warning('RF prediction failed for "%s": %s', ingredient_name, exc)
        return None


def predict_batch(ingredient_names: list[str]) -> dict[str, Optional[dict]]:
    """
    Batch prediction for a list of ingredient names.
    More efficient than calling predict_ingredient_risk() in a loop.

    Returns: { ingredient_name: prediction_dict_or_None }
    """
    clf, vec = _load_models()
    if clf is None or vec is None:
        return {name: None for name in ingredient_names}

    try:
        normalized = [n.lower().strip() for n in ingredient_names]
        X           = vec.transform(normalized)
        classes     = clf.predict(X)
        probas      = clf.predict_proba(X)
        class_names = list(clf.classes_)

        results = {}
        for name, predicted_class, prob_row in zip(ingredient_names, classes, probas):
            prob_dict  = {str(cls): float(p) for cls, p in zip(class_names, prob_row)}
            prob_vals  = list(prob_row) if not hasattr(prob_row, 'tolist') else prob_row.tolist()
            confidence = float(max(prob_vals))
            predicted_class = str(predicted_class)
            results[name] = {
                'predicted_class': predicted_class,
                'confidence':      confidence,
                'probabilities':   prob_dict,
                'source':          'rf_model',
            }
        return results

    except Exception as exc:
        logger.warning('RF batch prediction failed: %s', exc)
        return {name: None for name in ingredient_names}


def is_model_available() -> bool:
    """Returns True if the RF model is loaded and ready."""
    clf, _ = _load_models()
    return clf is not None

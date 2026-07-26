"""
tests/test_ml_model.py
=======================
Unit tests for scanner/ml_model.py.
Tests the singleton pattern, graceful fallback, and prediction behaviour.
Does NOT load the real model (too slow for unit tests — use @pytest.mark.slow for that).
"""
import pytest
from unittest.mock import patch, MagicMock

pytestmark = pytest.mark.unit


class TestMlModelLoader:

    def test_returns_none_when_model_files_missing(self):
        """When model files don't exist, should return None gracefully."""
        import scanner.ml_model as ml
        # Reset singleton state
        original_clf, original_vec, original_attempted = ml._clf, ml._vectorizer, ml._load_attempted
        ml._clf = None; ml._vectorizer = None; ml._load_attempted = False

        try:
            with patch('pathlib.Path.exists', return_value=False):
                clf, vec = ml._load_models()
                assert clf is None
                assert vec is None
        finally:
            ml._clf = original_clf
            ml._vectorizer = original_vec
            ml._load_attempted = original_attempted

    def test_predict_returns_none_when_model_unavailable(self):
        """predict_ingredient_risk() returns None gracefully when model not loaded."""
        import scanner.ml_model as ml

        with patch.object(ml, '_load_models', return_value=(None, None)):
            # Reset attempted flag
            ml._load_attempted = False
            result = ml.predict_ingredient_risk('some ingredient')
            assert result is None

    def test_predict_batch_returns_none_dict_when_unavailable(self):
        import scanner.ml_model as ml
        with patch.object(ml, '_load_models', return_value=(None, None)):
            ml._load_attempted = False
            names = ['ingredient_a', 'ingredient_b']
            result = ml.predict_batch(names)
            assert all(v is None for v in result.values())
            assert set(result.keys()) == set(names)

    def test_is_model_available_false_when_no_model(self):
        import scanner.ml_model as ml
        with patch.object(ml, '_load_models', return_value=(None, None)):
            ml._load_attempted = False
            assert ml.is_model_available() is False

    def test_singleton_loads_once(self):
        """_load_models should only call joblib.load once per process."""
        import scanner.ml_model as ml

        mock_clf = MagicMock()
        mock_clf.classes_ = ['safe', 'moderate', 'high']
        mock_vec = MagicMock()
        mock_vec.transform.return_value = MagicMock()
        mock_clf.predict.return_value = ['safe']

        ml._clf = None; ml._vectorizer = None; ml._load_attempted = False

        with patch('joblib.load', side_effect=[mock_clf, mock_vec]) as mock_load:
            with patch('pathlib.Path.exists', return_value=True):
                # Call twice — should only load once
                ml._load_models()
                ml._load_models()
                assert mock_load.call_count == 2   # once for clf, once for vec

    def test_predict_returns_structured_dict(self):
        """When model is available, prediction has correct structure."""
        import scanner.ml_model as ml
        import numpy as np

        mock_clf = MagicMock()
        mock_clf.classes_ = ['high', 'moderate', 'safe']
        import numpy as np
        mock_clf.predict.return_value = np.array(['moderate'])
        mock_clf.predict_proba.return_value = np.array([[0.1, 0.8, 0.1]])

        mock_vec = MagicMock()
        mock_vec.transform.return_value = MagicMock()

        ml._clf = None; ml._vectorizer = None; ml._load_attempted = False

        with patch.object(ml, '_load_models', return_value=(mock_clf, mock_vec)):
            ml._load_attempted = True; ml._clf = mock_clf; ml._vectorizer = mock_vec
            result = ml.predict_ingredient_risk('test ingredient')

            assert result is not None
            assert 'predicted_class' in result
            assert 'confidence' in result
            assert 'probabilities' in result
            assert 'source' in result
            assert result['source'] == 'rf_model'
            assert result['predicted_class'] == 'moderate'
            assert abs(result['confidence'] - 0.8) < 0.01


@pytest.mark.slow
class TestMlModelReal:
    """Tests that load the actual model files — mark as slow."""

    def test_real_model_loads_and_predicts(self):
        """Integration test: loads the real pkl files if present."""
        import scanner.ml_model as ml
        ml._clf = None; ml._vectorizer = None; ml._load_attempted = False

        clf, vec = ml._load_models()
        if clf is None:
            pytest.skip('Model files not present — run: python manage.py train_rf_model')

        result = ml.predict_ingredient_risk('sodium lauryl sulfate')
        assert result is not None
        assert result['predicted_class'] in ('safe', 'moderate', 'high')
        assert 0.0 <= result['confidence'] <= 1.0

    def test_batch_prediction_consistent(self):
        """Batch prediction should give same results as individual."""
        import scanner.ml_model as ml
        ml._clf = None; ml._vectorizer = None; ml._load_attempted = False

        if not ml.is_model_available():
            pytest.skip('Model files not present')

        names = ['water', 'fragrance', 'methylparaben']
        batch = ml.predict_batch(names)
        for name in names:
            individual = ml.predict_ingredient_risk(name)
            if individual is not None and batch[name] is not None:
                assert batch[name]['predicted_class'] == individual['predicted_class']

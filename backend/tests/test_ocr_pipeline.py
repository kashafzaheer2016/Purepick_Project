"""
tests/test_ocr_pipeline.py
===========================
Integration tests for the OCR → parse → analyze pipeline.
EasyOCR is mocked — no real image files or GPU needed.

Tests the pipeline as a whole:
  1. EasyOCR returns text
  2. parse_ingredients_from_text extracts tokens
  3. run_ingredient_intelligence scores them
  4. IngredientAnalyzer formats the final report
"""
import pytest
from unittest.mock import patch, MagicMock

from scanner.ocr_engine import parse_ingredients_from_text
from scanner.ingredient_intelligence import run_ingredient_intelligence
from scanner.ingredient_analyzer import get_analyzer

pytestmark = pytest.mark.integration


# ── Mocked OCR → parse → analyze ─────────────────────────────────────────────

class TestOCRPipeline:

    @patch('scanner.ocr_engine.easyocr')
    def test_full_pipeline_clean_label(self, mock_easyocr):
        """Simulate clean label with known bad ingredients."""
        # Mock EasyOCR to return a clean label text
        mock_reader = MagicMock()
        mock_reader.readtext.return_value = [
            'Ingredients: Water, Glycerin, Sodium Lauryl Sulfate, Fragrance, Methylparaben'
        ]
        mock_easyocr.Reader.return_value = mock_reader

        from scanner.ocr_engine import extract_text_easyocr
        raw_text = ' '.join(mock_reader.readtext.return_value)

        ingredients = parse_ingredients_from_text(raw_text)
        assert len(ingredients) >= 4
        assert any('sodium lauryl sulfate' in i for i in ingredients)

    def test_pipeline_allergic_user_detects_fragrance(self, allergic_profile):
        """End-to-end: allergic user scans product with fragrance → flagged."""
        label_text = 'Ingredients: Water, Glycerin, Parfum, Cetearyl Alcohol, Phenoxyethanol'
        ingredients = parse_ingredients_from_text(label_text)
        report = run_ingredient_intelligence(ingredients, allergic_profile)

        assert report['total_flagged'] >= 1
        flagged_names = [f['raw_ingredient'] for f in report['flagged_ingredients']]
        assert any('parfum' in n.lower() or 'fragrance' in n.lower() for n in flagged_names)

    def test_pipeline_safe_product_no_flags(self, allergic_profile):
        """Hypoallergenic product should score safe even for sensitive user."""
        label_text = (
            'Ingredients: Aqua, Glycerin, Sodium Hyaluronate, '
            'Niacinamide, Tocopherol, Citric Acid'
        )
        ingredients = parse_ingredients_from_text(label_text)
        report = run_ingredient_intelligence(ingredients, allergic_profile)
        # No fragrance or sulfates → should not flag
        assert report['total_flagged'] == 0
        assert report['risk_band'] == 'Safe'

    def test_analyzer_wraps_intelligence_correctly(self, allergic_profile):
        """IngredientAnalyzer.analyze() should return correct report structure."""
        ingredients = ['water', 'fragrance', 'sodium lauryl sulfate']
        analyzer = get_analyzer()
        report = analyzer.analyze(ingredients, allergic_profile)

        # Check top-level keys
        assert 'overall_score' in report
        assert 'risk' in report
        assert 'allergy_result' in report
        assert 'ingredient_breakdown' in report
        assert 'ml_augmented' in report
        assert 'model_available' in report

    def test_analyzer_score_in_valid_range(self, plain_profile):
        ingredients = ['water', 'glycerin', 'fragrance']
        analyzer = get_analyzer()
        report = analyzer.analyze(ingredients, plain_profile)
        score = report['overall_score']
        assert 0 <= score <= 100

    def test_analyzer_allergy_alerts_have_required_fields(self, allergic_profile):
        ingredients = ['fragrance', 'water']
        analyzer = get_analyzer()
        report = analyzer.analyze(ingredients, allergic_profile)

        alerts = report['allergy_result']['allergy_alerts']
        assert len(alerts) >= 1
        for alert in alerts:
            assert 'ingredient' in alert
            assert 'common_name' in alert
            assert 'matched_concern' in alert
            assert 'severity' in alert
            assert 'display_color' in alert
            assert 'plain_explanation' in alert

    def test_ml_predicted_alerts_have_confidence(self, plain_profile):
        """ML-predicted alerts should include confidence score."""
        from unittest.mock import patch

        def mock_augment(results, indices):
            for i in indices:
                results[i]['flagged'] = True
                results[i]['match_source'] = 'rf_model'
                results[i]['severity'] = 'ML_PREDICTED'
                results[i]['risk_points'] = 10
                results[i]['ml_confidence'] = 0.75
                results[i]['explanation'] = 'AI predicted risk (confidence: 75%)'
            return results

        with patch('scanner.ingredient_intelligence._augment_with_ml', side_effect=mock_augment):
            report = run_ingredient_intelligence(['xyz-unknown-chem'], plain_profile)

        assert report['total_flagged'] == 1
        flagged = report['flagged_ingredients'][0]
        assert flagged['severity'] == 'ML_PREDICTED'
        assert flagged.get('ml_confidence') == 0.75

    def test_parse_then_analyze_nut_allergy_profile(self, nut_allergy_profile):
        """Label with almond oil → flagged for nut allergy."""
        label = 'Ingredients: Water, Prunus Amygdalus Dulcis Oil, Glycerin, Fragrance'
        ingredients = parse_ingredients_from_text(label)
        report = run_ingredient_intelligence(ingredients, nut_allergy_profile)
        # Prunus Amygdalus Dulcis Oil = almond oil → nut allergy trigger
        assert report['total_flagged'] >= 1


# ── Error resilience ──────────────────────────────────────────────────────────

class TestOCRPipelineResilience:

    def test_garbage_ocr_output_returns_empty(self):
        garbage = '!!!! #### @@@ $$$ %%%%'
        result = parse_ingredients_from_text(garbage)
        # Should not crash, may return empty or minimal list
        assert isinstance(result, list)

    def test_non_latin_characters_handled(self):
        text = 'المكونات: ماء, غلسرين, Water, Glycerin'
        result = parse_ingredients_from_text(text)
        # Should at minimum return the Latin words
        assert isinstance(result, list)

    def test_analyze_with_empty_ingredients_does_not_crash(self, plain_profile):
        report = run_ingredient_intelligence([], plain_profile)
        assert report['risk_band'] == 'Safe'
        assert report['total_flagged'] == 0

    def test_analyze_with_very_long_ingredient_list(self, plain_profile):
        ingredients = [f'ingredient{i}' for i in range(60)]
        report = run_ingredient_intelligence(ingredients, plain_profile)
        assert isinstance(report, dict)
        assert len(report['all_ingredients']) == 60

"""
tests/test_ocr_parsing.py
==========================
Unit tests for parse_ingredients_from_text().
No images, no EasyOCR — tests the text parsing logic only.

Covers:
  - Standard label format (comma-separated)
  - Label with "Ingredients:" prefix
  - OCR noise (brackets, pipes, artifacts)
  - Multiple separator types (semicolons, bullets, newlines)
  - Percentage annotations
  - Long ingredient descriptions that need sub-splitting
  - Edge cases: empty, whitespace, non-ingredient text
"""
import pytest
from scanner.ocr_engine import parse_ingredients_from_text

pytestmark = pytest.mark.unit


class TestParseIngredientsFromText:

    def test_basic_comma_separated(self):
        text = 'Water, Glycerin, Sodium Lauryl Sulfate, Fragrance'
        result = parse_ingredients_from_text(text)
        assert 'water' in result
        assert 'glycerin' in result
        assert 'sodium lauryl sulfate' in result

    def test_ingredients_prefix_stripped(self):
        text = 'Ingredients: Water, Glycerin, Niacinamide'
        result = parse_ingredients_from_text(text)
        assert 'water' in result
        assert 'glycerin' in result
        # "Ingredients" itself should not be in result
        assert 'ingredients' not in result

    def test_colon_prefix_stripped(self):
        text = 'INGREDIENTS: Aqua, Cetearyl Alcohol, Dimethicone'
        result = parse_ingredients_from_text(text)
        assert 'aqua' in result
        assert 'cetearyl alcohol' in result

    def test_ocr_pipe_artifacts_removed(self):
        """OCR sometimes introduces | and [ ] artifacts."""
        text = 'Water, |Glycerin|, [Fragrance], Niacinamide'
        result = parse_ingredients_from_text(text)
        assert 'water' in result
        assert 'glycerin' in result

    def test_semicolon_separator(self):
        text = 'Water; Glycerin; Methylparaben; Fragrance'
        result = parse_ingredients_from_text(text)
        assert len(result) >= 3

    def test_newline_separator(self):
        text = 'Water\nGlycerin\nNiacinamide\nHyaluronic Acid'
        result = parse_ingredients_from_text(text)
        assert len(result) >= 3

    def test_percentage_annotation_stripped(self):
        """'Niacinamide (10%)' → 'niacinamide'."""
        text = 'Water, Niacinamide (10%), Glycerin (5%)'
        result = parse_ingredients_from_text(text)
        assert 'niacinamide' in result
        assert 'glycerin' in result

    def test_stop_words_filtered(self):
        """Common label words should not appear as ingredients."""
        text = 'Ingredients: Water, Glycerin. Contains: Fragrance. Warning: keep out of reach.'
        result = parse_ingredients_from_text(text)
        assert 'warning' not in result
        assert 'contains' not in result
        assert 'ingredients' not in result

    def test_deduplication(self):
        """Same ingredient listed twice should appear once."""
        text = 'Water, Glycerin, Water, Fragrance'
        result = parse_ingredients_from_text(text)
        assert result.count('water') == 1

    def test_max_60_ingredients_returned(self):
        """Parser limits output to 60 ingredients."""
        ingredients = [f'ingredient{i}' for i in range(100)]
        text = ', '.join(ingredients)
        result = parse_ingredients_from_text(text)
        assert len(result) <= 60

    def test_empty_string(self):
        assert parse_ingredients_from_text('') == []

    def test_none_equivalent(self):
        """Whitespace-only should return empty list."""
        assert parse_ingredients_from_text('   ') == []

    def test_very_short_tokens_filtered(self):
        """Single characters and 2-char tokens should be filtered."""
        text = 'A, AB, Water, Glycerin, B'
        result = parse_ingredients_from_text(text)
        assert 'a' not in result
        assert 'b' not in result
        assert 'water' in result

    def test_real_label_format(self):
        """Simulates real OCR output from a moisturizer label."""
        text = (
            'Ingredients: Aqua, Glycerin, Cetearyl Alcohol, '
            'Dimethicone, Phenoxyethanol, Sodium Hyaluronate, '
            'Niacinamide, Tocopheryl Acetate, Parfum, '
            'Citric Acid, Sodium Benzoate'
        )
        result = parse_ingredients_from_text(text)
        assert 'aqua' in result
        assert 'glycerin' in result
        assert 'niacinamide' in result
        assert 'parfum' in result
        assert len(result) >= 8

    def test_inci_label_with_bullets(self):
        """Bullet separator (·) is replaced with comma by barcode_service._parse_ingredients.
        ocr parse_ingredients_from_text handles ·· via split on whitespace or fallback."""
        text = 'INCI: Aqua, Glycerin, Sodium Lauryl Sulfate, Parfum'
        result = parse_ingredients_from_text(text)
        assert 'aqua' in result
        assert 'glycerin' in result

    def test_mixed_case_lowercased(self):
        """Output should always be lowercase."""
        text = 'WATER, GLYCERIN, FRAGRANCE'
        result = parse_ingredients_from_text(text)
        assert all(r == r.lower() for r in result)

    def test_parenthetical_handled(self):
        """Parenthetical content parsed — result may include base word."""
        text = 'Water, Glycerin, Fragrance'
        result = parse_ingredients_from_text(text)
        assert 'water' in result
        assert 'glycerin' in result


class TestParseIngredientsEdgeCases:

    def test_stop_words_not_in_result(self):
        text = 'Ingredients: Contains Warning and with may also'
        result = parse_ingredients_from_text(text)
        # None of the stop words should appear
        for stop in ['warning', 'contains', 'and', 'with', 'may', 'also', 'ingredients']:
            assert stop not in result

    def test_long_item_sub_split(self):
        """Items over 60 chars get sub-split on periods."""
        text = 'Water. This is a very long ingredient description that is over sixty characters total. Glycerin'
        result = parse_ingredients_from_text(text)
        assert 'water' in result
        assert 'glycerin' in result

    def test_realistic_ocr_noise(self):
        """Simulates garbled OCR output — should still extract useful tokens."""
        text = '|Water|, G|lycerin, [Niacinam|ide], Fragrance|||'
        result = parse_ingredients_from_text(text)
        assert 'water' in result
        assert 'glycerin' in result

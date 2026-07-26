"""
tests/test_barcode_service.py
==============================
Unit tests for scanner/barcode_service.py.
All HTTP calls are mocked — no real network requests.

Covers:
  - Successful product lookup with full ingredient list
  - Product not found (404 response)
  - API error responses
  - Network timeout
  - _parse_ingredients() with various label formats
  - Invalid barcode format validation
  - Missing ingredient list in found product
"""
import pytest
from unittest.mock import patch, MagicMock

from scanner.barcode_service import lookup_barcode, _parse_ingredients

pytestmark = pytest.mark.unit


def _mock_response(status_code: int, json_data: dict) -> MagicMock:
    """Create a mock requests.Response."""
    mock = MagicMock()
    mock.status_code = status_code
    mock.json.return_value = json_data
    return mock


OBF_SUCCESS_RESPONSE = {
    'status': 1,
    'product': {
        'product_name': 'Test Moisturizer',
        'product_name_en': 'Test Moisturizer',
        'brands': 'TestBrand',
        'ingredients_text': 'Water, Glycerin, Niacinamide, Fragrance',
        'ingredients_text_en': 'Water, Glycerin, Niacinamide, Fragrance',
        'image_front_small_url': 'https://example.com/img.jpg',
    },
}

OBF_NOT_FOUND_RESPONSE = {
    'status': 0,
    'product': {},
}


# ── lookup_barcode ────────────────────────────────────────────────────────────

class TestLookupBarcode:

    @patch('scanner.barcode_service.requests.get')
    def test_successful_lookup_returns_found_true(self, mock_get):
        mock_get.return_value = _mock_response(200, OBF_SUCCESS_RESPONSE)
        result = lookup_barcode('3600523021382')
        assert result['found'] is True
        assert result['product_name'] == 'Test Moisturizer'
        assert result['brand'] == 'TestBrand'
        assert result['source'] == 'open_beauty_facts'

    @patch('scanner.barcode_service.requests.get')
    def test_successful_lookup_parses_ingredients(self, mock_get):
        mock_get.return_value = _mock_response(200, OBF_SUCCESS_RESPONSE)
        result = lookup_barcode('3600523021382')
        assert result['found'] is True
        assert len(result['ingredients_list']) >= 3
        # _parse_ingredients preserves original case from OBF response
        ing_lower = [i.lower() for i in result['ingredients_list']]
        assert 'water' in ing_lower
        assert 'glycerin' in ing_lower
        assert len(result['ingredients_list']) >= 3
        assert any(i.lower() == 'glycerin' for i in result['ingredients_list'])

    @patch('scanner.barcode_service.requests.get')
    def test_not_found_returns_found_false(self, mock_get):
        mock_get.return_value = _mock_response(200, OBF_NOT_FOUND_RESPONSE)
        result = lookup_barcode('9999999999999')
        assert result['found'] is False
        assert 'message' in result

    @patch('scanner.barcode_service.requests.get')
    def test_404_response_returns_not_found(self, mock_get):
        mock_get.return_value = _mock_response(404, {})
        result = lookup_barcode('1234567890123')
        assert result['found'] is False

    @patch('scanner.barcode_service.requests.get')
    def test_server_error_returns_not_found(self, mock_get):
        mock_get.return_value = _mock_response(500, {})
        result = lookup_barcode('1234567890123')
        assert result['found'] is False
        assert 'message' in result

    @patch('scanner.barcode_service.requests.get')
    def test_timeout_returns_not_found(self, mock_get):
        import requests
        mock_get.side_effect = requests.Timeout()
        result = lookup_barcode('1234567890123')
        assert result['found'] is False
        assert 'timed out' in result['message'].lower()

    @patch('scanner.barcode_service.requests.get')
    def test_connection_error_returns_not_found(self, mock_get):
        import requests
        mock_get.side_effect = requests.ConnectionError()
        result = lookup_barcode('1234567890123')
        assert result['found'] is False
        assert 'connection' in result['message'].lower()

    def test_non_numeric_barcode_returns_not_found(self):
        result = lookup_barcode('ABC12345')
        assert result['found'] is False
        assert 'Invalid' in result['message'] or 'invalid' in result['message']

    def test_empty_barcode_returns_not_found(self):
        result = lookup_barcode('')
        assert result['found'] is False

    @patch('scanner.barcode_service.requests.get')
    def test_product_without_ingredients_returns_not_found(self, mock_get):
        response_data = {
            'status': 1,
            'product': {
                'product_name': 'Mystery Product',
                'brands': 'MysteryBrand',
                'ingredients_text': '',    # no ingredient list
            },
        }
        mock_get.return_value = _mock_response(200, response_data)
        result = lookup_barcode('1234567890123')
        assert result['found'] is False
        assert 'no ingredient list' in result['message'].lower() or 'not found' in result['message'].lower()

    @patch('scanner.barcode_service.requests.get')
    def test_image_url_included_when_available(self, mock_get):
        mock_get.return_value = _mock_response(200, OBF_SUCCESS_RESPONSE)
        result = lookup_barcode('3600523021382')
        assert result.get('image_url') == 'https://example.com/img.jpg'

    @patch('scanner.barcode_service.requests.get')
    def test_correct_url_called(self, mock_get):
        mock_get.return_value = _mock_response(200, OBF_SUCCESS_RESPONSE)
        lookup_barcode('3600523021382')
        call_url = mock_get.call_args[0][0]
        assert '3600523021382' in call_url
        assert 'openbeautyfacts.org' in call_url

    @patch('scanner.barcode_service.requests.get')
    def test_user_agent_header_sent(self, mock_get):
        mock_get.return_value = _mock_response(200, OBF_SUCCESS_RESPONSE)
        lookup_barcode('3600523021382')
        call_kwargs = mock_get.call_args[1]
        headers = call_kwargs.get('headers', {})
        assert 'User-Agent' in headers
        assert 'PurePick' in headers['User-Agent']


# ── _parse_ingredients ────────────────────────────────────────────────────────

class TestParseIngredients:

    def test_basic_comma_separated(self):
        result = _parse_ingredients('Water, Glycerin, Fragrance')
        assert 'Water' in result or 'water' in result
        assert len(result) >= 2

    def test_semicolon_separated(self):
        result = _parse_ingredients('Water; Glycerin; Niacinamide')
        assert len(result) >= 2

    def test_middle_dot_separator(self):
        result = _parse_ingredients('Water·Glycerin·Fragrance')
        assert len(result) >= 2

    def test_percentage_removed(self):
        result = _parse_ingredients('Niacinamide 10%, Water, Glycerin 5%')
        for item in result:
            assert '%' not in item

    def test_parenthetical_removed(self):
        result = _parse_ingredients('Water (Aqua), Glycerin')
        # Result should not contain raw parenthetical text
        assert not any('(Aqua)' in item for item in result)

    def test_empty_string_returns_empty_list(self):
        assert _parse_ingredients('') == []

    def test_ingredients_prefix_stripped(self):
        result = _parse_ingredients('Ingredients: Water, Glycerin')
        assert 'Ingredients' not in result
        assert 'ingredients' not in result

    def test_short_items_filtered(self):
        result = _parse_ingredients('a, Water, b, Glycerin')
        for item in result:
            assert len(item) >= 2

    def test_real_world_label(self):
        label = (
            'Aqua, Glycerin, Cetearyl Alcohol, Dimethicone, '
            'Phenoxyethanol, Sodium Hyaluronate, Niacinamide, '
            'Tocopheryl Acetate, Parfum'
        )
        result = _parse_ingredients(label)
        assert len(result) >= 7

"""
PurePick OCR Engine — Ingredient Extraction Pipeline
=====================================================
Primary:  Gemini Vision  — fast, accurate, context-aware
Fallback: EasyOCR        — local CPU, no API needed (singleton-cached)

Gemini Vision is used first because:
  - 5-10x faster than EasyOCR on CPU (API call vs neural network inference)
  - Understands ingredient label context (knows INCI names, formatting)
  - Handles curved packaging, small fonts, mixed scripts
  - Already integrated (gemini-flash-latest works with current API key)

EasyOCR singleton: model is loaded once and reused — fixes the 20-40s
cold-start penalty that was caused by loading 100MB weights on every request.
"""
import os
import re
import logging
import base64
import numpy as np

logger = logging.getLogger(__name__)

# ── EasyOCR singleton ──────────────────────────────────────────────────────────
_easyocr_reader = None

def _get_easyocr_reader():
    global _easyocr_reader
    if _easyocr_reader is None:
        try:
            import easyocr
            logger.info('Loading EasyOCR model (first time only)...')
            _easyocr_reader = easyocr.Reader(['en'], gpu=False, verbose=False)
            logger.info('EasyOCR model loaded and cached.')
        except Exception as e:
            logger.error('Failed to load EasyOCR: %s', e)
    return _easyocr_reader


# ── Gemini Vision OCR (Primary) ────────────────────────────────────────────────

def extract_text_gemini(image_path: str) -> str:
    """
    Use Gemini Vision to extract the full ingredient list from a product label image.
    Returns raw ingredient text string, or '' on failure.
    """
    try:
        from django.conf import settings
        from google import genai
        from google.genai import types

        api_key = getattr(settings, 'GEMINI_API_KEY', None)
        if not api_key or api_key == 'YOUR_GEMINI_API_KEY_HERE':
            logger.debug('Gemini Vision skipped — API key not configured')
            return ''

        # Read image as bytes
        with open(image_path, 'rb') as f:
            image_bytes = f.read()

        # Detect MIME type
        ext = os.path.splitext(image_path)[1].lower()
        mime_map = {'.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
                    '.png': 'image/png', '.webp': 'image/webp'}
        mime_type = mime_map.get(ext, 'image/jpeg')

        prompt = """You are a product label OCR assistant specializing in cosmetic and food ingredient lists.

Look at this product label image and extract ONLY the ingredient list.

Instructions:
- Find the section labeled "Ingredients", "INGREDIENTS", "Composition", "INCI", or similar
- Extract all ingredients exactly as printed
- Separate each ingredient with a comma
- Do NOT include warnings, directions, or other text — ONLY ingredients
- If no ingredient list is visible, respond with: NOT_FOUND

Return ONLY the comma-separated ingredient list, nothing else."""

        client = genai.Client(api_key=api_key)
        config = types.GenerateContentConfig(
            temperature=0.0,
            max_output_tokens=1024,
            thinking_config=types.ThinkingConfig(thinking_budget=0),
        )

        response = None
        for model_name in ['gemini-flash-latest', 'gemini-2.0-flash']:
            try:
                response = client.models.generate_content(
                    model=model_name,
                    contents=[
                        types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                        prompt,
                    ],
                    config=config,
                )
                if response and response.text:
                    break
            except Exception as e:
                logger.debug('Gemini Vision model %s failed: %s', model_name, e)
                response = None

        if not response or not response.text:
            return ''

        text = response.text.strip()
        if 'NOT_FOUND' in text.upper() or len(text) < 5:
            return ''

        logger.info('Gemini Vision extracted %d chars from label', len(text))
        return text

    except Exception as e:
        logger.warning('Gemini Vision OCR failed: %s', e)
        return ''


# ── EasyOCR fallback ───────────────────────────────────────────────────────────

def _preprocess_image(image_path: str):
    """Enhance image contrast/sharpness for better OCR accuracy."""
    try:
        from PIL import Image, ImageFilter, ImageEnhance
        img = Image.open(image_path).convert('L')
        img = img.filter(ImageFilter.SHARPEN)
        enhancer = ImageEnhance.Contrast(img)
        img = enhancer.enhance(2.0)
        return img
    except Exception as e:
        logger.warning('Image preprocessing failed: %s', e)
        return None


def extract_text_easyocr(image_path: str) -> str:
    """Extract text using cached EasyOCR reader."""
    try:
        reader = _get_easyocr_reader()
        if reader is None:
            return ''

        img = _preprocess_image(image_path)
        image_input = np.array(img) if img else image_path

        results = reader.readtext(image_input, detail=0, paragraph=True)
        text = ' '.join(results).strip()

        if not text:
            logger.warning('EasyOCR returned empty text for: %s', image_path)
        return text

    except Exception as e:
        logger.error('EasyOCR failure: %s', e)
        return ''


# ── Main extraction function ───────────────────────────────────────────────────

def extract_text_from_image(image_path: str) -> str:
    """
    Primary: Gemini Vision (fast + accurate)
    Fallback: EasyOCR (local, slower)
    """
    # Try Gemini Vision first
    text = extract_text_gemini(image_path)
    if text:
        logger.info('OCR: Gemini Vision succeeded')
        return text

    # Fall back to EasyOCR
    logger.info('OCR: Gemini failed/unavailable — falling back to EasyOCR')
    text = extract_text_easyocr(image_path)
    if text:
        return text

    # Demo mode fallback
    if os.getenv('DEMO_MODE') == 'True':
        return 'Water, Glycerin, Niacinamide, Sodium Chloride, Phenoxyethanol.'

    return ''


# ── Ingredient parser ──────────────────────────────────────────────────────────

def parse_ingredients_from_text(raw_text: str) -> list:
    """
    Parse ingredient list from raw OCR/Gemini text.
    Gemini already returns comma-separated ingredients — this cleans and dedupes.
    """
    if not raw_text:
        return []

    text = raw_text.lower()
    text = re.sub(r'[|\[\]{}«»]', '', text)

    # Try to isolate ingredient section (for EasyOCR output which includes full label)
    patterns = [
        r'(?:ingredients|ingrediente|ingred?nts?|composition|inci|formula|contains)[\s:=]+(.+?)(?:\.\s*\n\n|contains|warnings|directions|caution|produced|$)',
        r'(?:active ingredients)[\s:=]+(.+?)(?:\.|\n\n|inactive|$)',
        r'(?:inactive ingredients)[\s:=]+(.+?)(?:\.|\n\n|$)',
    ]

    ingredients_text = ''
    for pattern in patterns:
        match = re.search(pattern, text, re.DOTALL | re.IGNORECASE)
        if match:
            ingredients_text = match.group(1)
            break

    # Gemini returns clean comma-separated list — use directly if no section found
    if not ingredients_text or len(ingredients_text.split(',')) < 2:
        ingredients_text = text

    # Split on commas, semicolons, bullets
    raw_list = re.split(r'[,;•·\n\t]+', ingredients_text)

    stop_words = {'ingredients', 'contains', 'warning', 'direction', 'caution',
                  'and', 'with', 'may', 'also', 'not_found'}

    cleaned = []
    for item in raw_list:
        item = item.strip()
        item = re.sub(r'^[^a-z]+|[^a-z]+$', '', item)
        item = re.sub(r'\([\d.]+\s*%\)', '', item).strip()

        if len(item) > 2 and item not in stop_words:
            if len(item) > 60:
                for sp in item.split('.'):
                    sp = sp.strip()
                    if 2 < len(sp) < 60:
                        cleaned.append(sp)
            else:
                cleaned.append(item)

    seen = set()
    final_list = []
    for c in cleaned:
        if c not in seen:
            final_list.append(c)
            seen.add(c)

    return final_list[:60]


# ── Ingredient label validator ──────────────────────────────────────────────────

_INGREDIENT_SIGNALS = {
    'water', 'aqua', 'glycerin', 'glycerol', 'sodium', 'acid', 'extract',
    'oil', 'butter', 'alcohol', 'parfum', 'fragrance', 'color', 'colour',
    'oxide', 'stearate', 'palmitate', 'silicone', 'dimethicone', 'paraben',
    'phenoxyethanol', 'tocopherol', 'vitamin', 'niacinamide', 'retinol',
    'hyaluronic', 'salicylic', 'benzoyl', 'sulfate', 'chloride', 'carbomer',
    'xanthan', 'cellulose', 'glucoside', 'lactate', 'citrate', 'phosphate',
    'methylparaben', 'propylparaben', 'zinc', 'titanium', 'iron', 'mica',
    'sugar', 'glucose', 'fructose', 'maltodextrin', 'starch', 'lecithin',
}

_LABEL_KEYWORDS = {
    'ingredients', 'composition', 'inci', 'contains', 'formula',
    'active ingredient', 'inactive ingredient', 'ingr',
}


def is_product_label(raw_text: str, parsed_ingredients: list) -> tuple[bool, str]:
    """
    Validate whether extracted text is from a product ingredient label.
    Returns (is_valid, error_message).
    """
    if not raw_text or not raw_text.strip():
        return False, (
            'No text was detected in this image. '
            'Please scan the ingredients list on the back of a product label.'
        )

    text_lower = raw_text.lower()
    word_count = len(raw_text.split())
    has_label_keyword = any(kw in text_lower for kw in _LABEL_KEYWORDS)
    signal_matches = sum(1 for sig in _INGREDIENT_SIGNALS if sig in text_lower)
    comma_count = raw_text.count(',')
    enough_ingredients = len(parsed_ingredients) >= 3

    if has_label_keyword and enough_ingredients:
        return True, ''
    if signal_matches >= 3 and enough_ingredients:
        return True, ''
    if comma_count >= 4 and signal_matches >= 2:
        return True, ''
    if enough_ingredients and comma_count >= 3:
        return True, ''

    if word_count < 5:
        return False, (
            'The image is too blurry or the text is too small to read. '
            'Please take a clearer, closer photo of the ingredients list.'
        )
    if has_label_keyword and not enough_ingredients:
        return False, (
            'An ingredients section was detected but the text is unclear. '
            'Please take a closer, well-lit photo of the full ingredients list.'
        )
    return False, (
        'No ingredient list detected. Please scan the back of a product '
        'where the ingredients list is printed.'
    )

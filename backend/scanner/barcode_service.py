"""
scanner/barcode_service.py
==========================
Barcode lookup with smart regional routing + Gemini AI fallback.

Lookup chain:
  Pakistani barcodes (890 prefix):
    Tier 1 — Gemini AI  (knows Pakistani brands well)
    Tier 2 — Open Beauty Facts
    Tier 3 — Open Food Facts

  International barcodes:
    Tier 1 — Open Beauty Facts
    Tier 2 — Open Food Facts
    Tier 3 — Gemini AI

Pakistan GS1 prefix: 890
Common Pakistani brands: Gul Ahmed, Pond's PK, Reckitt PK, Unilever PK,
Ariel PK, Safeguard, Lifebuoy, Surf Excel, Mezan, Olper's, Tarang, Nurpur etc.
"""
from __future__ import annotations

import logging
import re
from typing import Optional

import requests

logger = logging.getLogger(__name__)

_OBF_BASE_URL    = 'https://world.openbeautyfacts.org/api/v2/product/{barcode}.json'
_OFF_BASE_URL    = 'https://world.openfoodfacts.org/api/v2/product/{barcode}.json'
_REQUEST_TIMEOUT = 8


def _is_pakistani_barcode(barcode: str) -> bool:
    """Pakistan GS1 country code is 890. EAN-13 barcodes starting with 890 are Pakistani."""
    return barcode.startswith('890')


def _lookup_via_gemini(barcode: str, is_pakistani: bool = False) -> dict:
    """
    Ask Gemini to identify the product by barcode.
    Uses a Pakistan-specific prompt for local products.
    """
    try:
        from django.conf import settings
        from google import genai
        from google.genai import types

        api_key = getattr(settings, 'GEMINI_API_KEY', None)
        if not api_key or api_key == 'YOUR_GEMINI_API_KEY_HERE':
            logger.debug('Gemini barcode lookup skipped — API key not configured')
            return {}

        if is_pakistani:
            prompt = f"""You are a product ingredient lookup assistant specializing in Pakistani consumer products.

A user in Pakistan scanned barcode: {barcode}

This is a Pakistani product (GS1 prefix 890). Common Pakistani brands include:
Unilever Pakistan (Sunsilk, Dove, Clear, Lifebuoy, Lux, Pond's, Rexona, Surf Excel, Comfort),
Procter & Gamble Pakistan (Ariel, Safeguard, Head & Shoulders, Pantene, Rejoice),
Reckitt Pakistan (Dettol, Veet, Harpic, Vanish),
Colgate-Palmolive Pakistan (Colgate, Palmolive, Capri),
Gul Ahmed, Hemani Herbals, BIOXIL, Bio Amla, Saeed Ghani, Medora, Rivaj UK,
English Collection, Sweet Touch, Colors Queen, Christine, Olivia, Golden Pearl,
Fair & Lovely Pakistan, Stillman's, Dr. Fazeela, Zara Cosmetics.

Task: Identify this Pakistani product and return its full ingredient list.

If you recognise this barcode OR the product from it, respond in EXACTLY this format:
PRODUCT_NAME: <full product name>
BRAND: <brand name>
INGREDIENTS: <comma-separated ingredient list>

If you do NOT know this product, respond with exactly: NOT_FOUND

Only return ingredients you are confident about. Do not fabricate."""
        else:
            prompt = f"""You are a product ingredient lookup assistant.

A user scanned barcode: {barcode}

Task: Identify this product and return its full ingredient list.

If you recognise this barcode OR can reliably identify the product, respond in EXACTLY this format:
PRODUCT_NAME: <full product name>
BRAND: <brand name>
INGREDIENTS: <comma-separated ingredient list>

If you do NOT know this product, respond with exactly: NOT_FOUND

Only return ingredients you are confident about. Do not fabricate."""

        client = genai.Client(api_key=api_key)
        gen_config = types.GenerateContentConfig(
            temperature=0.1,
            max_output_tokens=512,
            thinking_config=types.ThinkingConfig(thinking_budget=0),
        )

        response = ''
        for model_name in ['gemini-flash-latest', 'gemini-2.0-flash', 'gemini-2.0-flash-lite']:
            try:
                resp = client.models.generate_content(
                    model=model_name,
                    contents=prompt,
                    config=gen_config,
                )
                response = resp.text.strip() if resp and resp.text else ''
                if response:
                    break
            except Exception as e:
                logger.debug('Gemini model %s barcode lookup failed: %s', model_name, e)
                response = ''

        if not response or 'NOT_FOUND' in response:
            return {}

        # Parse structured response
        product_name     = 'Unknown Product'
        brand            = ''
        ingredients_text = ''

        for line in response.splitlines():
            line = line.strip()
            if line.startswith('PRODUCT_NAME:'):
                product_name = line.split(':', 1)[1].strip()
            elif line.startswith('BRAND:'):
                brand = line.split(':', 1)[1].strip()
            elif line.startswith('INGREDIENTS:'):
                ingredients_text = line.split(':', 1)[1].strip()

        if not ingredients_text:
            return {}

        ingredients_list = _parse_ingredients(ingredients_text)
        if len(ingredients_list) < 3:
            return {}

        logger.info('Barcode %s resolved via Gemini AI: "%s" (%d ingredients)',
                    barcode, product_name, len(ingredients_list))

        return {
            'found':            True,
            'barcode':          barcode,
            'product_name':     product_name,
            'brand':            brand,
            'ingredients_text': ingredients_text,
            'ingredients_list': ingredients_list,
            'image_url':        None,
            'source':           'gemini_knowledge',
            'ai_sourced':       True,
        }

    except Exception as exc:
        logger.debug('Gemini barcode lookup error for %s: %s', barcode, exc)
        return {}


def _lookup_open_beauty_facts(barcode: str) -> dict:
    """Tier lookup via Open Beauty Facts (cosmetics database)."""
    try:
        resp = requests.get(
            _OBF_BASE_URL.format(barcode=barcode),
            timeout=_REQUEST_TIMEOUT,
            headers={'User-Agent': 'PurePick-App/1.0 (contact@purepick.app)'},
        )
        if resp.status_code != 200:
            return {}
        data = resp.json()
        if data.get('status') != 1:
            return {}
        product = data.get('product', {})
        ingredients_text = (
            product.get('ingredients_text_en') or product.get('ingredients_text') or ''
        ).strip()
        ingredients_list = _parse_ingredients(ingredients_text)
        if not ingredients_list:
            return {}
        return {
            'found':            True,
            'barcode':          barcode,
            'product_name':     (product.get('product_name_en') or product.get('product_name') or 'Unknown Product').strip(),
            'brand':            (product.get('brands') or '').strip(),
            'ingredients_text': ingredients_text,
            'ingredients_list': ingredients_list,
            'image_url':        product.get('image_front_small_url'),
            'source':           'open_beauty_facts',
        }
    except Exception as exc:
        logger.debug('OpenBeautyFacts lookup error: %s', exc)
        return {}


def _lookup_open_food_facts(barcode: str) -> dict:
    """Tier lookup via Open Food Facts (food/general products)."""
    try:
        resp = requests.get(
            _OFF_BASE_URL.format(barcode=barcode),
            timeout=_REQUEST_TIMEOUT,
            headers={'User-Agent': 'PurePick-App/1.0 (contact@purepick.app)'},
        )
        if resp.status_code != 200:
            return {}
        data = resp.json()
        if data.get('status') != 1:
            return {}
        product = data.get('product', {})
        ingredients_text = (
            product.get('ingredients_text_en') or product.get('ingredients_text') or ''
        ).strip()
        ingredients_list = _parse_ingredients(ingredients_text)
        if not ingredients_list:
            return {}
        return {
            'found':            True,
            'barcode':          barcode,
            'product_name':     (product.get('product_name_en') or product.get('product_name') or 'Unknown Product').strip(),
            'brand':            (product.get('brands') or '').strip(),
            'ingredients_text': ingredients_text,
            'ingredients_list': ingredients_list,
            'image_url':        product.get('image_front_small_url'),
            'source':           'open_food_facts',
        }
    except Exception as exc:
        logger.debug('OpenFoodFacts lookup error: %s', exc)
        return {}


def lookup_barcode(barcode: str) -> dict:
    """
    Smart barcode lookup with regional routing.

    Pakistani barcodes (890 prefix) → Gemini first (knows local brands)
    International barcodes → databases first, Gemini as final fallback
    """
    if not barcode or not barcode.strip().isdigit():
        return _not_found(
            barcode,
            'This doesn\'t look like a product barcode. '
            'Please scan the numeric barcode on the back or bottom of a product. '
            'QR codes are not supported.'
        )

    barcode = barcode.strip()
    is_pk   = _is_pakistani_barcode(barcode)

    if is_pk:
        # ── Pakistani product: Gemini → OBF → OFF ────────────────────────────
        logger.info('Pakistani barcode %s detected — trying Gemini first', barcode)

        result = _lookup_via_gemini(barcode, is_pakistani=True)
        if result:
            return result

        result = _lookup_open_beauty_facts(barcode)
        if result:
            return result

        result = _lookup_open_food_facts(barcode)
        if result:
            return result

        return _not_found(
            barcode,
            'This Pakistani product wasn\'t found in our databases. '
            'Please scan the ingredient list on the back of the product instead.'
        )

    else:
        # ── International product: OBF → OFF → Gemini ────────────────────────
        logger.info('International barcode %s — trying Open Beauty Facts first', barcode)

        result = _lookup_open_beauty_facts(barcode)
        if result:
            return result

        logger.info('Barcode %s not in OBF — trying Open Food Facts', barcode)
        result = _lookup_open_food_facts(barcode)
        if result:
            return result

        logger.info('Barcode %s not in any DB — trying Gemini AI', barcode)
        result = _lookup_via_gemini(barcode, is_pakistani=False)
        if result:
            return result

        return _not_found(
            barcode,
            'Product not found in any database. '
            'Try scanning the ingredient label on the back of the product instead.'
        )


def _parse_ingredients(raw_text: str) -> list[str]:
    """Parse a raw ingredients string into a clean list."""
    if not raw_text:
        return []

    text = re.sub(r'^ingredients?\s*:\s*', '', raw_text, flags=re.IGNORECASE).strip()
    text = text.replace('·', ',').replace(';', ',')
    text = re.sub(r'\([^)]*\)', '', text)

    parts = [p.strip().rstrip('.').strip() for p in text.split(',')]

    cleaned = []
    for p in parts:
        p = re.sub(r'\d+(\.\d+)?\s*%', '', p).strip()
        if len(p) >= 2:
            cleaned.append(p)

    return cleaned


def _not_found(barcode: str, message: str) -> dict:
    return {
        'found':   False,
        'barcode': barcode or '',
        'message': message,
    }

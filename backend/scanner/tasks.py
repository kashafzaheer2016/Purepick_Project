"""
scanner/tasks.py
================
All CPU-heavy and external-API scanner operations run as Celery tasks.

Task flow for OCR scan:
  HTTP POST /api/scan-label/
      → saves image to temp file
      → enqueues run_ocr_and_analyze.delay(tmp_path, user_id)
      → returns {"task_id": "...", "status": "PENDING"}  ← immediate 202

  Flutter polls GET /api/task/<task_id>/
      → PENDING  → show spinner
      → STARTED  → show "Analyzing..."
      → SUCCESS  → render result
      → FAILURE  → show error

Task flow for Gemini chat:
  HTTP POST /api/chat/
      → enqueues call_gemini_chat.delay(query, user_id)
      → returns task_id immediately

WHY shared_task instead of @app.task:
  shared_task avoids importing the Celery app instance directly,
  which prevents circular imports between celery.py and tasks.py.
"""
from __future__ import annotations

import json
import logging
import os
import tempfile
from datetime import datetime, timezone, timedelta
from typing import Any

from celery import shared_task
from celery.exceptions import SoftTimeLimitExceeded

logger = logging.getLogger(__name__)


# ── OCR + Analysis Task ───────────────────────────────────────────────────────

@shared_task(
    bind=True,
    name='scanner.tasks.run_ocr_and_analyze',
    max_retries=2,
    default_retry_delay=5,
    queue='ml',
)
def run_ocr_and_analyze(self, image_data: str, user_id: int) -> dict[str, Any]:
    """
    Upgraded pipeline with Base64 support for cloud workers.
    """
    import base64
    import tempfile

    # Recreate image from base64 data
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
    tmp.write(base64.b64decode(image_data))
    image_path = tmp.name
    tmp.close()

    try:
        from .ocr_engine import extract_text_from_image, parse_ingredients_from_text
        from .ingredient_analyzer import get_analyzer
        from .utils import save_scan_json
        from purepick_core.models import HealthProfile, ScanRecord

        # Stage 1: OCR (Gemini Vision primary, EasyOCR fallback)
        logger.info('Task %s: starting OCR for user %s', self.request.id, user_id)
        raw_text = extract_text_from_image(image_path)

        if not raw_text:
            return {
                'status': 'error',
                'error': 'no_text_detected',
                'message': 'No text was detected. Please take a clear, well-lit photo of the ingredient label.',
            }

        # Stage 2: Parse ingredient tokens
        # Gemini Vision returns clean text — no correction pass needed
        # EasyOCR output may still benefit from correction (handled by parse logic)
        ingredients = parse_ingredients_from_text(raw_text)

        # Stage 2.5: Validate this is actually a product label
        from .ocr_engine import is_product_label
        is_label, reason = is_product_label(raw_text, ingredients)
        if not is_label:
            return {
                'status': 'error',
                'error': 'not_a_product_label',
                'message': reason,
                'raw_text_preview': raw_text[:200],
            }

        if not ingredients:
            return {
                'status': 'error',
                'error': 'no_ingredients_found',
                'message': (
                    'Ingredients were detected but could not be parsed. '
                    'Please take a clearer photo of the full ingredients list.'
                ),
                'raw_text_preview': raw_text[:200],
            }

        # Stage 3: Load user profile
        user_profile = _load_user_profile(user_id)

        # Stage 4: Run ingredient intelligence
        analyzer = get_analyzer()
        report = analyzer.analyze(ingredients, user_profile=user_profile)

        # Stage 4.5: AI insight — only call Gemini if quota allows, else use rule engine summary
        report['ai_insight'] = _get_rule_based_verdict(ingredients, user_profile, report)

        report['extracted_ingredients'] = ingredients
        report['raw_text_preview'] = raw_text[:300]

        # Stage 5/6: Persist...
        record_id = _persist_scan_record(user_id, report, ingredients, raw_text=raw_text)
        report['scan_id'] = record_id

        # Stage 7: Update Skincare Streak
        _update_user_streak(user_id)

        _safe_delete(image_path)   # delete only after success
        return report
    except Exception as exc:
        logger.exception('OCR Task failed: %s', exc)
        try:
            raise self.retry(exc=exc)   # image still exists for retry
        except self.MaxRetriesExceededError:
            _safe_delete(image_path)    # delete only when all retries exhausted
            return {'status': 'error', 'error': 'Analysis failed. Please try again.'}


# ── Safety Agent Logic ────────────────────────────────────────────────────────

def _fuzzy_ocr_correction(raw_text: str) -> str:
    """[FEATURE A] Review messy OCR and fix typos based on skincare context."""
    prompt = f"""You are the PurePick OCR Correction Agent.
Input is messy text from a scanner. Fix typos and standardize names based on skincare/food context.
Example: "S0dium Chl0ride" -> "Sodium Chloride".
If the text is already clear, return it as is.
ONLY return the corrected text, no conversation.

MESSY TEXT:
{raw_text[:2000]}"""
    try:
        return _call_gemini_api(prompt, stream=False)
    except:
        return raw_text


def _get_rule_based_verdict(ingredients: list, profile: dict, report: dict) -> str:
    """
    Fast local verdict — no Gemini call, no quota usage.
    Summarises what the rule engine already found.
    """
    alerts = report.get('allergy_result', {}).get('allergy_alerts', [])
    score  = report.get('overall_score', 75)
    band   = report.get('risk', {}).get('risk_band', 'Safe')

    if not alerts:
        skin_type = profile.get('skin_type', 'Normal')
        return (
            f"**Overall Verdict: Safe ✓**\n\n"
            f"No concerning ingredients detected for your {skin_type} skin profile. "
            f"Safety score: {score}/100.\n\n"
            f"**Tip:** Always patch test new products before full application."
        )

    lines = [f"**Overall Verdict: {band}** — Safety score {score}/100\n"]
    lines.append("**Key Concerns:**")
    for a in alerts[:5]:
        name    = a.get('common_name') or a.get('ingredient', '')
        concern = a.get('matched_concern', '')
        sev     = a.get('severity', 'MODERATE')
        banner  = '⛔' if sev == 'CRITICAL' else '⚠️'
        lines.append(f"• {banner} **{name}** — {concern}")

    allergies = profile.get('allergies', [])
    if allergies:
        matched = [a['common_name'] for a in alerts if a.get('matched_concern', '').lower() in [al.lower() for al in allergies]]
        if matched:
            lines.append(f"\n**Personal Alert:** {', '.join(matched)} matches your allergy profile.")

    return '\n'.join(lines)


def _get_safety_agent_verdict(ingredients: list, profile: dict) -> str:
    """[FEATURE B/C] Personalized Safety Verdict with hidden alias mapping."""
    allergies = profile.get('allergies', [])
    skin_type = profile.get('skin_type', 'Normal')
    conditions = profile.get('skin_conditions', [])

    prompt = f"""You are PurePick AI — a friendly product safety expert. Analyze these ingredients for this user and give a clear, direct safety verdict.

USER PROFILE:
- Skin Type: {skin_type}
- Allergies: {', '.join(allergies) if allergies else 'None'}
- Skin Conditions: {', '.join(conditions) if conditions else 'None'}

INGREDIENTS: {', '.join(ingredients[:30])}

Write a short safety analysis using this exact format:

**Overall Verdict:** [Safe / Caution / Avoid] — one sentence summary.

**Key Ingredients:**
• [Ingredient] — [what it does, safe or concern]
• [Ingredient] — [what it does, safe or concern]
(list top 4–6 notable ingredients only)

**Personalized Note:** [One sentence specific to this user's skin type or allergies]

Rules:
- Do NOT show your reasoning or thinking process
- Do NOT use phrases like "Let me analyze" or "I will now"
- Be direct and concise
- Maximum 150 words total"""
    try:
        return _call_gemini_api(prompt, stream=False)
    except:
        return "AI analysis unavailable."


# ── Ingredient Analysis (text-only, no OCR) ───────────────────────────────────

@shared_task(
    bind=True,
    name='scanner.tasks.run_ingredient_analysis',
    max_retries=1,
    queue='default',    # Rule engine is fast — default queue is fine
)
def run_ingredient_analysis(self, ingredients: list[str], user_id: int) -> dict[str, Any]:
    """
    Rule engine analysis for manually-entered ingredient lists.
    Lighter than OCR — runs on the default queue.
    """
    try:
        from .ingredient_analyzer import get_analyzer

        user_profile = _load_user_profile(user_id)
        analyzer = get_analyzer()
        report = analyzer.analyze(ingredients, user_profile=user_profile)

        record_id = _persist_scan_record(user_id, report, ingredients)
        report['scan_id'] = record_id

        _update_user_streak(user_id)

        return report

    except SoftTimeLimitExceeded:
        return {'status': 'error', 'error': 'Analysis timed out.'}
    except Exception as exc:
        logger.exception('run_ingredient_analysis failed: %s', exc)
        try:
            raise self.retry(exc=exc)
        except self.MaxRetriesExceededError:
            return {'status': 'error', 'error': 'Analysis failed.'}


# ── Gemini Chat Task ──────────────────────────────────────────────────────────

@shared_task(
    bind=True,
    name='scanner.tasks.call_gemini_chat',
    max_retries=2,
    default_retry_delay=3,
    queue='default',
)
def call_gemini_chat(self, query: str, user_id: int, history: list = None) -> dict[str, Any]:
    """
    Gemini chat call off the request thread.
    Supports conversation history for contextual multi-turn chat.
    Returns { response: str } on success, { error: str } on failure.
    """
    try:
        from purepick_core.models import HealthProfile, ScanRecord

        profile_str = 'No profile set.'
        scan_history_str = 'No scans yet.'

        try:
            profile = HealthProfile.objects.get(user_id=user_id)
            profile_str = (
                f'Allergies: {", ".join(profile.get_allergies_list())}. '
                f'Skin type: {profile.skin_type}. '
                f'Skin conditions: {", ".join(profile.get_skin_conditions_list())}. '
                f'Custom concerns: {profile.custom_allergens or "none"}'
            )
            scans = ScanRecord.objects.filter(user_id=user_id).order_by('-scanned_at')[:5]
            if scans:
                scan_history_str = 'Recent product scans:\n' + '\n'.join(
                    [f'- {s.product_name}: {s.risk_level} risk' for s in scans]
                )
        except HealthProfile.DoesNotExist:
            pass

        # Build conversation history string for context
        history_context = ''
        if history:
            history_context = '\n\nCONVERSATION HISTORY (for context):\n'
            for msg in (history or [])[-8:]:   # last 8 messages max
                role = 'User' if msg.get('role') == 'user' else 'Assistant'
                history_context += f'{role}: {msg.get("text", "")}\n'

        prompt = f"""You are PurePick AI — a knowledgeable, friendly product safety and skincare assistant.

USER PROFILE:
{profile_str}

{scan_history_str}
{history_context}

CURRENT QUESTION: {query}

RULES:
1. Give PERSONALIZED advice based on the user profile above.
2. Check ingredients against their specific allergies and skin conditions.
3. Flag hidden allergen aliases (e.g. Maltodextrin = corn derivative).
4. Be concise, warm, and direct — no lengthy preamble.
5. NEVER start with "I", "Let me", "Sure", or "Of course".
6. NEVER show reasoning or thinking steps.
7. Use clean Markdown formatting:
   - **bold** for key ingredients and warnings
   - bullet points for lists
   - ### for section headers (### Analysis, ### Recommendation)
8. Never claim to be a licensed medical professional.
9. Keep responses under 200 words unless detail is truly needed.

Answer directly:"""

        response_text = _call_gemini_api(prompt, stream=True)
        return {'response': response_text}

    except SoftTimeLimitExceeded:
        return {'error': 'Request timed out. Please try again.'}
    except Exception as exc:
        logger.exception('call_gemini_chat failed: %s', exc)
        try:
            raise self.retry(exc=exc)
        except self.MaxRetriesExceededError:
            return {'error': 'AI chat unavailable. Please try again later.'}


# ── Gemini Tips Task ──────────────────────────────────────────────────────────

@shared_task(
    bind=True,
    name='scanner.tasks.call_gemini_tips',
    max_retries=1,
    queue='default',
)
def call_gemini_tips(self, user_id: int) -> dict[str, Any]:
    """
    Generate personalised AI tips for a user.
    Returns { tips: [...] }.
    """
    _FALLBACK_TIPS = [
        {
            'title': 'Check for SLS',
            'body': 'Sodium Lauryl Sulfate is a common irritant found in many cleansers.',
            'category': 'Ingredient Watch',
            'severity': 'Medium',
            'related_ingredient': 'SLS',
        },
        {
            'title': 'Fragrance Sensitivity',
            'body': 'Synthetic fragrances can trigger hidden allergies even in small amounts.',
            'category': 'Allergy',
            'severity': 'High',
            'related_ingredient': 'Parfum',
        },
    ]

    # ── Cache check: return cached tips if fresh enough ──────────────────────
    cached = _get_cached_tips(user_id)
    if cached:
        logger.info('Returning cached tips for user %s', user_id)
        return {'tips': cached}

    # ── Rate-limit guard: only call Gemini for tips once per 30 min ──────────
    # If another tips request already fired recently, return fallback instantly
    # so scan label quota isn't consumed by repeated home screen loads.
    try:
        import redis as redis_lib
        from django.conf import settings
        _r = redis_lib.from_url(settings.CELERY_BROKER_URL, decode_responses=True)
        lock_key = f'purepick:tips:generating:{user_id}'
        if _r.exists(lock_key):
            logger.info('Tips generation already in progress for user %s — returning fallback', user_id)
            return {'tips': _FALLBACK_TIPS}
        _r.setex(lock_key, 30 * 60, '1')  # lock for 30 min
    except Exception:
        pass

    try:
        from purepick_core.models import HealthProfile, ScanRecord

        try:
            profile = HealthProfile.objects.get(user_id=user_id)
            allergies_str = ", ".join(profile.get_allergies_list()) or 'none'
            conditions_str = ", ".join(profile.get_skin_conditions_list()) or 'none'
            custom_str = profile.custom_allergens or 'none'
            skin_type = profile.skin_type
            gender = profile.gender
        except HealthProfile.DoesNotExist:
            allergies_str = 'none'
            conditions_str = 'none'
            custom_str = 'none'
            skin_type = 'Normal'
            gender = 'Other'

        recent_scans = ScanRecord.objects.filter(user_id=user_id).order_by('-scanned_at')[:5]
        scan_context = (
            '\n'.join([f'- {s.product_name}: {s.risk_level} risk' for s in recent_scans])
            if recent_scans else 'No scans yet.'
        )

        # ── [NEW] Weather / Seasonal Context ──────────────────────────────────
        from django.utils import timezone
        month = timezone.now().month
        season = "Summer" if month in [6,7,8] else "Autumn" if month in [9,10,11] else "Winter" if month in [12,1,2] else "Spring"
        weather_context = f"Current Season: {season}. Assume moderate UV levels and humidity typical for this season."

        prompt = f"""You are PurePick's AI skincare advisor. Generate exactly 5 highly personalized skincare safety tips.

USER HEALTH PROFILE:
- Gender: {gender}
- Skin Type: {skin_type}
- Allergies: {allergies_str}
- Skin Conditions: {conditions_str}
- Custom Allergens: {custom_str}

ENVIRONMENTAL CONTEXT:
{weather_context}

RECENT SCAN HISTORY:
{scan_context}

GOAL: Provide actionable, scientific, and hyper-personalized advice based on THEIR unique profile.
MANDATORY: Include exactly one tip with category "Weather Insight" that links the current season ({season}) to their skin type ({skin_type}).

FORMAT: Return ONLY a JSON array (no markdown, no preamble):
[
  {{
    "title": "Short title",
    "body": "2-3 sentences specific to THEIR profile and the environment",
    "category": "Allergy|Skin Condition|Weather Insight|Ingredient Watch",
    "severity": "High|Medium|Low",
    "related_ingredient": "name or null"
  }}
]"""

        # Use streaming for faster perceived first-byte delivery
        raw = _call_gemini_api(prompt, stream=True)

        # If API key missing, raw contains the instructions string
        if "AI Chat is currently offline" in raw:
            return {
                'tips': [{
                    'title': 'AI Connectivity Issue',
                    'body': 'Your personalized AI tips are unavailable. Please add your Gemini API Key to the .env file on the server.',
                    'category': 'General Safety',
                    'severity': 'Medium',
                    'related_ingredient': None
                }]
            }

        import re
        match = re.search(r'\[.*\]', raw, re.DOTALL)
        if match:
            try:
                # Clean up any potential markdown or noise
                json_str = match.group().replace('```json', '').replace('```', '').strip()
                tips = json.loads(json_str)
                _set_cached_tips(user_id, tips)   # cache for 6 hours
                return {'tips': tips}
            except json.JSONDecodeError:
                logger.error("AI returned invalid JSON tips: %s", raw)

        return {'tips': _FALLBACK_TIPS}

    except SoftTimeLimitExceeded:
        return {'tips': _FALLBACK_TIPS}
    except Exception as exc:
        logger.exception('call_gemini_tips failed: %s', exc)
        return {'tips': _FALLBACK_TIPS}


# ── Shared Helpers (module-private) ──────────────────────────────────────────

def _load_user_profile(user_id: int) -> dict:
    """Load health profile from DB. Returns safe defaults on miss."""
    try:
        from purepick_core.models import HealthProfile
        p = HealthProfile.objects.get(user_id=user_id)
        return {
            'allergies': p.get_allergies_list(),
            'skin_conditions': p.get_skin_conditions_list(),
            'custom_allergens': p.get_custom_allergens_list(),
            'skin_type': p.skin_type,
            'gender': p.gender,
            'age': p.age,
            'profile_missing': False,
            'last_updated': str(p.updated_at),
        }
    except Exception:
        return {'allergies': [], 'skin_conditions': [], 'custom_allergens': [], 'skin_type': 'Normal', 'profile_missing': True}


def _persist_scan_record(user_id: int, report: dict, ingredients: list,
                         raw_text: str = '', product_name: str = 'Scanned Product',
                         scan_source: str = 'manual', barcode: str = '') -> int | None:
    """Write scan result to DB. Returns record ID or None on failure."""
    try:
        from purepick_core.models import ScanRecord
        risk_band = report.get('risk', {}).get('risk_band', 'Moderate').lower()
        risk_level = risk_band if risk_band in ('safe', 'moderate', 'high') else 'moderate'
        flagged = [a['ingredient'] for a in report.get('allergy_result', {}).get('allergy_alerts', [])]
        guessed_name = (
            report.get('product_name')
            or (raw_text.split('\n')[0].strip()[:50] if raw_text else None)
            or product_name
        )
        rec = ScanRecord.objects.create(
            user_id=user_id,
            product_name=guessed_name,
            ingredients_raw=', '.join(ingredients),
            safety_score=report.get('overall_score', 50),
            risk_level=risk_level,
            flagged_ingredients=json.dumps(flagged),
            ai_analysis=report.get('ai_insight', ''),
            personal_warnings=report.get('personal_warnings', ''),
            scan_source=scan_source,
            barcode=barcode,
        )
        # WHY: invalidate cached tips so next request reflects the new scan
        invalidate_tips_cache(user_id)
        # Send push notification for high-risk scans
        try:
            from purepick_core.notification_views import send_scan_risk_notification
            send_scan_risk_notification(
                user_id, guessed_name, risk_level, len(flagged)
            )
        except Exception:
            pass   # notifications are optional — never block scan save

        return rec.id
    except Exception as exc:
        logger.warning('Could not persist scan record for user %s: %s', user_id, exc)
        return None


def _call_gemini_api(prompt: str, stream: bool = False) -> str:
    """
    Call Gemini API using the new google-genai SDK (v1 endpoint).
    Supports the AQ. key format from Google AI Studio.
    Falls back gracefully on quota or model errors.
    """
    from django.conf import settings
    from google import genai
    from google.genai import types

    api_key = getattr(settings, 'GEMINI_API_KEY', None)
    if not api_key or api_key == 'YOUR_GEMINI_API_KEY_HERE':
        return "AI analysis is currently in simplified mode (API Key missing)."

    client = genai.Client(api_key=api_key)

    gen_config = types.GenerateContentConfig(
        temperature=0.3,
        max_output_tokens=1024,
        thinking_config=types.ThinkingConfig(thinking_budget=0),  # disable thinking output
    )

    import time

    # Models confirmed working with this API key
    models = ['gemini-flash-latest', 'gemini-2.0-flash', 'gemini-2.0-flash-lite']
    last_error = ''

    for i, model_name in enumerate(models):
        # Retry up to 3 times on 429 with backoff
        for attempt in range(3):
            try:
                if stream:
                    chunks = []
                    for chunk in client.models.generate_content_stream(
                        model=model_name,
                        contents=prompt,
                        config=gen_config,
                    ):
                        if chunk.text:
                            chunks.append(chunk.text)
                    result = ''.join(chunks)
                else:
                    resp = client.models.generate_content(
                        model=model_name,
                        contents=prompt,
                        config=gen_config,
                    )
                    result = resp.text if resp and resp.text else ""

                if result:
                    logger.info('Gemini response from %s attempt %d (%d chars)',
                                model_name, attempt + 1, len(result))
                    return result
                break  # empty result — try next model

            except Exception as e:
                err_msg = str(e)
                last_error = err_msg
                is_rate_limit = "429" in err_msg or "quota" in err_msg.lower() or "RESOURCE_EXHAUSTED" in err_msg
                is_not_found  = "404" in err_msg or "NOT_FOUND" in err_msg

                if is_not_found:
                    logger.debug('Model %s not available for this key — skipping', model_name)
                    break  # try next model immediately

                if is_rate_limit:
                    wait = 4 * (attempt + 1)   # 4s, 8s, 12s
                    logger.warning('Rate limit on %s (attempt %d) — waiting %ds',
                                   model_name, attempt + 1, wait)
                    if attempt < 2:
                        time.sleep(wait)
                        continue
                    break  # exhausted retries for this model

                logger.debug('Gemini model %s failed: %s', model_name, e)
                break  # unexpected error — try next model

    # All models exhausted
    if "429" in last_error or "RESOURCE_EXHAUSTED" in last_error:
        return (
            "PurePick AI is experiencing high demand right now. "
            "Please try again in a moment."
        )
    return "AI analysis is currently unavailable. Please try again later."


# ── Redis tips cache ──────────────────────────────────────────────────────────
_TIPS_CACHE_TTL = 24 * 60 * 60  # 24 hours — tips don't need to refresh every scan


def _tips_cache_key(user_id: int) -> str:
    return f'purepick:tips:user:{user_id}'


def _get_cached_tips(user_id: int):
    """Return cached tips list or None on miss / Redis unavailable."""
    try:
        import redis as redis_lib
        from django.conf import settings
        r = redis_lib.from_url(settings.CELERY_BROKER_URL, decode_responses=True)
        raw = r.get(_tips_cache_key(user_id))
        if raw:
            logger.debug('Tips cache HIT for user %s', user_id)
            return json.loads(raw)
    except Exception as exc:
        logger.debug('Tips cache get failed: %s', exc)
    return None


def _set_cached_tips(user_id: int, tips: list) -> None:
    """Write tips to Redis with 6h TTL. Failures are silent."""
    try:
        import redis as redis_lib
        from django.conf import settings
        r = redis_lib.from_url(settings.CELERY_BROKER_URL, decode_responses=True)
        r.setex(_tips_cache_key(user_id), _TIPS_CACHE_TTL, json.dumps(tips))
        logger.debug('Tips cached for user %s (TTL=6h)', user_id)
    except Exception as exc:
        logger.debug('Tips cache set failed: %s', exc)


def invalidate_tips_cache(user_id: int) -> None:
    """Bust tips cache after a new scan — so next request gets fresh tips."""
    try:
        import redis as redis_lib
        from django.conf import settings
        r = redis_lib.from_url(settings.CELERY_BROKER_URL, decode_responses=True)
        r.delete(_tips_cache_key(user_id))
        logger.debug('Tips cache invalidated for user %s', user_id)
    except Exception as exc:
        logger.debug('Tips cache invalidation failed: %s', exc)


def _update_user_streak(user_id: int) -> None:
    """Increment user's skincare streak if they scan on a new day."""
    try:
        from purepick_core.models import User
        from django.utils import timezone
        from datetime import date

        user = User.objects.get(id=user_id)
        today = timezone.now().date()

        if user.last_streak_date == today:
            logger.info('User %s already scanned today. Streak: %s', user_id, user.current_streak)
            return

        # If last scan was yesterday, increment
        if user.last_streak_date == today - timedelta(days=1):
            user.current_streak += 1
        else:
            # If they missed a day, reset to 1
            user.current_streak = 1

        user.last_streak_date = today
        if user.current_streak > user.best_streak:
            user.best_streak = user.current_streak

        user.save()
        logger.info('Streak UPDATED for user %s: %s days', user_id, user.current_streak)
    except Exception as exc:
        logger.warning('Could not update streak for user %s: %s', user_id, exc)


def _safe_delete(path: str) -> None:
    """Delete a file, suppressing all errors."""
    try:
        if path and os.path.exists(path):
            os.unlink(path)
    except Exception as exc:
        logger.warning('Could not delete temp file %s: %s', path, exc)


# ── Barcode Lookup + Analysis Task ───────────────────────────────────────────

@shared_task(
    bind=True,
    name='scanner.tasks.run_barcode_analysis',
    max_retries=2,
    default_retry_delay=3,
    queue='default',     # network I/O task — default queue, not ml
)
def run_barcode_analysis(self, barcode: str, user_id: int) -> dict:
    """
    Barcode → Open Beauty Facts lookup → ingredient analysis pipeline.

    Args:
        barcode: UPC/EAN string from Flutter barcode scanner.
        user_id: Authenticated user's ID.

    Returns:
        Full analysis report (same shape as run_ingredient_analysis)
        with added product metadata fields.
    """
    try:
        from .barcode_service import lookup_barcode
        from .ingredient_analyzer import get_analyzer

        # Stage 1: Barcode lookup
        lookup = lookup_barcode(barcode)

        if not lookup['found']:
            return {
                'status': 'not_found',
                'barcode': barcode,
                'message': lookup['message'],
            }

        ingredients     = lookup['ingredients_list']
        product_name    = lookup['product_name']
        brand           = lookup['brand']

        if not ingredients:
            return {
                'status': 'no_ingredients',
                'barcode': barcode,
                'product_name': product_name,
                'message': f'No ingredient list found for "{product_name}".',
            }

        # Stage 2: Ingredient analysis
        user_profile = _load_user_profile(user_id)
        analyzer     = get_analyzer()
        report       = analyzer.analyze(ingredients, user_profile=user_profile)

        # Stage 3: Enrich report with product metadata
        report['product_name']     = product_name
        report['brand']            = brand
        report['barcode']          = barcode
        report['image_url']        = lookup.get('image_url')
        report['ingredients_text'] = lookup.get('ingredients_text', '')
        report['scan_source']      = 'barcode'
        report['lookup_source']    = lookup.get('source', 'open_beauty_facts')
        report['ai_sourced']       = lookup.get('ai_sourced', False)  # True when Gemini provided ingredients

        # Stage 4: Persist
        record_id = _persist_scan_record(
            user_id, report, ingredients,
            product_name=product_name,
            scan_source='barcode',
            barcode=barcode,
        )
        report['scan_id'] = record_id

        _update_user_streak(user_id)

        logger.info('Barcode %s analyzed for user %s: %s', barcode, user_id, product_name)
        return report

    except SoftTimeLimitExceeded:
        return {'status': 'error', 'error': 'Lookup timed out. Please try again.'}
    except Exception as exc:
        logger.exception('run_barcode_analysis failed for %s: %s', barcode, exc)
        try:
            raise self.retry(exc=exc)
        except self.MaxRetriesExceededError:
            return {'status': 'error', 'error': 'Barcode lookup failed after retries.'}

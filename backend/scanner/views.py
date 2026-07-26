"""
Scanner Views — Async task-dispatching endpoints
=================================================
All CPU-heavy operations (OCR, ML inference, Gemini calls) are now
enqueued as Celery tasks. Views return immediately with a task_id.
Flutter polls GET /api/task/<task_id>/ until the result is ready.

Request lifecycle:
  POST /api/scan-label/  →  save temp file  →  enqueue task  →  202 + task_id
  POST /api/analyze/     →  enqueue task    →  202 + task_id
  POST /api/chat/        →  enqueue task    →  202 + task_id
  GET  /api/ai-tips/id/  →  enqueue task    →  202 + task_id
  GET  /api/task/uuid/   →  poll result     →  200 + {status, result?}
"""
import logging
import os
import tempfile

from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from django.http import JsonResponse
import json

from purepick_core.auth_utils import jwt_required, require_own_user
from purepick_core.views import (
    register_user, login_user, google_login, refresh_token, logout_user,
    update_profile, get_profile,
    get_history, save_product, get_saved, delete_saved,
)
from purepick_core.models import User, HealthProfile, ScanRecord

logger = logging.getLogger(__name__)

MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024
ALLOWED_IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'}


def _validate_image(image_file) -> tuple[bool, str]:
    if not image_file:
        return False, 'image file is required'
    ext = os.path.splitext(image_file.name)[1].lower()
    if ext not in ALLOWED_IMAGE_EXTENSIONS:
        return False, f'Unsupported file type "{ext}". Use JPG, PNG, or WebP.'
    if image_file.size > MAX_IMAGE_SIZE_BYTES:
        return False, 'Image too large. Maximum size is 10 MB.'
    return True, ''


# ── AI Analysis endpoints ──────────────────────────────────────────────────────

@csrf_exempt
@jwt_required
@require_http_methods(['POST'])
def analyze_ingredients(request):
    """
    POST /api/analyze/
    Body: { "ingredients": [...] }
    Enqueues ingredient analysis task. Returns task_id immediately.
    """
    try:
        data = json.loads(request.body)
        ingredients = data.get('ingredients', [])
        user_id = request.auth_user_id

        if not ingredients or not isinstance(ingredients, list):
            return JsonResponse({'error': 'ingredients must be a non-empty list'}, status=400)
        if len(ingredients) > 200:
            return JsonResponse({'error': 'Maximum 200 ingredients per request.'}, status=400)

        from .tasks import run_ingredient_analysis
        task = run_ingredient_analysis.delay(ingredients, user_id)

        return JsonResponse({'task_id': task.id, 'status': 'PENDING'}, status=202)

    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON body'}, status=400)
    except Exception as exc:
        logger.error('analyze_ingredients enqueue error: %s', exc)
        return JsonResponse({'error': 'Failed to start analysis'}, status=500)


@csrf_exempt
@jwt_required
@require_http_methods(['POST'])
def scan_label_image(request):
    """
    POST /api/scan-label/
    Saves uploaded image to a persistent temp file, enqueues OCR+analyze task.
    Returns task_id immediately — Flutter polls for the result.

    ⚠ IMPORTANT: uses delete=False + no cleanup here.
    The Celery task (run_ocr_and_analyze) owns the file and deletes it on completion.
    """
    try:
        user_id = request.auth_user_id
        image_file = request.FILES.get('image')

        valid, err = _validate_image(image_file)
        if not valid:
            return JsonResponse({'error': err}, status=400)

        ext = os.path.splitext(image_file.name)[1].lower() or '.jpg'

        # WHY delete=False: file must outlive the HTTP request so the Celery worker can read it
        # USE /app/scans/ shared volume for Docker
        save_dir = '/app/scans'
        if not os.path.exists(save_dir):
            os.makedirs(save_dir, exist_ok=True)

        with tempfile.NamedTemporaryFile(dir=save_dir, delete=False, suffix=ext, prefix='purepick_ocr_') as tmp:
            for chunk in image_file.chunks():
                tmp.write(chunk)
            tmp_path = tmp.name

        # Convert to base64 for cloud worker compatibility
        import base64
        with open(tmp_path, 'rb') as f:
            img_b64 = base64.b64encode(f.read()).decode('utf-8')

        from .tasks import run_ocr_and_analyze
        task = run_ocr_and_analyze.delay(img_b64, user_id)

        # Cleanup temp file immediately after b64 conversion
        os.unlink(tmp_path)

        logger.info('Enqueued OCR task %s for user %s (Base64 sync)', task.id, user_id)
        return JsonResponse({
            'task_id': task.id,
            'status': 'PENDING',
            'message': 'Scan in progress. Poll /api/task/<task_id>/ for results.',
        }, status=202)

    except Exception as exc:
        logger.error('scan_label_image enqueue error: %s', exc)
        return JsonResponse({'error': 'Failed to start scan'}, status=500)


@csrf_exempt
@jwt_required
@require_http_methods(['POST'])
def get_alternatives(request):
    """
    POST /api/alternatives/
    Fetches curated 'Clean Swaps' based on product category.
    """
    try:
        data = json.loads(request.body)
        category_hint = data.get('category', '').lower()

        # 1. Try to find products in the specific category
        from purepick_core.models import CleanProduct

        # Categorization logic (simple keyword matching)
        target_cat = 'moisturizer' # default
        if 'shampoo' in category_hint: target_cat = 'shampoo'
        elif 'cleanser' in category_hint or 'wash' in category_hint: target_cat = 'cleanser'
        elif 'sunscreen' in category_hint or 'spf' in category_hint: target_cat = 'sunscreen'
        elif 'serum' in category_hint: target_cat = 'serum'

        swaps = CleanProduct.objects.filter(category=target_cat).order_by('-safety_score')[:3]

        results = [
            {
                'name': s.name,
                'brand': s.brand,
                'score': s.safety_score,
                'category': s.get_category_display(),
                'buy_url': s.buy_url or 'https://www.amazon.com/s?k=' + s.brand.replace(' ', '+') + '+' + s.name.replace(' ', '+')
            } for s in swaps
        ]

        return JsonResponse({'alternatives': results})

    except Exception as exc:
        logger.error('get_alternatives error: %s', exc)
        return JsonResponse({'error': 'Failed to fetch alternatives'}, status=500)


@csrf_exempt
@jwt_required
@require_http_methods(['POST'])
def chat_with_ai(request):
    """
    POST /api/chat/
    Body: { "query": "..." }
    Enqueues Gemini chat task. Returns task_id immediately.
    """
    try:
        data = json.loads(request.body)
        query = data.get('query', '').strip()
        history = data.get('history', [])   # list of {role, text} for context
        user_id = request.auth_user_id

        if not query:
            return JsonResponse({'error': 'query is required'}, status=400)
        if len(query) > 1000:
            return JsonResponse({'error': 'Query too long. Maximum 1000 characters.'}, status=400)

        from .tasks import call_gemini_chat
        task = call_gemini_chat.delay(query, user_id, history=history[-10:])

        return JsonResponse({'task_id': task.id, 'status': 'PENDING'}, status=202)

    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON body'}, status=400)
    except Exception as exc:
        logger.error('chat_with_ai enqueue error: %s', exc)
        return JsonResponse({'error': 'Failed to start chat'}, status=500)


@jwt_required
@require_own_user('user_id')
def get_ai_tips(request, user_id):
    """
    GET /api/ai-tips/<user_id>/
    Enqueues Gemini tips task. Returns task_id immediately.
    """
    try:
        from .tasks import call_gemini_tips
        task = call_gemini_tips.delay(user_id)
        return JsonResponse({'task_id': task.id, 'status': 'PENDING'}, status=202)

    except Exception as exc:
        logger.error('get_ai_tips enqueue error: %s', exc)
        return JsonResponse({'error': 'Failed to start tips generation'}, status=500)


@jwt_required
@require_own_user('user_id')
def get_home_stats(request, user_id):
    """
    GET /api/home-stats/<user_id>/
    Synchronous — simple DB aggregation, no ML.
    """
    try:
        from django.db.models import Avg
        user_obj = User.objects.filter(id=user_id).first()
        if not user_obj:
            return JsonResponse({'error': 'User not found'}, status=404)

        all_scans = ScanRecord.objects.filter(user_id=user_id)
        total_scans = all_scans.count()
        avg_data = all_scans.aggregate(Avg('safety_score'))
        avg_safety = int(avg_data['safety_score__avg'] or 0)
        safe_products = all_scans.filter(risk_level='safe').count()
        flagged_products = all_scans.filter(risk_level='high').count()

        recent = all_scans.order_by('-scanned_at')[:5]
        recent_list = [
            {
                'product_name': s.product_name,
                'band': s.risk_level,
                'risk_level': s.risk_level,
                'safety_score': s.safety_score,
                'score': s.safety_score,
                'date': s.scanned_at.strftime('%b %d, %H:%M'),
            }
            for s in recent
        ]

        # Skin history
        from skin_analysis.models import SkinAnalysisRecord
        recent_skin = SkinAnalysisRecord.objects.filter(user_id=user_id).order_by('-analysed_at').first()
        skin_data = None
        if recent_skin:
            skin_data = {
                'type': recent_skin.skin_type,
                'disorder': recent_skin.skin_disorder,
                'date': recent_skin.analysed_at.strftime('%b %d'),
            }

        # Health Profile Summary
        profile = HealthProfile.objects.filter(user_id=user_id).first()
        profile_summary = None
        if profile:
            profile_summary = {
                'skin_type': profile.skin_type,
                'allergies': profile.get_allergies_list(),
                'skin_conditions': profile.get_skin_conditions_list(),
                'custom_concerns': profile.get_custom_allergens_list(),
            }

        return JsonResponse({
            'total_scans': total_scans,
            'avg_safety': f'{avg_safety}%',
            'avg_safety_score': avg_safety,
            'safe_products': safe_products,
            'flagged_products': flagged_products,
            'recent_scans': recent_list,
            'recent_skin': skin_data,
            'health_profile': profile_summary,
            'streak': user_obj.current_streak,
            'best_streak': user_obj.best_streak,
        })

    except Exception as exc:
        logger.error('get_home_stats error for user %s: %s', user_id, exc)
        return JsonResponse({'error': 'Failed to load stats'}, status=500)


@csrf_exempt
@jwt_required
@require_http_methods(['POST'])
def lookup_barcode(request):
    """
    POST /api/barcode-lookup/
    Body: { "barcode": "1234567890123" }
    Enqueues barcode → Open Beauty Facts → analyze task.
    Returns task_id immediately.
    """
    try:
        data    = json.loads(request.body)
        barcode = data.get('barcode', '').strip()
        user_id = request.auth_user_id

        if not barcode:
            return JsonResponse({'error': 'barcode is required'}, status=400)

        if not barcode.isdigit() or len(barcode) not in (8, 12, 13, 14):
            return JsonResponse(
                {'error': 'Invalid barcode. Expected 8, 12, or 13-digit UPC/EAN.'},
                status=400,
            )

        from .tasks import run_barcode_analysis
        task = run_barcode_analysis.delay(barcode, user_id)

        logger.info('Enqueued barcode task %s for barcode %s user %s', task.id, barcode, user_id)
        return JsonResponse({
            'task_id': task.id,
            'status':  'PENDING',
            'message': 'Looking up barcode. Poll /api/task/<task_id>/ for results.',
        }, status=202)

    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON body'}, status=400)
    except Exception as exc:
        logger.error('lookup_barcode enqueue error: %s', exc)
        return JsonResponse({'error': 'Failed to start barcode lookup'}, status=500)


@jwt_required
@require_http_methods(['GET'])
def get_skincast(request):
    """
    GET /api/skincast/?lat=...&lon=...
    Fetches real weather, UV index, and AQI from OpenWeatherMap APIs.

    Endpoints used (all free tier):
      - /data/2.5/weather       → temp, humidity, city name
      - /data/2.5/uvi           → real UV index
      - /data/2.5/air_pollution → real AQI (1=Good, 2=Fair, 3=Moderate, 4=Poor, 5=Very Poor)
    """
    lat = request.GET.get('lat')
    lon = request.GET.get('lon')

    if not lat or not lon:
        return JsonResponse({'error': 'lat and lon are required'}, status=400)

    import requests as req
    from datetime import datetime

    api_key  = os.getenv('OPENWEATHER_API_KEY', '')
    base_url = 'https://api.openweathermap.org'

    # Sensible defaults (Pakistan summer baseline)
    temp     = 32.0
    humidity = 45
    uv       = 6.0
    aqi      = 50
    city     = 'Your Location'

    if api_key:
        # ── 1. Current weather ────────────────────────────────────────────────
        try:
            r = req.get(
                f"{base_url}/data/2.5/weather?lat={lat}&lon={lon}&appid={api_key}&units=metric",
                timeout=6
            )
            if r.status_code == 200:
                d = r.json()
                temp     = round(d['main']['temp'], 1)
                humidity = d['main']['humidity']
                city     = d.get('name', 'Your Location')
                logger.info('SkinCast weather: %s temp=%.1f°C humid=%d%%', city, temp, humidity)
        except Exception as e:
            logger.warning('SkinCast weather fetch failed: %s', e)

        # ── 2. UV Index ───────────────────────────────────────────────────────
        try:
            r = req.get(
                f"{base_url}/data/2.5/uvi?lat={lat}&lon={lon}&appid={api_key}",
                timeout=6
            )
            if r.status_code == 200:
                uv = round(r.json().get('value', 6.0), 1)
                logger.info('SkinCast UV index: %.1f', uv)
        except Exception as e:
            logger.warning('SkinCast UV fetch failed: %s', e)
            # Estimate UV from time of day if API fails
            hour = datetime.now().hour
            if 10 <= hour <= 14:
                uv = 8.0 if temp > 30 else 5.0
            elif 8 <= hour <= 16:
                uv = 5.0 if temp > 25 else 3.0
            else:
                uv = 0.0

        # ── 3. Air Pollution / AQI ────────────────────────────────────────────
        try:
            r = req.get(
                f"{base_url}/data/2.5/air_pollution?lat={lat}&lon={lon}&appid={api_key}",
                timeout=6
            )
            if r.status_code == 200:
                components = r.json()['list'][0]['components']
                owm_aqi    = r.json()['list'][0]['main']['aqi']  # 1-5 scale
                # Convert OWM AQI scale (1-5) to US AQI equivalent for our rules (>150 = poor)
                aqi_map = {1: 25, 2: 75, 3: 125, 4: 175, 5: 250}
                aqi = aqi_map.get(owm_aqi, 50)
                logger.info('SkinCast AQI: OWM=%d → US_equiv=%d', owm_aqi, aqi)
        except Exception as e:
            logger.warning('SkinCast AQI fetch failed: %s', e)
    else:
        logger.warning('SkinCast: No OpenWeatherMap API key configured — using location-aware defaults')
        # Use time-of-day defaults when no key
        hour = datetime.now().hour
        if 10 <= hour <= 14:
            uv = 9.0   # High UV midday assumption
        elif hour < 6 or hour >= 19:
            uv = 0.0

    return JsonResponse({
        'temp':     temp,
        'humidity': humidity,
        'uv':       uv,
        'city':     city,
        'aqi':      aqi,
    })


from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from datetime import datetime
import requests


@jwt_required
def get_dashboard(request):
    """ Unified Skin Dashboard API - GET (FBV version) """
    lat = request.GET.get('lat', '0')
    lon = request.GET.get('lon', '0')
    user_id = request.auth_user_id

    # 1. Load User Profile
    from purepick_core.models import HealthProfile, SkinLog
    profile = HealthProfile.objects.filter(user_id=user_id).first()
    skin_type = profile.skin_type.lower() if profile else 'normal'

    # 2. Fetch Weather (OpenWeatherMap)
    api_key = os.getenv('OPENWEATHER_API_KEY', 'MOCK_KEY')
    weather = {'temp': 24.0, 'humidity': 50, 'uv': 3.0}
    if api_key != 'MOCK_KEY':
        try:
            url = f"https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={api_key}&units=metric"
            res = requests.get(url, timeout=3).json()
            weather['temp'] = res['main']['temp']
            weather['humidity'] = res['main']['humidity']
        except: pass

    # 3. AQI Prediction
    aqi = predict_aqi(lat, lon)

    # 4. Rules Engine logic
    now_hour = datetime.now().hour
    state = "All Clear"
    msg = "Perfect weather. Stick to standard routine."

    if now_hour >= 19 or now_hour < 5:
        state = "Night Repair"
        msg = "Time to repair. Apply Retinol and night cream."
    elif aqi > 150:
        state = "High Pollution"
        msg = "Poor air quality. Apply Vitamin C to block free radicals."
    elif weather['uv'] > 6:
        state = "High UV"
        msg = "High UV Index. Apply SPF 50+."
    elif weather['temp'] > 35 and weather['humidity'] > 60 and skin_type == 'oily':
        state = "Sweat Alert"
        msg = "High heat & humidity. Use lightweight gel moisturizer."
    elif weather['temp'] < 15 and weather['humidity'] < 30:
        state = "Winter Dry"
        msg = "Cold, dry air. Lock in hydration."

    # 5. Fetch Today's Log
    today_log = SkinLog.objects.filter(user_id=user_id, date=datetime.now().date()).first()
    log_data = None
    if today_log:
        log_data = {
            'score': today_log.condition_score,
            'tags': today_log.tags,
            'am': today_log.am_routine_done,
            'pm': today_log.pm_routine_done
        }

    return JsonResponse({
        'weather': {**weather, 'aqi': aqi},
        'skin_cast': {'state': state, 'message': msg},
        'today_log': log_data
    })


@csrf_exempt
@jwt_required
@require_http_methods(['POST'])
def save_skin_log(request):
    """ Save today's skin diary entry (FBV version) """
    try:
        from purepick_core.models import SkinLog
        user_id = request.auth_user_id
        data = json.loads(request.body)

        log, created = SkinLog.objects.update_or_create(
            user_id=user_id,
            date=datetime.now().date(),
            defaults={
                'condition_score': data.get('score', 3),
                'tags': data.get('tags', []),
                'am_routine_done': data.get('am', False),
                'pm_routine_done': data.get('pm', False),
            }
        )
        return JsonResponse({'status': 'saved', 'id': log.id})
    except Exception as exc:
        logger.error('save_skin_log error: %s', exc)
        return JsonResponse({'error': 'Failed to save log'}, status=500)


@require_http_methods(['GET'])
def health_check(request):
    """
    GET /api/health/
    Lightweight liveness probe used by:
      - Dockerfile HEALTHCHECK
      - docker-compose service_healthy condition
      - Load balancers / uptime monitors

    Returns 200 as long as the Django process is alive.
    No DB or Redis check — those have their own healthchecks in docker-compose.
    """
    return JsonResponse({'status': 'ok'}, status=200)

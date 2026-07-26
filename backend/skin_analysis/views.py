"""
skin_analysis/views.py — Async task-dispatching
"""
from __future__ import annotations
import logging
import os
import tempfile

from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from purepick_core.auth_utils import jwt_required, require_own_user
from .models import SkinAnalysisRecord
import json

logger = logging.getLogger(__name__)

MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024
ALLOWED_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'}


@csrf_exempt
@jwt_required
@require_http_methods(['POST'])
def analyze_face(request):
    """
    POST /api/skin/analyze-face/
    Saves selfie, enqueues ResNet-50 task. Returns task_id immediately.

    ⚠ delete=False: Celery worker owns file cleanup.
    """
    image_file = request.FILES.get('image')
    if not image_file:
        return JsonResponse({'error': 'image file is required'}, status=400)

    ext = os.path.splitext(image_file.name)[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        return JsonResponse({'error': f'Unsupported file type "{ext}".'}, status=400)
    if image_file.size > MAX_IMAGE_SIZE_BYTES:
        return JsonResponse({'error': 'Image too large. Maximum 10 MB.'}, status=400)

    user_id = request.auth_user_id

    try:
        # USE /app/scans/ shared volume for Docker
        save_dir = '/app/scans'
        if not os.path.exists(save_dir):
            os.makedirs(save_dir, exist_ok=True)

        with tempfile.NamedTemporaryFile(dir=save_dir, delete=False, suffix=ext, prefix='purepick_skin_') as tmp:
            for chunk in image_file.chunks():
                tmp.write(chunk)
            tmp_path = tmp.name
    except Exception as exc:
        logger.error('Failed to save uploaded image: %s', exc)
        return JsonResponse({'error': 'Could not process uploaded file.'}, status=500)

    # Convert to base64 for cloud worker compatibility
    import base64
    with open(tmp_path, 'rb') as f:
        img_b64 = base64.b64encode(f.read()).decode('utf-8')

    from .tasks import run_skin_analysis
    task = run_skin_analysis.delay(img_b64, user_id)

    # Cleanup temp file immediately after b64 conversion
    os.unlink(tmp_path)

    logger.info('Enqueued skin analysis task %s for user %s (Base64 sync)', task.id, user_id)
    return JsonResponse({
        'task_id': task.id,
        'status': 'PENDING',
        'message': 'Skin analysis in progress. Poll /api/task/<task_id>/ for results.',
    }, status=202)


@jwt_required
@require_own_user('user_id')
def get_skin_history(request, user_id):
    """GET /api/skin/history/<user_id>/ — optimized for mobile payloads."""
    try:
        # Optimization: only fetch fields needed for the history list
        records = SkinAnalysisRecord.objects.filter(user_id=user_id).only(
            'id', 'skin_type', 'skin_disorder', 'analysed_at'
        ).order_by('-analysed_at')[:20]

        data = [
            {
                'id': r.id,
                'skin_type': r.skin_type,
                'skin_disorder': r.skin_disorder,
                'date': r.analysed_at.strftime('%b %d, %Y %H:%M'),
            }
            for r in records
        ]
        return JsonResponse(data, safe=False)

    except Exception as exc:
        logger.error('get_skin_history error: %s', exc)
        return JsonResponse({'error': 'Failed to load skin history'}, status=500)

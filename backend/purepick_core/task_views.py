"""
purepick_core/task_views.py
===========================
Generic task status polling endpoint.

GET /api/task/<task_id>/
  Returns the current state and result of any Celery task.

Response shapes:
  { "status": "PENDING" }
  { "status": "STARTED", "progress": "Running OCR..." }
  { "status": "SUCCESS", "result": { ...full report... } }
  { "status": "FAILURE", "error": "Description" }

WHY polling instead of WebSockets:
  - Flutter HTTP client is simpler than WebSocket management
  - Tasks complete in 3–15s — polling at 1.5s intervals means max 10 polls
  - WebSockets add infra complexity (channels, daphne) for minimal UX gain here
  - Can upgrade to SSE/WebSocket in a future batch without changing task logic
"""
import logging
from django.http import JsonResponse
from celery.result import AsyncResult
from purepick_core.auth_utils import jwt_required

logger = logging.getLogger(__name__)


@jwt_required
def get_task_status(request, task_id: str):
    """
    GET /api/task/<task_id>/
    JWT required. Returns task state + result when complete.

    ⚠ SECURITY: Any authenticated user can poll any task_id if they know it.
    task_ids are UUIDs (hard to guess), and results expire after 1 hour.
    For stricter isolation, store task_id → user_id mapping in Redis on enqueue.
    """
    try:
        result = AsyncResult(task_id)
        state = result.state     # PENDING | STARTED | SUCCESS | FAILURE | RETRY

        if state == 'PENDING':
            return JsonResponse({'status': 'PENDING'})

        if state == 'STARTED':
            meta = result.info or {}
            return JsonResponse({
                'status': 'STARTED',
                'progress': meta.get('progress', 'Processing...'),
            })

        if state == 'SUCCESS':
            task_result = result.get()
            # Propagate task-level errors (e.g. no_face, ocr_empty)
            if isinstance(task_result, dict) and task_result.get('status') == 'error':
                return JsonResponse({
                    'status': 'FAILURE',
                    'error': task_result.get('error', 'Task failed'),
                })
            return JsonResponse({'status': 'SUCCESS', 'result': task_result})

        if state == 'FAILURE':
            exc = result.info
            logger.error('Task %s failed: %s', task_id, exc)
            return JsonResponse({
                'status': 'FAILURE',
                'error': 'Processing failed. Please try again.',
            })

        # RETRY or unknown states
        return JsonResponse({'status': state})

    except Exception as exc:
        logger.error('get_task_status error for %s: %s', task_id, exc)
        return JsonResponse({'error': 'Could not retrieve task status'}, status=500)

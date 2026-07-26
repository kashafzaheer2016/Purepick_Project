"""
skin_analysis/tasks.py
=======================
Celery task that runs the two-pass skin analysis pipeline off-thread.

Queue: 'ml'  (concurrency=2) — GPU/CPU heavy: SSD face detection,
CLAHE preprocessing, Gemini dual-pass Vision, optional ResNet-50.

The task:
  1. Calls skin_engine.analyse_face_image()
  2. Persists result to SkinAnalysisRecord
  3. Returns full report to Flutter via task polling

⚠ image_path is deleted here — the view must NOT delete it first.
"""
from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone

from celery import shared_task
from celery.exceptions import SoftTimeLimitExceeded

logger = logging.getLogger(__name__)

MEDICAL_DISCLAIMER = (
    'This analysis is for informational and cosmetic guidance purposes only '
    'and is not a medical diagnosis. Always consult a qualified dermatologist '
    'for clinical assessment and treatment of skin conditions.'
)


@shared_task(
    bind=True,
    name='skin_analysis.tasks.run_skin_analysis',
    max_retries=1,
    default_retry_delay=5,
    queue='ml',
    soft_time_limit=270,   # 4.5 min — covers cold-start model load
    time_limit=300,
)
def run_skin_analysis(self, image_data: str, user_id: int) -> dict:
    """
    Run full skin analysis pipeline with Base64 image input.
    """
    import base64
    import tempfile

    image_path = None   # ensure finally block can reference it safely

    # Decode base64 → temp file
    try:
        decoded = base64.b64decode(image_data)
        logger.info('Base64 decoded: %d bytes', len(decoded))
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
        tmp.write(decoded)
        image_path = tmp.name
        tmp.close()
    except Exception as e:
        logger.error('Base64 decode failed: %s', e)
        return {'status': 'error', 'message': 'Image decode failed'}

    try:
        from .skin_engine import analyse_face_image
        from .models import SkinAnalysisRecord
        from purepick_core.models import User

        logger.info('Task %s: starting dual-pass skin analysis for user %s',
                    self.request.id, user_id)

        report = analyse_face_image(image_path)
        error  = report.get('error')

        # ── Error handling ─────────────────────────────────────────────────────
        if error == 'no_face':
            return {
                'status':  'error',
                'error':   'no_face',
                'message': (
                    'No human face detected. Please take a clear, well-lit selfie '
                    'facing directly at the camera.'
                ),
            }

        if error and error.startswith('model_missing'):
            return {
                'status':  'error',
                'error':   'model_not_available',
                'message': 'Skin analysis model is not available on the server.',
            }

        if error:
            logger.error('analyse_face_image returned error: %s', error)
            return {'status': 'error', 'error': 'Skin analysis failed.'}

        # ── Persist to DB ──────────────────────────────────────────────────────
        record_id = None
        try:
            user_obj = User.objects.filter(id=user_id).first()
            rec = SkinAnalysisRecord.objects.create(
                user=user_obj,
                skin_type=report.get('skin_type') or '',
                skin_disorder=report.get('skin_disorder') or '',
                skin_type_confidence=report.get('skin_type_confidence', 0.0),
                skin_disorder_confidence=report.get('skin_disorder_confidence', 0.0),
                skin_conditions=json.dumps(report.get('skin_conditions', [])),
                ai_notes=report.get('ai_notes', ''),
                recommendations=json.dumps(report.get('recommendations', {})),
                analysis_source=report.get('analysis_source', 'unknown'),
            )
            record_id = rec.id
        except Exception as exc:
            logger.warning('Could not persist skin analysis record: %s', exc)

        # ── Build Flutter response ─────────────────────────────────────────────
        result = {
            # Core skin type
            'has_face':                     report.get('has_face', True),
            'skin_type':                    report.get('skin_type'),
            'skin_type_confidence':         report.get('skin_type_confidence', 0.0),

            # Primary condition (legacy + new)
            'skin_disorder':                report.get('skin_disorder'),
            'skin_disorder_confidence':     report.get('skin_disorder_confidence', 0.0),

            # Full conditions list — now includes zone + dark_circle_type fields
            'skin_conditions':              report.get('skin_conditions', []),

            # Zone-level analysis (new in v2)
            'zone_analysis':                report.get('zone_analysis', {}),

            # Flat condition score map for charts
            'condition_scores':             report.get('condition_scores', {}),

            # AI narrative
            'ai_notes':                     report.get('ai_notes', ''),
            'image_quality':                report.get('image_quality', 'unknown'),

            # Skincare recommendations
            'recommendations':              report.get('recommendations', {}),
            'condition_recommendations':    report.get('condition_recommendations', {}),

            # Score + metadata
            'overall_skin_health_score':    report.get('overall_skin_health_score', 75),
            'analysis_source':              report.get('analysis_source', 'unknown'),
            'disclaimer':                   MEDICAL_DISCLAIMER,
        }

        if record_id is not None:
            result['record_id'] = record_id

        logger.info(
            'Task %s: dual-pass analysis complete — type=%s conditions=%d score=%d source=%s',
            self.request.id,
            result['skin_type'],
            len(result['skin_conditions']),
            result['overall_skin_health_score'],
            result['analysis_source'],
        )
        return result

    except SoftTimeLimitExceeded:
        logger.error('Task %s: skin analysis timed out after 180s', self.request.id)
        return {
            'status':  'error',
            'error':   'timeout',
            'message': 'Skin analysis timed out. Please try again with a clearer image.',
        }

    except Exception as exc:
        logger.exception('Task %s: unexpected error: %s', self.request.id, exc)
        try:
            raise self.retry(exc=exc)
        except self.MaxRetriesExceededError:
            return {'status': 'error', 'error': 'Skin analysis failed after retries.'}

    finally:
        _safe_delete(image_path)


def _safe_delete(path: str) -> None:
    try:
        if path and os.path.exists(path):
            os.unlink(path)
    except Exception as exc:
        logger.warning('Could not delete temp file %s: %s', path, exc)

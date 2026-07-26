"""
purepick_core/notification_views.py
=====================================
FCM push notification endpoints.

Firebase was already configured in the app (google-services.json present)
but never used. This batch wires it up.

Flow:
  1. App registers FCM device token on login
     POST /api/notifications/register-token/
       { fcm_token: "..." }
       → stored on HealthProfile

  2. After scan completes with high/critical risk, a push is sent
     (called from scanner/tasks.py _persist_scan_record)

  3. User can opt out via preference stored in SharedPreferences
     (respected by the app; server always sends to registered tokens)
"""
import json
import logging

from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from django.http import JsonResponse

from purepick_core.auth_utils import jwt_required

logger = logging.getLogger(__name__)


@csrf_exempt
@jwt_required
@require_http_methods(['POST'])
def register_fcm_token(request):
    """
    POST /api/notifications/register-token/
    Body: { "fcm_token": "..." }
    JWT required — token stored against authenticated user.
    """
    try:
        data      = json.loads(request.body)
        fcm_token = data.get('fcm_token', '').strip()
        user_id   = request.auth_user_id

        if not fcm_token:
            return JsonResponse({'error': 'fcm_token is required'}, status=400)

        from purepick_core.models import HealthProfile
        profile, _ = HealthProfile.objects.get_or_create(user_id=user_id)
        profile.fcm_token = fcm_token
        profile.save(update_fields=['fcm_token'])

        logger.info('FCM token registered for user %s', user_id)
        return JsonResponse({'message': 'Token registered'})

    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON body'}, status=400)
    except Exception as exc:
        logger.error('register_fcm_token error: %s', exc)
        return JsonResponse({'error': 'Failed to register token'}, status=500)


def send_scan_risk_notification(user_id: int, product_name: str,
                                risk_level: str, flagged_count: int) -> bool:
    """
    Send a push notification to a user after a high-risk scan.
    Called from scanner/tasks._persist_scan_record().

    Returns True if notification was sent, False otherwise.
    Only sends for 'high' risk level — moderate and safe are silent.
    """
    if risk_level.lower() not in ('high', 'high risk'):
        return False   # Only alert on high risk

    try:
        from purepick_core.models import HealthProfile
        profile = HealthProfile.objects.filter(user_id=user_id).first()

        if not profile or not getattr(profile, 'fcm_token', None):
            return False   # User has no registered FCM token

        fcm_token = profile.fcm_token
        return _send_fcm(
            token=fcm_token,
            title='🚨 High Risk Product Detected',
            body=(
                f'"{product_name}" triggered {flagged_count} '
                f'allergen alert{"s" if flagged_count != 1 else ""}. '
                f'Tap to view details.'
            ),
            data={'screen': 'history', 'risk_level': risk_level},
        )

    except Exception as exc:
        logger.error('send_scan_risk_notification error: %s', exc)
        return False


def _send_fcm(token: str, title: str, body: str, data: dict = None) -> bool:
    """
    Send a single FCM push notification via Firebase Admin SDK.

    Requires FIREBASE_CREDENTIALS_PATH in settings (path to service account JSON).
    Falls back gracefully if firebase_admin is not installed.
    """
    from django.conf import settings

    credentials_path = getattr(settings, 'FIREBASE_CREDENTIALS_PATH', None)
    if not credentials_path:
        logger.debug('FIREBASE_CREDENTIALS_PATH not set — FCM notifications disabled')
        return False

    try:
        import firebase_admin
        from firebase_admin import credentials, messaging

        # Initialize app once (singleton pattern)
        if not firebase_admin._apps:
            cred = credentials.Certificate(credentials_path)
            firebase_admin.initialize_app(cred)

        message = messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            android=messaging.AndroidConfig(priority='high'),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound='default'),
                ),
            ),
        )

        messaging.send(message)
        logger.info('FCM notification sent to token ...%s', token[-6:])
        return True

    except ImportError:
        logger.debug('firebase_admin not installed — FCM disabled. Run: pip install firebase-admin')
        return False
    except Exception as exc:
        logger.warning('FCM send failed: %s', exc)
        return False

"""
purepick_core/password_reset_views.py
======================================
Forgot-password flow:
  1. POST /api/password-reset/request/   { username_or_email }
       → creates PasswordResetToken, emails the link
       → always returns 200 (no user enumeration)

  2. POST /api/password-reset/confirm/   { token, new_password }
       → validates token, sets new argon2 password, deletes token

Security:
  - UUID4 tokens (128-bit entropy)
  - Tokens expire after 1 hour
  - Old tokens deleted on new request (no token accumulation)
  - Generic "if account exists, email sent" response (no enumeration)
  - New password validated for minimum length
  - Token deleted immediately after use (single-use)
"""
import json
import logging
import re

from django.conf import settings
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from django.http import JsonResponse
from django.utils import timezone

from .models import User, PasswordResetToken
from .auth_utils import hash_password

logger = logging.getLogger(__name__)


@csrf_exempt
@require_http_methods(['POST'])
def request_password_reset(request):
    """
    POST /api/password-reset/request/
    Body: { "username_or_email": "..." }

    Creates a reset token and sends it by email.
    Always returns 200 — never reveals whether the account exists.
    """
    try:
        data = json.loads(request.body)
        identifier = data.get('username_or_email', '').strip()

        if not identifier:
            return JsonResponse(
                {'message': 'If an account with that identifier exists, a reset link has been sent.'},
                status=200,
            )

        # Lookup by username OR email
        user = (
            User.objects.filter(username=identifier).first()
            or User.objects.filter(email=identifier).first()
        )

        if user:
            # Delete any existing tokens for this user (avoid accumulation)
            PasswordResetToken.objects.filter(user=user).delete()
            token_obj = PasswordResetToken.objects.create(user=user)

            _send_reset_email(user, str(token_obj.token))
            logger.info('Password reset token created for user %s', user.id)

        # Always return same response — prevents user enumeration
        return JsonResponse({
            'message': 'If an account with that identifier exists, a reset link has been sent.',
        })

    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON body'}, status=400)
    except Exception as exc:
        logger.error('request_password_reset error: %s', exc)
        # Still return success to avoid leaking info
        return JsonResponse({
            'message': 'If an account with that identifier exists, a reset link has been sent.',
        })


@csrf_exempt
@require_http_methods(['POST'])
def confirm_password_reset(request):
    """
    POST /api/password-reset/confirm/
    Body: { "token": "<uuid>", "new_password": "..." }

    Validates token, sets new password, deletes token.
    """
    try:
        data         = json.loads(request.body)
        raw_token    = data.get('token', '').strip()
        new_password = data.get('new_password', '').strip()

        if not raw_token or not new_password:
            return JsonResponse({'error': 'token and new_password are required'}, status=400)

        pwd_error = _validate_password(new_password)
        if pwd_error:
            return JsonResponse({'error': pwd_error}, status=400)

        try:
            token_obj = PasswordResetToken.objects.select_related('user').get(
                token=raw_token,
                expires_at__gt=timezone.now(),  # only valid (unexpired) tokens
            )
        except PasswordResetToken.DoesNotExist:
            return JsonResponse({'error': 'Invalid or expired reset token'}, status=400)

        # Set new password
        user = token_obj.user
        user.password = hash_password(new_password)
        user.save(update_fields=['password'])

        # Delete token — single use
        token_obj.delete()

        logger.info('Password reset completed for user %s', user.id)
        return JsonResponse({'message': 'Password reset successfully. Please log in.'})

    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON body'}, status=400)
    except Exception as exc:
        logger.error('confirm_password_reset error: %s', exc)
        return JsonResponse({'error': 'Reset failed'}, status=500)


def _validate_password(password: str):
    if len(password) < 8:
        return 'Password must be at least 8 characters long.'
    if not re.search(r'[A-Za-z]', password):
        return 'Password must contain at least one letter (a-z or A-Z).'
    if not re.search(r'[0-9]', password):
        return 'Password must contain at least one number (0-9).'
    return None


def _send_reset_email(user: User, token: str) -> None:
    """
    Send the password reset email.

    In production: configure EMAIL_BACKEND in settings.prod.py
    (e.g. SendGrid, AWS SES, or SMTP).

    For development: Django's console backend prints to stdout.
    Set EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'
    """
    try:
        from django.core.mail import send_mail

        app_name  = 'PurePick'
        reset_url = f'{getattr(settings, "FRONTEND_BASE_URL", "purepick://")}/reset-password?token={token}'

        subject = f'{app_name} — Password Reset Request'
        body    = (
            f'Hi {user.name},\n\n'
            f'You requested a password reset for your {app_name} account.\n\n'
            f'Click the link below to reset your password:\n{reset_url}\n\n'
            f'This link expires in 1 hour.\n\n'
            f'If you did not request this, you can safely ignore this email.\n\n'
            f'— The {app_name} Team'
        )

        send_mail(
            subject=subject,
            message=body,
            from_email=getattr(settings, 'DEFAULT_FROM_EMAIL', f'noreply@purepick.app'),
            recipient_list=[user.email] if user.email else [],
            fail_silently=True,   # log errors, never crash the view
        )
        logger.info('Reset email sent to user %s', user.id)

    except Exception as exc:
        logger.error('Failed to send reset email to user %s: %s', user.id, exc)

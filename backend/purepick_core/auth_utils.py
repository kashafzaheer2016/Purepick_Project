"""
purepick_core/auth_utils.py
===========================
Centralised auth helpers:
  - argon2 password hashing  (replaces bare SHA-256)
  - JWT token pair generation
  - Google ID token server-side verification
  - Request ownership guard decorator

⚠ SECURITY: All password operations MUST go through this module.
"""
from __future__ import annotations

import logging
from functools import wraps
from typing import Optional

from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.http import JsonResponse

logger = logging.getLogger(__name__)


# ── Password hashing ──────────────────────────────────────────────────────────

def hash_password(raw_password: str) -> str:
    """
    Hash a raw password using Django's argon2 hasher.
    Falls back to pbkdf2_sha256 if argon2-cffi is not installed.
    The returned string includes the algorithm, salt, and hash — safe to store directly.

    WHY argon2: memory-hard, resistant to GPU brute-force, OWASP recommended.
    Old SHA-256 was unsalted — identical passwords produced identical hashes.
    """
    return make_password(raw_password)


def verify_password(raw_password: str, encoded: str) -> bool:
    """
    Verify a raw password against a stored Django-encoded hash.
    Works with argon2, pbkdf2_sha256, and legacy SHA-256 hashes.
    """
    # ⚠ EDGE CASE: Legacy SHA-256 hashes (len=64, no '$' separator) from old codebase.
    # Detect and handle gracefully so existing users aren't locked out during migration.
    if len(encoded) == 64 and '$' not in encoded:
        import hashlib
        return hashlib.sha256(raw_password.encode()).hexdigest() == encoded
    return check_password(raw_password, encoded)


def needs_rehash(encoded: str) -> bool:
    """
    Returns True if the stored hash is a legacy SHA-256 that should be
    upgraded to argon2 on next successful login.
    """
    return len(encoded) == 64 and '$' not in encoded


# ── JWT token pair ────────────────────────────────────────────────────────────

def generate_tokens_for_user(user) -> dict:
    """
    Generate an access + refresh JWT pair for a PurePick User instance.
    Uses djangorestframework-simplejwt with a custom payload.

    Returns:
        {
            "access":  "<jwt>",
            "refresh": "<jwt>",
            "user_id": int,
            "name":    str,
            "username": str,
        }
    """
    from rest_framework_simplejwt.tokens import RefreshToken

    refresh = RefreshToken()
    # Add custom claims — available in every decoded token
    refresh['user_id'] = user.id
    refresh['username'] = user.username
    refresh['name'] = user.name

    logger.debug('Generated tokens for user %s (%s)', user.id, user.username)

    return {
        'access': str(refresh.access_token),
        'refresh': str(refresh),
        'user_id': user.id,
        'name': user.name,
        'username': user.username,
    }


# ── Google OAuth server-side verification ────────────────────────────────────

def verify_google_token(id_token: str) -> Optional[dict]:
    """
    Verify a Google ID token using the google-auth library.
    Returns the decoded payload dict on success, None on failure.

    WHY: The old implementation just base64-decoded the JWT payload without
    verifying the signature — any forged token would pass. This calls Google's
    public key endpoint to cryptographically verify the token.

    Requires GOOGLE_CLIENT_ID to be set in settings.
    """
    client_id = getattr(settings, 'GOOGLE_CLIENT_ID', '')
    if not client_id:
        logger.error('GOOGLE_CLIENT_ID not configured — cannot verify Google tokens')
        return None

    try:
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests as google_requests

        payload = google_id_token.verify_oauth2_token(
            id_token,
            google_requests.Request(),
            client_id,
        )
        return payload
    except ValueError as exc:
        logger.warning('Google token verification failed: %s', exc)
        return None
    except Exception as exc:
        logger.error('Unexpected error verifying Google token: %s', exc)
        return None


# ── Ownership guard decorator ─────────────────────────────────────────────────

def require_own_user(url_kwarg: str = 'user_id'):
    """
    Decorator for function-based views that ensures the authenticated user
    can only access their own resources.

    Usage:
        @require_own_user('user_id')
        def get_history(request, user_id):
            ...

    The decorator reads request.auth_user_id (set by jwt_required) and
    compares it to the URL kwarg. Returns 403 on mismatch.
    """
    def decorator(view_func):
        @wraps(view_func)
        def wrapped(request, *args, **kwargs):
            target_id = kwargs.get(url_kwarg)
            if target_id is None:
                logger.error('require_own_user: %s missing from kwargs', url_kwarg)
                return JsonResponse({'error': 'Missing user identifier'}, status=400)

            if request.auth_user_id != int(target_id):
                logger.warning('Access denied for user %s to resource owned by %s', request.auth_user_id, target_id)
                return JsonResponse({'error': 'Access denied'}, status=403)

            return view_func(request, *args, **kwargs)
        return wrapped
    return decorator


def jwt_required(view_func):
    """
    Decorator that validates the Bearer JWT on every request and attaches
    request.auth_user_id for downstream use.

    WHY manual validation instead of JWTAuthentication:
    The User model in this project is a plain models.Model, not a subclass
    of AbstractBaseUser. DRF's JWTAuthentication tries to fetch the user from
    the default auth system, which fails here. We just need to verify the
    token signature/expiry and extract the user_id claim.
    """
    @wraps(view_func)
    def wrapped(request, *args, **kwargs):
        from rest_framework_simplejwt.tokens import AccessToken
        from rest_framework_simplejwt.exceptions import TokenError

        auth_header = request.headers.get('Authorization', '')
        if not auth_header.startswith('Bearer '):
            logger.warning('Missing or invalid Authorization header')
            return JsonResponse({'error': 'Authentication required'}, status=401)

        raw_token = auth_header.split(' ')[1]
        try:
            token = AccessToken(raw_token)
            user_id = token.get('user_id')
            if not user_id:
                logger.error('Token missing user_id claim')
                return JsonResponse({'error': 'Invalid token claims'}, status=401)

            request.auth_user_id = user_id
        except TokenError as exc:
            logger.warning('JWT validation failed: %s', exc)
            return JsonResponse({'error': str(exc)}, status=401)
        except Exception as exc:
            logger.error('Unexpected error during JWT validation: %s', exc)
            return JsonResponse({'error': 'Invalid token'}, status=401)

        return view_func(request, *args, **kwargs)
    return wrapped

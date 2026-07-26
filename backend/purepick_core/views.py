"""
purepick_core/views.py
======================
Auth, profile, history, and saved-product endpoints.

Security changes vs original:
  ✓ argon2 password hashing (via auth_utils.hash_password)
  ✓ Legacy SHA-256 hash upgrade on next login (needs_rehash)
  ✓ JWT token pair returned on register/login (generate_tokens_for_user)
  ✓ Google OAuth tokens verified server-side via google-auth (verify_google_token)
  ✓ All mutating endpoints require a valid JWT (jwt_required)
  ✓ User can only access their own data (require_own_user)
  ✓ Input validation tightened
  ✓ Debug print statements removed
"""
import json
import logging
import re

from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from django.http import JsonResponse

from .models import User, HealthProfile, ScanRecord, SavedProduct
from .auth_utils import (
    hash_password,
    verify_password,
    needs_rehash,
    generate_tokens_for_user,
    verify_google_token,
    jwt_required,
    require_own_user,
)

logger = logging.getLogger(__name__)


def _validate_password(password: str) -> str | None:
    """
    Returns an error message string if password is invalid, or None if valid.
    Rules:
      - At least 8 characters
      - At least one letter (a-z or A-Z)
      - At least one digit (0-9)
      - Special characters are optional
    """
    if len(password) < 8:
        return 'Password must be at least 8 characters long.'
    if not re.search(r'[A-Za-z]', password):
        return 'Password must contain at least one letter (a-z or A-Z).'
    if not re.search(r'[0-9]', password):
        return 'Password must contain at least one number (0-9).'
    return None


# ── Registration ──────────────────────────────────────────────────────────────

@csrf_exempt
@require_http_methods(['POST'])
def register_user(request):
    """
    POST /api/register/
    Body: { name, username, password }
    Returns: JWT pair + user info
    """
    try:
        data = json.loads(request.body)
        name     = data.get('name', '').strip()
        username = data.get('username', '').strip()
        password = data.get('password', '').strip()
        email    = data.get('email', '').strip().lower()

        if not all([name, username, password, email]):
            return JsonResponse({'error': 'name, username, email, and password are required'}, status=400)

        import re
        if not re.match(r'^[^@]+@[^@]+\.[^@]+$', email):
            return JsonResponse({'error': 'Please enter a valid email address'}, status=400)

        pwd_error = _validate_password(password)
        if pwd_error:
            return JsonResponse({'error': pwd_error}, status=400)

        if len(username) < 3:
            return JsonResponse({'error': 'Username must be at least 3 characters'}, status=400)

        if User.objects.filter(username=username).exists():
            return JsonResponse({'error': 'Username already taken'}, status=400)

        if User.objects.filter(email=email).exists():
            return JsonResponse({'error': 'An account with this email already exists'}, status=400)

        user = User.objects.create(
            name=name,
            username=username,
            email=email,
            password=hash_password(password),   # WHY: argon2, not SHA-256
        )
        HealthProfile.objects.create(user=user)

        tokens = generate_tokens_for_user(user)
        tokens.update({
            'skin_type': 'Normal',
            'gender':    'Other',
        })
        return JsonResponse(tokens, status=201)

    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON body'}, status=400)
    except Exception as exc:
        logger.error('register_user error: %s', exc)
        return JsonResponse({'error': 'Registration failed'}, status=500)


# ── Login ─────────────────────────────────────────────────────────────────────

@csrf_exempt
@require_http_methods(['POST'])
def login_user(request):
    """
    POST /api/login/
    Body: { username, password }
    Returns: JWT pair + user info

    Upgrades legacy SHA-256 hashes to argon2 transparently on successful login.
    """
    try:
        data = json.loads(request.body)
        username = data.get('username', '').strip()
        password = data.get('password', '').strip()

        if not username or not password:
            return JsonResponse({'error': 'username and password are required'}, status=400)

        user = User.objects.filter(username=username).first()
        if not user:
            # WHY: same error message for wrong user/pass to prevent username enumeration
            return JsonResponse({'error': 'Invalid credentials'}, status=401)

        if not verify_password(password, user.password):
            return JsonResponse({'error': 'Invalid credentials'}, status=401)

        # ⚠ EDGE CASE: Upgrade legacy SHA-256 hash to argon2 silently
        if needs_rehash(user.password):
            user.password = hash_password(password)
            user.save(update_fields=['password'])
            logger.info('Upgraded password hash for user %s to argon2', user.id)

        from django.utils import timezone
        now = timezone.now()
        today = now.date()

        # ── Streak Logic ──────────────────────────────────────────────────────
        if user.last_streak_date:
            yesterday = today - timezone.timedelta(days=1)
            if user.last_streak_date == yesterday:
                user.current_streak += 1
            elif user.last_streak_date < yesterday:
                user.current_streak = 1
            # if already today, do nothing
        else:
            user.current_streak = 1

        user.last_streak_date = today
        if user.current_streak > user.best_streak:
            user.best_streak = user.current_streak

        user.last_login = now
        user.save(update_fields=['last_login', 'current_streak', 'last_streak_date', 'best_streak'])

        tokens = generate_tokens_for_user(user)
        # Add profile info for immediate UI hydration
        tokens.update({
            'skin_type': user.profile.skin_type,
            'gender':    user.profile.gender,
        })
        return JsonResponse(tokens)

    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON body'}, status=400)
    except Exception as exc:
        logger.error('login_user error: %s', exc)
        return JsonResponse({'error': 'Login failed'}, status=500)


# ── Google OAuth Login ────────────────────────────────────────────────────────

@csrf_exempt
@require_http_methods(['POST'])
def google_login(request):
    """
    POST /api/google-login/
    Body: { token: "<google_id_token>" }
    Returns: JWT pair + user info

    WHY: Original decoded JWT payload with base64 only — no signature check.
    Now uses google-auth library to cryptographically verify the token against
    Google's public keys. GOOGLE_CLIENT_ID must be set in settings.
    """
    try:
        data = json.loads(request.body)
        id_token = data.get('token', '').strip()

        if not id_token:
            return JsonResponse({'error': 'token is required'}, status=400)

        payload = verify_google_token(id_token)
        if not payload:
            return JsonResponse({'error': 'Invalid or expired Google token'}, status=401)

        email = payload.get('email', '')
        name  = payload.get('name', 'Google User')

        if not email:
            return JsonResponse({'error': 'Google token missing email claim'}, status=400)

        # Derive a stable username from the email
        username = email.replace('@', '_at_').replace('.', '_')
        user = User.objects.filter(username=username).first()
        is_new_user = False

        if not user:
            # First-time Google login — create account with unusable password
            from django.contrib.auth.hashers import make_password as _make_unusable
            user = User.objects.create(
                name=name,
                username=username,
                email=email,                     # save email so password reset works
                password=_make_unusable('!'),
            )
            HealthProfile.objects.create(user=user)
            logger.info('Created new user %s via Google OAuth', user.id)
            is_new_user = True
        elif not user.email and email:
            # Backfill email for existing Google users who were created without it
            user.email = email
            user.save(update_fields=['email'])

        from django.utils import timezone
        now = timezone.now()
        today = now.date()

        # ── Streak Logic ──────────────────────────────────────────────────────
        if user.last_streak_date:
            yesterday = today - timezone.timedelta(days=1)
            if user.last_streak_date == yesterday:
                user.current_streak += 1
            elif user.last_streak_date < yesterday:
                user.current_streak = 1
        else:
            user.current_streak = 1

        user.last_streak_date = today
        if user.current_streak > user.best_streak:
            user.best_streak = user.current_streak

        user.last_login = now
        user.save(update_fields=['last_login', 'current_streak', 'last_streak_date', 'best_streak'])

        tokens = generate_tokens_for_user(user)
        tokens.update({
            'skin_type':   user.profile.skin_type,
            'gender':      user.profile.gender,
            'is_new_user': is_new_user,
        })
        return JsonResponse(tokens)

    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON body'}, status=400)
    except Exception as exc:
        logger.error('google_login error: %s', exc)
        return JsonResponse({'error': 'Google login failed'}, status=500)


# ── Token Refresh ─────────────────────────────────────────────────────────────

@csrf_exempt
@require_http_methods(['POST'])
def refresh_token(request):
    """
    POST /api/token/refresh/
    Body: { refresh: "<refresh_token>" }
    Returns: { access: "<new_access_token>" }
    """
    try:
        from rest_framework_simplejwt.tokens import RefreshToken
        from rest_framework_simplejwt.exceptions import TokenError

        data = json.loads(request.body)
        raw_refresh = data.get('refresh', '').strip()

        if not raw_refresh:
            return JsonResponse({'error': 'refresh token is required'}, status=400)

        token = RefreshToken(raw_refresh)
        return JsonResponse({'access': str(token.access_token)})

    except Exception:
        return JsonResponse({'error': 'Invalid or expired refresh token'}, status=401)


# ── Logout (blacklist refresh token) ─────────────────────────────────────────

@csrf_exempt
@jwt_required
@require_http_methods(['POST'])
def logout_user(request):
    """
    POST /api/logout/
    Body: { refresh: "<refresh_token>" }
    Blacklists the refresh token so it cannot be reused.
    """
    try:
        from rest_framework_simplejwt.tokens import RefreshToken

        data = json.loads(request.body)
        raw_refresh = data.get('refresh', '').strip()

        if raw_refresh:
            token = RefreshToken(raw_refresh)
            token.blacklist()

        return JsonResponse({'message': 'Logged out successfully'})
    except Exception:
        # Treat as success — token may already be blacklisted
        return JsonResponse({'message': 'Logged out'})


@csrf_exempt
@jwt_required
@require_http_methods(['DELETE'])
def delete_account(request):
    """
    DELETE /api/delete-account/
    Permanently deletes the authenticated user's account and all their data.
    Requires a valid JWT. No going back.
    """
    try:
        user = User.objects.filter(id=request.auth_user_id).first()
        if not user:
            return JsonResponse({'error': 'User not found'}, status=404)
        user_id = user.id
        user.delete()   # cascades to HealthProfile, ScanRecord, SavedProduct etc.
        logger.info('Account permanently deleted: user_id=%s', user_id)
        return JsonResponse({'message': 'Account deleted successfully'})
    except Exception as exc:
        logger.error('delete_account error: %s', exc)
        return JsonResponse({'error': 'Failed to delete account'}, status=500)


# ── Profile ───────────────────────────────────────────────────────────────────

@csrf_exempt
@jwt_required
@require_http_methods(['POST'])
def update_profile(request):
    """
    POST /api/profile/update/
    Body: { allergies, skin_conditions, custom_allergens }
    JWT required — user_id taken from token, not body.
    """
    try:
        data = json.loads(request.body)
        user_id = request.auth_user_id       # WHY: from verified JWT, not user-supplied body

        user = User.objects.filter(id=user_id).first()
        if not user:
            return JsonResponse({'error': 'User not found'}, status=404)

        profile, _ = HealthProfile.objects.get_or_create(user=user)

        # ── M2M allergy tags ──────────────────────────────────────────────────
        if 'allergies' in data:
            from .models import AllergyTag
            allergy_names = data['allergies']
            if isinstance(allergy_names, str):
                allergy_names = [a.strip() for a in allergy_names.split(',') if a.strip()]
            tags = []
            for name in allergy_names:
                tag, _ = AllergyTag.objects.get_or_create(
                    name=name,
                    defaults={'is_preset': False},
                )
                tags.append(tag)
            profile.allergy_tags.set(tags)

        if 'skin_type' in data:
            profile.skin_type = data['skin_type']
        if 'gender' in data:
            profile.gender = data['gender']
        if 'age' in data:
            try:
                profile.age = int(data['age'])
            except (ValueError, TypeError):
                pass

        # ── M2M skin condition tags ───────────────────────────────────────────
        if 'skin_conditions' in data:
            from .models import SkinConditionTag
            condition_names = data['skin_conditions']
            if isinstance(condition_names, str):
                condition_names = [c.strip() for c in condition_names.split(',') if c.strip()]
            tags = []
            for name in condition_names:
                tag, _ = SkinConditionTag.objects.get_or_create(
                    name=name,
                    defaults={'is_preset': False},
                )
                tags.append(tag)
            profile.skin_condition_tags.set(tags)

            # ⚠ LEGACY SYNC: Store in legacy text field for AI tasks that still use it
            profile.skin_conditions_legacy = ", ".join(condition_names)

        # ── LEGACY SYNC: Store in legacy text field for AI tasks ─────────────
        if 'allergies' in data:
            allergy_names = data['allergies']
            if isinstance(allergy_names, str):
                profile.allergies_legacy = allergy_names
            else:
                profile.allergies_legacy = ", ".join(allergy_names)

        if 'custom_allergens' in data:
            profile.custom_allergens = data['custom_allergens']

        profile.save()
        return JsonResponse({'message': 'Profile updated successfully'})

    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON body'}, status=400)
    except Exception as exc:
        logger.error('update_profile error: %s', exc)
        return JsonResponse({'error': 'Update failed'}, status=500)


@jwt_required
@require_own_user('user_id')
def get_profile(request, user_id):
    """
    GET /api/profile/<user_id>/
    JWT required + ownership enforced.
    """
    try:
        user = User.objects.filter(id=user_id).first()
        if not user:
            return JsonResponse({'error': 'User not found'}, status=404)

        profile, _ = HealthProfile.objects.get_or_create(user=user)
        return JsonResponse({
            'user_id':        user.id,
            'name':           user.name,
            'username':       user.username,
            'email':           user.email,
            'skin_type':       profile.skin_type,
            'gender':          profile.gender,
            'age':             getattr(profile, 'age', None),
            'allergies':       profile.get_allergies_list(),
            'skin_conditions': profile.get_skin_conditions_list(),
            'custom_allergens': profile.get_custom_allergens_list(),
        })

    except Exception as exc:
        logger.error('get_profile error: %s', exc)
        return JsonResponse({'error': 'Failed to load profile'}, status=500)


# ── Scan History ──────────────────────────────────────────────────────────────

@jwt_required
@require_own_user('user_id')
def get_history(request, user_id):
    """
    GET /api/history/<user_id>/
    JWT required + ownership enforced. Optimized for mobile payloads.
    """
    try:
        # Optimization: only fetch fields needed for the list view
        scans = ScanRecord.objects.filter(user_id=user_id).only(
            'id', 'product_name', 'safety_score', 'risk_level', 'scanned_at'
        ).order_by('-scanned_at')[:20] # Limit to 20 for payload stability

        data = [
            {
                'id': s.id,
                'product_name': s.product_name,
                'score': s.safety_score,
                'risk_level': s.risk_level,
                'date': s.scanned_at.strftime('%Y-%m-%d %H:%M'),
            }
            for s in scans
        ]
        return JsonResponse(data, safe=False)

    except Exception as exc:
        logger.error('get_history error: %s', exc)
        return JsonResponse({'error': 'Failed to load history'}, status=500)
        return JsonResponse({'error': 'Failed to load history'}, status=500)


# ── Saved Products ────────────────────────────────────────────────────────────

@csrf_exempt
@jwt_required
@require_http_methods(['POST'])
def save_product(request):
    """
    POST /api/saved/add/
    JWT required — user_id taken from verified token.
    """
    try:
        data = json.loads(request.body)
        user_id = request.auth_user_id

        user = User.objects.filter(id=user_id).first()
        if not user:
            return JsonResponse({'error': 'User not found'}, status=404)

        saved = SavedProduct.objects.create(
            user=user,
            name=data.get('name') or 'Unknown Product',
            brand=data.get('brand') or '',
            safety_score=int(data.get('score') or 0),
            risk_level=data.get('risk_level') or 'moderate',
            ingredients=data.get('ingredients') or '',
        )
        return JsonResponse({'message': 'Product saved', 'id': saved.id})

    except (json.JSONDecodeError, ValueError) as exc:
        return JsonResponse({'error': f'Invalid request: {exc}'}, status=400)
    except Exception as exc:
        logger.error('save_product error: %s', exc)
        return JsonResponse({'error': 'Save failed'}, status=500)


@jwt_required
@require_own_user('user_id')
def get_saved(request, user_id):
    """
    GET /api/saved/<user_id>/
    JWT required + ownership enforced.
    """
    try:
        products = SavedProduct.objects.filter(user_id=user_id).order_by('-saved_at')
        data = [
            {
                'id': p.id,
                'name': p.name,
                'brand': p.brand,
                'safety_score': p.safety_score,
                'risk_level': p.risk_level,
                'ingredients': p.ingredients,
                'date': p.saved_at.strftime('%b %d, %Y'),
                'saved_at': p.saved_at.isoformat(),
            }
            for p in products
        ]
        return JsonResponse(data, safe=False)

    except Exception as exc:
        logger.error('get_saved error: %s', exc)
        return JsonResponse({'error': 'Failed to load saved products'}, status=500)


@csrf_exempt
@jwt_required
def delete_saved(request, product_id):
    """
    DELETE /api/saved/delete/<product_id>/
    JWT required. Ownership check: only delete if the product belongs to the
    authenticated user.
    """
    try:
        deleted_count, _ = SavedProduct.objects.filter(
            id=product_id,
            user_id=request.auth_user_id,   # WHY: ownership guard inline
        ).delete()

        if deleted_count == 0:
            return JsonResponse({'error': 'Product not found or access denied'}, status=404)

        return JsonResponse({'message': 'Deleted'})

    except Exception as exc:
        logger.error('delete_saved error: %s', exc)
        return JsonResponse({'error': 'Delete failed'}, status=500)

"""
tests/test_auth_utils.py
=========================
Unit and integration tests for purepick_core/auth_utils.py.

Covers:
  - hash_password / verify_password
  - Legacy SHA-256 detection + needs_rehash
  - generate_tokens_for_user
  - jwt_required decorator
  - require_own_user decorator
"""
import hashlib
import pytest
from unittest.mock import patch, MagicMock

from django.test import RequestFactory
from django.http import JsonResponse

from purepick_core.auth_utils import (
    hash_password,
    verify_password,
    needs_rehash,
    generate_tokens_for_user,
    jwt_required,
    require_own_user,
)

pytestmark = pytest.mark.unit


# ── Password hashing ──────────────────────────────────────────────────────────

class TestPasswordHashing:

    def test_hash_password_returns_string(self):
        h = hash_password('mypassword123')
        assert isinstance(h, str)
        assert len(h) > 20

    def test_hash_is_not_plaintext(self):
        h = hash_password('mypassword123')
        assert 'mypassword123' not in h

    def test_same_password_different_hashes(self):
        """argon2 uses a random salt — same password → different hashes."""
        h1 = hash_password('mypassword123')
        h2 = hash_password('mypassword123')
        assert h1 != h2   # random salt ensures this

    def test_verify_correct_password(self):
        h = hash_password('correctpass')
        assert verify_password('correctpass', h) is True

    def test_verify_wrong_password(self):
        h = hash_password('correctpass')
        assert verify_password('wrongpass', h) is False

    def test_verify_legacy_sha256_hash(self):
        """Backward compatibility: legacy SHA-256 hashes still verify."""
        raw = 'legacypassword'
        legacy_hash = hashlib.sha256(raw.encode()).hexdigest()
        assert verify_password(raw, legacy_hash) is True

    def test_verify_legacy_sha256_wrong_password(self):
        raw = 'legacypassword'
        legacy_hash = hashlib.sha256(raw.encode()).hexdigest()
        assert verify_password('wrongpassword', legacy_hash) is False


class TestNeedsRehash:

    def test_legacy_sha256_needs_rehash(self):
        legacy = hashlib.sha256(b'test').hexdigest()
        assert len(legacy) == 64
        assert needs_rehash(legacy) is True

    def test_argon2_hash_does_not_need_rehash(self):
        modern = hash_password('test')
        assert needs_rehash(modern) is False

    def test_pbkdf2_hash_does_not_need_rehash(self):
        """Any hash with $ separator is modern."""
        assert needs_rehash('pbkdf2_sha256$600000$salt$hash') is False


# ── JWT generation ────────────────────────────────────────────────────────────

class TestGenerateTokens:

    def test_returns_access_and_refresh(self, plain_user):
        tokens = generate_tokens_for_user(plain_user)
        assert 'access' in tokens
        assert 'refresh' in tokens
        assert 'user_id' in tokens
        assert 'name' in tokens
        assert 'username' in tokens

    def test_user_id_in_tokens(self, plain_user):
        tokens = generate_tokens_for_user(plain_user)
        assert tokens['user_id'] == plain_user.id

    def test_access_token_is_jwt_format(self, plain_user):
        tokens = generate_tokens_for_user(plain_user)
        parts = tokens['access'].split('.')
        assert len(parts) == 3   # header.payload.signature

    def test_refresh_token_is_jwt_format(self, plain_user):
        tokens = generate_tokens_for_user(plain_user)
        parts = tokens['refresh'].split('.')
        assert len(parts) == 3


# ── jwt_required decorator ────────────────────────────────────────────────────

class TestJwtRequired:

    def _make_view(self):
        @jwt_required
        def dummy_view(request):
            return JsonResponse({'user_id': request.auth_user_id})
        return dummy_view

    def test_valid_token_sets_auth_user_id(self, plain_user):
        tokens = generate_tokens_for_user(plain_user)
        factory = RequestFactory()
        request = factory.get('/')
        request.META['HTTP_AUTHORIZATION'] = f'Bearer {tokens["access"]}'
        view = self._make_view()
        response = view(request)
        assert response.status_code == 200
        import json
        data = json.loads(response.content)
        assert data['user_id'] == plain_user.id

    def test_missing_token_returns_401(self):
        factory = RequestFactory()
        request = factory.get('/')
        view = self._make_view()
        response = view(request)
        assert response.status_code == 401

    def test_invalid_token_returns_401(self):
        factory = RequestFactory()
        request = factory.get('/')
        request.META['HTTP_AUTHORIZATION'] = 'Bearer this.is.invalid'
        view = self._make_view()
        response = view(request)
        assert response.status_code == 401

    def test_malformed_header_returns_401(self):
        factory = RequestFactory()
        request = factory.get('/')
        request.META['HTTP_AUTHORIZATION'] = 'NotBearer token'
        view = self._make_view()
        response = view(request)
        assert response.status_code == 401


# ── require_own_user decorator ────────────────────────────────────────────────

class TestRequireOwnUser:

    def _make_protected_view(self):
        @jwt_required
        @require_own_user('user_id')
        def protected_view(request, user_id):
            return JsonResponse({'ok': True, 'user_id': user_id})
        return protected_view

    def test_owner_can_access_own_resource(self, plain_user):
        tokens = generate_tokens_for_user(plain_user)
        factory = RequestFactory()
        request = factory.get('/')
        request.META['HTTP_AUTHORIZATION'] = f'Bearer {tokens["access"]}'
        view = self._make_protected_view()
        response = view(request, user_id=plain_user.id)
        assert response.status_code == 200

    def test_other_user_gets_403(self, plain_user, allergic_user):
        """User trying to access another user's resource."""
        tokens = generate_tokens_for_user(plain_user)
        factory = RequestFactory()
        request = factory.get('/')
        request.META['HTTP_AUTHORIZATION'] = f'Bearer {tokens["access"]}'
        view = self._make_protected_view()
        # Try to access allergic_user's resource
        response = view(request, user_id=allergic_user.id)
        assert response.status_code == 403

    def test_no_token_gets_401(self, plain_user):
        factory = RequestFactory()
        request = factory.get('/')
        view = self._make_protected_view()
        response = view(request, user_id=plain_user.id)
        assert response.status_code == 401

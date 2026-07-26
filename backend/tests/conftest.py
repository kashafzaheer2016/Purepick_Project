"""
tests/conftest.py
=================
Shared pytest fixtures used across all test modules.

Fixture scope hierarchy:
  session  — created once for the entire test run (expensive: ML model load)
  module   — created once per test file
  function — default: fresh for every test (DB objects, API client)
"""
import json
import os
import pytest

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'purepick_core.settings.test')

import django
django.setup()

from django.test import TestCase, Client
from purepick_core.models import (
    User, HealthProfile, AllergyTag, SkinConditionTag, ScanRecord, SavedProduct,
)
from purepick_core.auth_utils import hash_password, generate_tokens_for_user


# ── User / Auth fixtures ──────────────────────────────────────────────────────

@pytest.fixture
def plain_user(db):
    """A basic user with no allergies or conditions."""
    user = User.objects.create(
        name='Test User',
        username='testuser',
        email='test@purepick.app',
        password=hash_password('testpass123'),
    )
    HealthProfile.objects.create(user=user)
    return user


@pytest.fixture
def allergic_user(db):
    """A user with fragrance + sulfate allergies and eczema."""
    user = User.objects.create(
        name='Allergic Alice',
        username='alice',
        email='alice@purepick.app',
        password=hash_password('alicepass123'),
    )
    profile = HealthProfile.objects.create(user=user)

    # Seed tags (normally done by migration)
    frag_tag, _   = AllergyTag.objects.get_or_create(name='Fragrance Allergy')
    sulfate_tag, _ = AllergyTag.objects.get_or_create(name='Sulfate Sensitivity')
    eczema_tag, _  = SkinConditionTag.objects.get_or_create(name='eczema')

    profile.allergy_tags.add(frag_tag, sulfate_tag)
    profile.skin_condition_tags.add(eczema_tag)
    return user


@pytest.fixture
def auth_client(plain_user):
    """Django test client with a valid JWT Bearer token."""
    tokens = generate_tokens_for_user(plain_user)
    client = Client()
    client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {tokens["access"]}'
    return client, plain_user, tokens


@pytest.fixture
def allergic_auth_client(allergic_user):
    """Django test client for the allergic user."""
    tokens = generate_tokens_for_user(allergic_user)
    client = Client()
    client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {tokens["access"]}'
    return client, allergic_user, tokens


# ── Profile fixture helpers ───────────────────────────────────────────────────

@pytest.fixture
def plain_profile():
    """Health profile dict (no allergies) — for unit tests without DB."""
    return {
        'allergies': [],
        'skin_conditions': [],
        'custom_allergens': [],
        'profile_missing': True,
    }


@pytest.fixture
def allergic_profile():
    """Health profile dict with fragrance + sulfate + eczema — for unit tests."""
    return {
        'allergies': ['fragrance allergy', 'sulfate sensitivity'],
        'skin_conditions': ['eczema'],
        'custom_allergens': [],
        'profile_missing': False,
    }


@pytest.fixture
def nut_allergy_profile():
    """Health profile with nut allergy."""
    return {
        'allergies': ['nut allergy'],
        'skin_conditions': [],
        'custom_allergens': [],
        'profile_missing': False,
    }


# ── Scan record fixture ───────────────────────────────────────────────────────

@pytest.fixture
def scan_record(db, plain_user):
    return ScanRecord.objects.create(
        user=plain_user,
        product_name='Test Cream',
        ingredients_raw='water, glycerin',
        safety_score=85,
        risk_level='safe',
        scan_source='manual',
    )

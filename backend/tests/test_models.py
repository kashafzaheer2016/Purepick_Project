"""
tests/test_models.py
=====================
Integration tests for database models.
Verifies schema correctness, M2M relationships, model methods,
and the PasswordResetToken lifecycle.
"""
import pytest
from django.utils import timezone
from datetime import timedelta

from purepick_core.models import (
    User, HealthProfile, AllergyTag, SkinConditionTag,
    ScanRecord, SavedProduct, PasswordResetToken,
)
from purepick_core.auth_utils import hash_password

pytestmark = pytest.mark.integration


# ── User model ────────────────────────────────────────────────────────────────

class TestUserModel:

    def test_user_creation(self, db, plain_user):
        assert plain_user.id is not None
        assert plain_user.username == 'testuser'
        assert plain_user.email == 'test@purepick.app'

    def test_password_not_plaintext(self, db, plain_user):
        assert 'testpass123' not in plain_user.password
        assert '$' in plain_user.password or len(plain_user.password) == 64

    def test_last_login_initially_none(self, db, plain_user):
        assert plain_user.last_login is None

    def test_last_login_can_be_set(self, db, plain_user):
        plain_user.last_login = timezone.now()
        plain_user.save()
        plain_user.refresh_from_db()
        assert plain_user.last_login is not None

    def test_username_unique(self, db, plain_user):
        from django.db import IntegrityError
        with pytest.raises(IntegrityError):
            User.objects.create(
                name='Dup',
                username=plain_user.username,
                password=hash_password('pass'),
            )


# ── HealthProfile + M2M ───────────────────────────────────────────────────────

class TestHealthProfileManyToMany:

    def test_allergy_tags_m2m(self, db, plain_user):
        tag, _ = AllergyTag.objects.get_or_create(name='Fragrance Allergy')
        profile = HealthProfile.objects.get(user=plain_user)
        profile.allergy_tags.add(tag)
        assert profile.allergy_tags.filter(name='Fragrance Allergy').exists()

    def test_get_allergies_list_from_m2m(self, db, plain_user):
        tag, _ = AllergyTag.objects.get_or_create(name='Nut Allergy')
        profile = HealthProfile.objects.get(user=plain_user)
        profile.allergy_tags.add(tag)
        allergies = profile.get_allergies_list()
        assert 'nut allergy' in allergies

    def test_skin_condition_tags_m2m(self, db, plain_user):
        tag, _ = SkinConditionTag.objects.get_or_create(name='eczema')
        profile = HealthProfile.objects.get(user=plain_user)
        profile.skin_condition_tags.add(tag)
        assert profile.skin_condition_tags.filter(name='eczema').exists()

    def test_get_skin_conditions_list(self, db, plain_user):
        tag, _ = SkinConditionTag.objects.get_or_create(name='rosacea')
        profile = HealthProfile.objects.get(user=plain_user)
        profile.skin_condition_tags.add(tag)
        conditions = profile.get_skin_conditions_list()
        assert 'rosacea' in conditions

    def test_get_allergies_fallback_to_legacy(self, db, plain_user):
        """When M2M is empty, falls back to legacy text field."""
        profile = HealthProfile.objects.get(user=plain_user)
        profile.allergies_legacy = 'Fragrance Allergy, Nut Allergy'
        profile.save()
        allergies = profile.get_allergies_list()
        assert 'fragrance allergy' in allergies
        assert 'nut allergy' in allergies

    def test_m2m_takes_priority_over_legacy(self, db, plain_user):
        """When M2M has data, legacy field is ignored."""
        tag, _ = AllergyTag.objects.get_or_create(name='Sulfate Sensitivity')
        profile = HealthProfile.objects.get(user=plain_user)
        profile.allergy_tags.add(tag)
        profile.allergies_legacy = 'Old Allergy'
        profile.save()
        allergies = profile.get_allergies_list()
        assert 'sulfate sensitivity' in allergies
        assert 'old allergy' not in allergies

    def test_custom_allergens_list(self, db, plain_user):
        profile = HealthProfile.objects.get(user=plain_user)
        profile.custom_allergens = 'cetearyl alcohol, dimethicone'
        profile.save()
        custom = profile.get_custom_allergens_list()
        assert 'cetearyl alcohol' in custom
        assert 'dimethicone' in custom

    def test_multiple_users_share_same_tag(self, db, plain_user, allergic_user):
        """Same AllergyTag can be shared across multiple HealthProfiles."""
        tag, _ = AllergyTag.objects.get_or_create(name='Paraben Sensitivity')
        p1 = HealthProfile.objects.get(user=plain_user)
        p2 = HealthProfile.objects.get(user=allergic_user)
        p1.allergy_tags.add(tag)
        p2.allergy_tags.add(tag)
        assert tag.profiles.count() == 2


# ── PasswordResetToken ────────────────────────────────────────────────────────

class TestPasswordResetToken:

    def test_token_created_with_uuid(self, db, plain_user):
        token = PasswordResetToken.objects.create(user=plain_user)
        assert token.token is not None
        assert str(token.token).count('-') == 4   # UUID4 format

    def test_token_is_valid_when_new(self, db, plain_user):
        token = PasswordResetToken.objects.create(user=plain_user)
        assert token.is_valid is True

    def test_token_invalid_when_expired(self, db, plain_user):
        token = PasswordResetToken.objects.create(
            user=plain_user,
            expires_at=timezone.now() - timedelta(seconds=1),
        )
        assert token.is_valid is False

    def test_token_deleted_after_use(self, db, plain_user):
        token = PasswordResetToken.objects.create(user=plain_user)
        token_id = token.id
        token.delete()
        assert not PasswordResetToken.objects.filter(id=token_id).exists()

    def test_old_tokens_replaced_on_new_request(self, db, plain_user):
        """When a new reset is requested, old tokens are deleted."""
        PasswordResetToken.objects.create(user=plain_user)
        PasswordResetToken.objects.create(user=plain_user)
        # Simulate new request: delete old tokens
        PasswordResetToken.objects.filter(user=plain_user).delete()
        PasswordResetToken.objects.create(user=plain_user)
        assert PasswordResetToken.objects.filter(user=plain_user).count() == 1


# ── ScanRecord ────────────────────────────────────────────────────────────────

class TestScanRecord:

    def test_scan_record_creation(self, db, scan_record):
        assert scan_record.id is not None
        assert scan_record.product_name == 'Test Cream'
        assert scan_record.risk_level == 'safe'
        assert scan_record.scan_source == 'manual'

    def test_get_flagged_list_parses_json(self, db, plain_user):
        import json
        record = ScanRecord.objects.create(
            user=plain_user,
            flagged_ingredients=json.dumps(['fragrance', 'methylparaben']),
            safety_score=40,
            risk_level='high',
        )
        flagged = record.get_flagged_list()
        assert 'fragrance' in flagged
        assert 'methylparaben' in flagged

    def test_get_flagged_list_handles_invalid_json(self, db, plain_user):
        record = ScanRecord.objects.create(
            user=plain_user,
            flagged_ingredients='not valid json',
            safety_score=50,
        )
        assert record.get_flagged_list() == []

    def test_scan_source_choices(self, db, plain_user):
        for source in ('manual', 'ocr', 'barcode'):
            record = ScanRecord.objects.create(
                user=plain_user, safety_score=70, scan_source=source)
            record.refresh_from_db()
            assert record.scan_source == source

    def test_barcode_field_stored(self, db, plain_user):
        record = ScanRecord.objects.create(
            user=plain_user,
            safety_score=80,
            barcode='3600523021382',
            scan_source='barcode',
        )
        record.refresh_from_db()
        assert record.barcode == '3600523021382'

    def test_ordering_newest_first(self, db, plain_user):
        ScanRecord.objects.create(user=plain_user, safety_score=80, product_name='First')
        ScanRecord.objects.create(user=plain_user, safety_score=70, product_name='Second')
        records = ScanRecord.objects.filter(user=plain_user)
        assert records[0].product_name == 'Second'   # newest first

    def test_cascade_delete_with_user(self, db, plain_user):
        ScanRecord.objects.create(user=plain_user, safety_score=80)
        user_id = plain_user.id
        plain_user.delete()
        assert ScanRecord.objects.filter(user_id=user_id).count() == 0


# ── AllergyTag ────────────────────────────────────────────────────────────────

class TestAllergyTag:

    def test_create_preset_tag(self, db):
        tag = AllergyTag.objects.create(name='Test Allergy', is_preset=True)
        assert tag.name == 'Test Allergy'
        assert tag.is_preset is True

    def test_tag_name_unique(self, db):
        from django.db import IntegrityError
        AllergyTag.objects.create(name='Unique Allergy')
        with pytest.raises(IntegrityError):
            AllergyTag.objects.create(name='Unique Allergy')

    def test_tag_str_representation(self, db):
        tag = AllergyTag.objects.create(name='My Allergy')
        assert str(tag) == 'My Allergy'

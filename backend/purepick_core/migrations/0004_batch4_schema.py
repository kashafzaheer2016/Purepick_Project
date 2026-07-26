"""
Migration 0004 — Batch 4 Schema + Data Migration

Operations:
  1. Create AllergyTag lookup table
  2. Create SkinConditionTag lookup table
  3. Add email + last_login to User
  4. Add M2M fields to HealthProfile
  5. Rename legacy TextField columns
  6. Create PasswordResetToken table
  7. Add scan_source + barcode to ScanRecord
  8. Add barcode to SavedProduct
  9. Add DB indexes
  10. Seed AllergyTag + SkinConditionTag with preset values
  11. DATA MIGRATION: move existing comma-text allergies → M2M rows
"""
from django.db import migrations, models
import django.db.models.deletion
import uuid

# Preset tags matching ingredient_intelligence.py maps
PRESET_ALLERGY_TAGS = [
    'Nut Allergy', 'Fragrance Allergy', 'Latex Allergy', 'Gluten Sensitivity',
    'Sulfate Sensitivity', 'Paraben Sensitivity', 'Alcohol Sensitivity',
    'Silicone Sensitivity', 'Lanolin Allergy', 'Formaldehyde Allergy',
    'Sunscreen Chemical Allergy', 'Nickel Allergy', 'Soy Allergy', 'Dairy Allergy',
]

PRESET_SKIN_CONDITION_TAGS = [
    'acne', 'eczema', 'rosacea', 'psoriasis',
    'sensitive skin', 'dry skin', 'oily skin', 'hyperpigmentation',
]


def seed_tags(apps, schema_editor):
    """Seed preset allergy and skin condition tags."""
    AllergyTag     = apps.get_model('purepick_core', 'AllergyTag')
    SkinConditionTag = apps.get_model('purepick_core', 'SkinConditionTag')

    for name in PRESET_ALLERGY_TAGS:
        AllergyTag.objects.get_or_create(name=name, defaults={'is_preset': True})

    for name in PRESET_SKIN_CONDITION_TAGS:
        SkinConditionTag.objects.get_or_create(name=name, defaults={'is_preset': True})


def migrate_legacy_data(apps, schema_editor):
    """
    Move existing comma-text allergies/skin_conditions into M2M tables.

    Strategy:
      - Read allergies_legacy (was 'allergies' before rename)
      - For each comma-separated value, find or create an AllergyTag
      - Link it to the HealthProfile M2M
      - Same for skin_conditions_legacy
    """
    HealthProfile    = apps.get_model('purepick_core', 'HealthProfile')
    AllergyTag       = apps.get_model('purepick_core', 'AllergyTag')
    SkinConditionTag = apps.get_model('purepick_core', 'SkinConditionTag')

    for profile in HealthProfile.objects.all():
        # Migrate allergy tags
        if profile.allergies_legacy:
            for raw in profile.allergies_legacy.split(','):
                name = raw.strip()
                if not name:
                    continue
                # Map common abbreviations from profile_setup_screen.dart
                name_map = {
                    'Fragrance': 'Fragrance Allergy',
                    'Parabens':  'Paraben Sensitivity',
                    'Sulfates':  'Sulfate Sensitivity',
                    'Gluten':    'Gluten Sensitivity',
                    'Nuts':      'Nut Allergy',
                    'Dairy':     'Dairy Allergy',
                    'Soy':       'Soy Allergy',
                    'Alcohol':   'Alcohol Sensitivity',
                }
                canonical = name_map.get(name, name)
                tag, _ = AllergyTag.objects.get_or_create(
                    name=canonical,
                    defaults={'is_preset': canonical in PRESET_ALLERGY_TAGS}
                )
                profile.allergy_tags.add(tag)

        # Migrate skin condition tags
        if profile.skin_conditions_legacy:
            for raw in profile.skin_conditions_legacy.split(','):
                name = raw.strip().lower()
                if not name or name == 'none':
                    continue
                tag, _ = SkinConditionTag.objects.get_or_create(
                    name=name,
                    defaults={'is_preset': name in PRESET_SKIN_CONDITION_TAGS}
                )
                profile.skin_condition_tags.add(tag)


def reverse_migrate(apps, schema_editor):
    """Reverse: copy M2M data back to legacy fields."""
    HealthProfile = apps.get_model('purepick_core', 'HealthProfile')
    for profile in HealthProfile.objects.all():
        allergies = [t.name for t in profile.allergy_tags.all()]
        conditions = [t.name for t in profile.skin_condition_tags.all()]
        if allergies:
            profile.allergies_legacy = ', '.join(allergies)
        if conditions:
            profile.skin_conditions_legacy = ', '.join(conditions)
        profile.save()


class Migration(migrations.Migration):

    dependencies = [
        ('purepick_core', '0003_scanrecord_ai_analysis_scanrecord_personal_warnings'),
    ]

    operations = [
        # ── 1. AllergyTag table ───────────────────────────────────────────────
        migrations.CreateModel(
            name='AllergyTag',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False)),
                ('name', models.CharField(max_length=100, unique=True)),
                ('is_preset', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
            ],
            options={'ordering': ['name']},
        ),
        migrations.AddIndex(
            model_name='allergytag',
            index=models.Index(fields=['name'], name='core_allergytag_name_idx'),
        ),

        # ── 2. SkinConditionTag table ─────────────────────────────────────────
        migrations.CreateModel(
            name='SkinConditionTag',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False)),
                ('name', models.CharField(max_length=100, unique=True)),
                ('is_preset', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
            ],
            options={'ordering': ['name']},
        ),
        migrations.AddIndex(
            model_name='skinconditiontag',
            index=models.Index(fields=['name'], name='core_skincondtag_name_idx'),
        ),

        # ── 3. User: email + last_login ───────────────────────────────────────
        migrations.AddField(
            model_name='user',
            name='email',
            field=models.EmailField(max_length=254, blank=True, default=''),
        ),
        migrations.AddField(
            model_name='user',
            name='last_login',
            field=models.DateTimeField(null=True, blank=True),
        ),
        migrations.AddIndex(
            model_name='user',
            index=models.Index(fields=['email'], name='core_user_email_idx'),
        ),

        # ── 4a. HealthProfile: rename legacy allergies field ──────────────────
        migrations.RenameField(
            model_name='healthprofile',
            old_name='allergies',
            new_name='allergies_legacy',
        ),
        # ── 4b. HealthProfile: rename legacy skin_conditions field ─────────────
        migrations.RenameField(
            model_name='healthprofile',
            old_name='skin_conditions',
            new_name='skin_conditions_legacy',
        ),
        # ── 4c. HealthProfile: M2M to AllergyTag ─────────────────────────────
        migrations.AddField(
            model_name='healthprofile',
            name='allergy_tags',
            field=models.ManyToManyField(
                to='purepick_core.allergytag',
                blank=True,
                related_name='profiles',
            ),
        ),
        # ── 4d. HealthProfile: M2M to SkinConditionTag ───────────────────────
        migrations.AddField(
            model_name='healthprofile',
            name='skin_condition_tags',
            field=models.ManyToManyField(
                to='purepick_core.skinconditiontag',
                blank=True,
                related_name='profiles',
            ),
        ),

        # ── 5. PasswordResetToken table ───────────────────────────────────────
        migrations.CreateModel(
            name='PasswordResetToken',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False)),
                ('token', models.UUIDField(default=uuid.uuid4, unique=True, db_index=True)),
                ('expires_at', models.DateTimeField()),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('user', models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='reset_tokens',
                    to='purepick_core.user',
                )),
            ],
        ),
        migrations.AddIndex(
            model_name='passwordresettoken',
            index=models.Index(fields=['token', 'expires_at'], name='core_resettoken_token_exp_idx'),
        ),

        # ── 6. ScanRecord: scan_source + barcode ──────────────────────────────
        migrations.AddField(
            model_name='scanrecord',
            name='scan_source',
            field=models.CharField(
                max_length=10,
                choices=[('manual','Manual'),('ocr','Camera OCR'),('barcode','Barcode')],
                default='manual',
            ),
        ),
        migrations.AddField(
            model_name='scanrecord',
            name='barcode',
            field=models.CharField(max_length=50, blank=True, default='', db_index=True),
        ),
        migrations.AddIndex(
            model_name='scanrecord',
            index=models.Index(fields=['user', '-scanned_at'], name='core_scan_user_date_idx'),
        ),
        migrations.AddIndex(
            model_name='scanrecord',
            index=models.Index(fields=['barcode'], name='core_scan_barcode_idx'),
        ),

        # ── 7. SavedProduct: barcode ──────────────────────────────────────────
        migrations.AddField(
            model_name='savedproduct',
            name='barcode',
            field=models.CharField(max_length=50, blank=True, default=''),
        ),

        # ── 8. Data migrations ────────────────────────────────────────────────
        migrations.RunPython(seed_tags, reverse_code=migrations.RunPython.noop),
        migrations.RunPython(migrate_legacy_data, reverse_code=reverse_migrate),
    ]

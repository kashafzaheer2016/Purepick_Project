"""
purepick_core/models.py — Batch 4
Batch 4 schema changes:
  + User: email field, last_login field
  + AllergyTag / SkinConditionTag: M2M lookup tables
  + HealthProfile: M2M to tags (legacy TextField kept for safe migration)
  + PasswordResetToken: UUID4 + expiry for forgot-password flow
  + ScanRecord: scan_source + barcode fields, DB indexes
"""
from __future__ import annotations
import json, uuid
from datetime import timedelta
from django.db import models
from django.utils import timezone


class AllergyTag(models.Model):
    name      = models.CharField(max_length=100, unique=True)
    is_preset = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    class Meta:
        ordering = ['name']
        indexes  = [models.Index(fields=['name'])]
    def __str__(self): return self.name


class SkinConditionTag(models.Model):
    name      = models.CharField(max_length=100, unique=True)
    is_preset = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    class Meta:
        ordering = ['name']
        indexes  = [models.Index(fields=['name'])]
    def __str__(self): return self.name


class User(models.Model):
    name       = models.CharField(max_length=200)
    username   = models.CharField(max_length=100, unique=True)
    email      = models.EmailField(max_length=254, blank=True, default='')
    password   = models.CharField(max_length=255)
    created_at = models.DateTimeField(auto_now_add=True)
    last_login = models.DateTimeField(null=True, blank=True)

    # Skincare Streak tracking
    current_streak = models.IntegerField(default=0)
    last_streak_date = models.DateField(null=True, blank=True)
    best_streak = models.IntegerField(default=0)

    class Meta:
        indexes = [models.Index(fields=['username']), models.Index(fields=['email'])]
    def __str__(self): return self.username


class HealthProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')

    # Explicit Structured Fields
    skin_type = models.CharField(max_length=50, blank=True, default='Normal')
    gender    = models.CharField(max_length=20, blank=True, default='Other')
    age       = models.PositiveSmallIntegerField(null=True, blank=True, help_text='User age in years')

    # M2M (new, authoritative post-migration)
    allergy_tags        = models.ManyToManyField('AllergyTag', blank=True, related_name='profiles')
    skin_condition_tags = models.ManyToManyField('SkinConditionTag', blank=True, related_name='profiles')

    # Free-text custom allergens
    custom_allergens = models.TextField(blank=True, default='')

    # Legacy fields — deprecated, kept for safety during migration
    allergies_legacy       = models.TextField(blank=True, default='')
    skin_conditions_legacy = models.TextField(blank=True, default='')

    fcm_token  = models.CharField(max_length=255, blank=True, default='',
                                    help_text='Firebase Cloud Messaging device token')
    updated_at = models.DateTimeField(auto_now=True)

    def get_allergies_list(self) -> list:
        m2m = list(self.allergy_tags.values_list('name', flat=True))
        if m2m:
            return [a.lower() for a in m2m]
        if self.allergies_legacy:
            return [a.strip().lower() for a in self.allergies_legacy.split(',') if a.strip()]
        return []

    def get_skin_conditions_list(self) -> list:
        m2m = list(self.skin_condition_tags.values_list('name', flat=True))
        if m2m:
            return [c.lower() for c in m2m]
        if self.skin_conditions_legacy:
            return [c.strip().lower() for c in self.skin_conditions_legacy.split(',') if c.strip()]
        return []

    def get_custom_allergens_list(self) -> list:
        if not self.custom_allergens:
            return []
        return [c.strip().lower() for c in self.custom_allergens.split(',') if c.strip()]

    def __str__(self): return f'Profile({self.user.username})'


def _token_expiry():
    return timezone.now() + timedelta(hours=1)


class PasswordResetToken(models.Model):
    """UUID4 one-time reset token. Expires 1h after creation."""
    user       = models.ForeignKey(User, on_delete=models.CASCADE, related_name='reset_tokens')
    token      = models.UUIDField(default=uuid.uuid4, unique=True, db_index=True)
    expires_at = models.DateTimeField(default=_token_expiry)
    created_at = models.DateTimeField(auto_now_add=True)
    class Meta:
        indexes = [models.Index(fields=['token', 'expires_at'])]
    @property
    def is_valid(self) -> bool:
        return timezone.now() < self.expires_at
    def __str__(self): return f'ResetToken({self.user.username})'


class ScanRecord(models.Model):
    RISK_CHOICES = [('safe','Safe'),('moderate','Moderate'),('high','High Risk')]
    SCAN_SOURCE_CHOICES = [('manual','Manual'),('ocr','Camera OCR'),('barcode','Barcode')]

    user               = models.ForeignKey(User, on_delete=models.CASCADE, related_name='scans')
    product_name       = models.CharField(max_length=300, blank=True, default='Scanned Product')
    ingredients_raw    = models.TextField(blank=True, default='')
    safety_score       = models.IntegerField(default=0)
    risk_level         = models.CharField(max_length=20, choices=RISK_CHOICES, default='moderate')
    flagged_ingredients = models.TextField(blank=True, default='[]')
    ai_analysis        = models.TextField(blank=True, default='')
    personal_warnings  = models.TextField(blank=True, default='')
    scan_source        = models.CharField(max_length=10, choices=SCAN_SOURCE_CHOICES, default='manual')
    barcode            = models.CharField(max_length=50, blank=True, default='', db_index=True)
    scanned_at         = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes  = [models.Index(fields=['user', '-scanned_at']), models.Index(fields=['barcode'])]
        ordering = ['-scanned_at']

    def get_flagged_list(self) -> list:
        try: return json.loads(self.flagged_ingredients)
        except: return []

    def __str__(self): return f'{self.user.username} | {self.product_name}'


class SavedProduct(models.Model):
    user         = models.ForeignKey(User, on_delete=models.CASCADE, related_name='saved_products')
    name         = models.CharField(max_length=300)
    brand        = models.CharField(max_length=200, blank=True, default='')
    safety_score = models.IntegerField(default=0)
    risk_level   = models.CharField(max_length=20, blank=True, default='moderate')
    ingredients  = models.TextField(blank=True, default='')
    barcode      = models.CharField(max_length=50, blank=True, default='')
    saved_at     = models.DateTimeField(auto_now_add=True)
    class Meta:
        indexes  = [models.Index(fields=['user', '-saved_at'])]
        ordering = ['-saved_at']
    def __str__(self): return f'{self.name} ({self.user.username})'


class SkinLog(models.Model):
    """Daily skin condition and routine tracking."""
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='skin_logs')
    date = models.DateField(default=timezone.now)
    condition_score = models.IntegerField(default=3) # 1-5
    tags = models.JSONField(default=list, blank=True) # e.g. ['Dry', 'Redness']
    am_routine_done = models.BooleanField(default=False)
    pm_routine_done = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'date')
        ordering = ['-date']

    def __str__(self):
        return f"SkinLog({self.user.username}, {self.date})"


class CleanProduct(models.Model):
    """Curated database of 'Safe' products for Clean Swaps."""
    CATEGORY_CHOICES = [
        ('shampoo', 'Shampoo'),
        ('cleanser', 'Cleanser'),
        ('moisturizer', 'Moisturizer'),
        ('sunscreen', 'Sunscreen'),
        ('serum', 'Serum'),
        ('conditioner', 'Conditioner'),
        ('body_wash', 'Body Wash'),
        ('toner', 'Toner'),
    ]
    name         = models.CharField(max_length=300)
    brand        = models.CharField(max_length=200)
    category     = models.CharField(max_length=50, choices=CATEGORY_CHOICES)
    safety_score = models.IntegerField(default=95)
    image_url    = models.URLField(blank=True, default='')
    buy_url      = models.URLField(blank=True, default='') # For future monetization
    description  = models.TextField(blank=True, default='')

    def __str__(self): return f'{self.brand} - {self.name}'

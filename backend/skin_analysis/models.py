from django.db import models
from purepick_core.models import User


class SkinAnalysisRecord(models.Model):
    """Stores each skin analysis result for a user."""
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='skin_analyses',
        null=True,
        blank=True,
    )
    skin_type = models.CharField(max_length=100, blank=True, default='')
    skin_disorder = models.CharField(max_length=200, blank=True, default='')
    skin_type_confidence = models.FloatField(default=0.0)
    skin_disorder_confidence = models.FloatField(default=0.0)
    skin_conditions = models.TextField(blank=True, default='[]')    # JSON list of all conditions
    ai_notes = models.TextField(blank=True, default='')             # Gemini AI observation
    recommendations = models.TextField(blank=True, default='{}')    # JSON dict
    analysis_source = models.CharField(max_length=50, blank=True, default='unknown')
    analysed_at = models.DateTimeField(auto_now_add=True)

    @property
    def created_at(self):
        """Alias for Flutter API compatibility."""
        return self.analysed_at

    def __str__(self):
        user_str = self.user.username if self.user else 'Guest'
        return f"{user_str} | {self.skin_type} | {self.analysed_at.date()}"

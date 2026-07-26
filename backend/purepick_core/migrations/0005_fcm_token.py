"""Migration 0005 — Add FCM token to HealthProfile"""
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('purepick_core', '0004_batch4_schema'),
    ]

    operations = [
        migrations.AddField(
            model_name='healthprofile',
            name='fcm_token',
            field=models.CharField(
                max_length=255,
                blank=True,
                default='',
                help_text='Firebase Cloud Messaging device token',
            ),
        ),
    ]

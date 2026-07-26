from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('skin_analysis', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='skinanalysisrecord',
            name='skin_conditions',
            field=models.TextField(blank=True, default='[]'),
        ),
        migrations.AddField(
            model_name='skinanalysisrecord',
            name='ai_notes',
            field=models.TextField(blank=True, default=''),
        ),
        migrations.AddField(
            model_name='skinanalysisrecord',
            name='analysis_source',
            field=models.CharField(blank=True, default='unknown', max_length=50),
        ),
    ]

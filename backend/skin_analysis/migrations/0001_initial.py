# pyrefly: ignore [missing-import]
from django.db import migrations, models
# pyrefly: ignore [missing-import]
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        # Depends on purepick_core User model being migrated first
        ('purepick_core', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='SkinAnalysisRecord',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('skin_type', models.CharField(blank=True, default='', max_length=100)),
                ('skin_disorder', models.CharField(blank=True, default='', max_length=200)),
                ('skin_type_confidence', models.FloatField(default=0.0)),
                ('skin_disorder_confidence', models.FloatField(default=0.0)),
                ('recommendations', models.TextField(blank=True, default='{}')),
                ('analysed_at', models.DateTimeField(auto_now_add=True)),
                ('user', models.ForeignKey(
                    blank=True,
                    null=True,
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='skin_analyses',
                    to='purepick_core.user',
                )),
            ],
        ),
    ]

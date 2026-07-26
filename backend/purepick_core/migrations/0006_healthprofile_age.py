from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('purepick_core', '0005_fcm_token'),
    ]

    operations = [
        migrations.AddField(
            model_name='healthprofile',
            name='age',
            field=models.PositiveSmallIntegerField(blank=True, help_text='User age in years', null=True),
        ),
    ]

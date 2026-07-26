"""
scanner/management/commands/train_rf_model.py
=============================================
Django management command to (re)train the Random Forest ingredient classifier.

Usage:
    python manage.py train_rf_model
    python manage.py train_rf_model --force   # retrain even if model is current

WHY this exists as a management command:
  - train_model.py was a standalone script with no Django context
  - This integrates properly with Django settings (DB path, model path)
  - Should be run after deployment or when the ingredient database is updated
  - Also fixes sklearn version mismatch warnings (re-saves with current version)
"""
from django.core.management.base import BaseCommand
from django.conf import settings
from pathlib import Path
import logging

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = 'Train or retrain the Random Forest ingredient safety classifier'

    def add_arguments(self, parser):
        parser.add_argument(
            '--force',
            action='store_true',
            help='Retrain even if model files already exist',
        )

    def handle(self, *args, **options):
        import sqlite3
        import pandas as pd
        import joblib
        from sklearn.feature_extraction.text import TfidfVectorizer
        from sklearn.ensemble import RandomForestClassifier
        from sklearn.model_selection import cross_val_score
        import numpy as np

        db_path    = Path(settings.PUREPICK_DB_PATH)
        model_path = Path(settings.MODEL_PATH)
        vec_path   = Path(settings.VECTORIZER_PATH)

        # Check if retraining is needed
        if not options['force'] and model_path.exists() and vec_path.exists():
            self.stdout.write(
                self.style.WARNING(
                    'Model files already exist. Use --force to retrain.\n'
                    f'  Model:      {model_path}\n'
                    f'  Vectorizer: {vec_path}'
                )
            )
            return

        if not db_path.exists():
            self.stderr.write(
                self.style.ERROR(
                    f'Database not found at {db_path}. '
                    'Run: python datasets/build_purepick_db_local.py'
                )
            )
            return

        self.stdout.write('Connecting to PurePick ingredient database...')
        conn = sqlite3.connect(str(db_path))
        df   = pd.read_sql_query(
            'SELECT normalized_name, safety_score, risk_level FROM ingredients',
            conn,
        )
        conn.close()

        if df.empty:
            self.stderr.write(self.style.ERROR('No ingredients in database.'))
            return

        self.stdout.write(f'Loaded {len(df)} ingredients.')

        # Validate class distribution
        class_counts = df['risk_level'].value_counts()
        self.stdout.write(f'Class distribution:\n{class_counts.to_string()}')

        # TF-IDF on character n-grams (1–3) — works well for ingredient name fragments
        self.stdout.write('Fitting TF-IDF vectorizer (char n-grams 1–3)...')
        vectorizer = TfidfVectorizer(ngram_range=(1, 3), analyzer='char_wb', min_df=1)
        X = vectorizer.fit_transform(df['normalized_name'])
        y = df['risk_level']

        # Cross-validation to estimate real-world accuracy
        self.stdout.write('Running 5-fold cross-validation...')
        clf_cv = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)
        cv_scores = cross_val_score(clf_cv, X, y, cv=5, scoring='accuracy')
        self.stdout.write(
            f'CV Accuracy: {np.mean(cv_scores)*100:.1f}% ± {np.std(cv_scores)*100:.1f}%'
        )

        # Train final model on full dataset
        self.stdout.write('Training final model on full dataset...')
        clf = RandomForestClassifier(
            n_estimators=200,        # more trees than original (100) for better stability
            random_state=42,
            n_jobs=-1,
            class_weight='balanced', # WHY: handles class imbalance in ingredient dataset
        )
        clf.fit(X, y)
        train_acc = clf.score(X, y)
        self.stdout.write(f'Training accuracy: {train_acc*100:.1f}%')

        # Save with current sklearn version (fixes version mismatch warnings)
        model_path.parent.mkdir(parents=True, exist_ok=True)
        joblib.dump(clf, model_path, compress=3)
        joblib.dump(vectorizer, vec_path, compress=3)

        # Reset the singleton so the new model is loaded on next call
        import scanner.ml_model as ml_mod
        ml_mod._clf            = None
        ml_mod._vectorizer     = None
        ml_mod._load_attempted = False

        self.stdout.write(self.style.SUCCESS(
            f'\nModel training complete!\n'
            f'  Model saved:      {model_path} ({model_path.stat().st_size // 1024} KB)\n'
            f'  Vectorizer saved: {vec_path} ({vec_path.stat().st_size // 1024} KB)\n'
            f'  Classes: {clf.classes_.tolist()}\n'
            f'  Run again with --force to retrain.'
        ))

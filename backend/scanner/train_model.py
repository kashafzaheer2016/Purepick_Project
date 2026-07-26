"""
PurePick AI Model Trainer
=========================
Trains a Random Forest Classifier using the purepick_db.sqlite knowledge base.
Exports ingredient_safety_model.pkl and tfidf_vectorizer.pkl
"""
import sqlite3
import pandas as pd
import joblib
import logging
from pathlib import Path
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.ensemble import RandomForestClassifier

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).resolve().parent.parent
DB_PATH = BASE_DIR / 'datasets' / 'purepick_db.sqlite'
MODEL_PATH = BASE_DIR / 'scanner' / 'ingredient_safety_model.pkl'
VECTORIZER_PATH = BASE_DIR / 'scanner' / 'tfidf_vectorizer.pkl'

def train_model():
    logger.info("Connecting to PurePick database...")
    
    if not DB_PATH.exists():
        logger.error(f"Database not found at {DB_PATH}")
        return

    conn = sqlite3.connect(str(DB_PATH))
    query = "SELECT normalized_name, safety_score, risk_level FROM ingredients"
    df = pd.read_sql_query(query, conn)
    conn.close()

    if df.empty:
        logger.error("No ingredients found in the database. Please run datasets/build_purepick_db_local.py first.")
        return
        
    logger.info(f"Loaded {len(df)} ingredients for training.")
    
    logger.info("Vectorizing ingredient names with TF-IDF...")
    vectorizer = TfidfVectorizer(ngram_range=(1, 3), analyzer='char_wb')
    X = vectorizer.fit_transform(df['normalized_name'])
    
    target = df['risk_level']
    
    logger.info("Training Random Forest Classifier (this may take a moment)...")
    clf = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)
    clf.fit(X, target)
    
    accuracy = clf.score(X, target)
    logger.info(f"Training Accuracy: {accuracy * 100:.2f}%")
    
    logger.info("Saving models to disk...")
    joblib.dump(clf, MODEL_PATH)
    joblib.dump(vectorizer, VECTORIZER_PATH)
    
    logger.info("Model training complete! Files saved:")
    logger.info(f"  - {MODEL_PATH.name}")
    logger.info(f"  - {VECTORIZER_PATH.name}")

if __name__ == '__main__':
    train_model()

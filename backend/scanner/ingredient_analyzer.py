"""
scanner/ingredient_analyzer.py
================================
Batch 3 changes:
  ✓ ML-predicted ingredients surfaced in allergy_alerts with 'ML_PREDICTED' badge
  ✓ ml_augmented flag passed through to report for Flutter UI badge display
  ✓ model_available flag in report so Flutter can show "AI-enhanced" indicator
"""
import logging
from .ingredient_intelligence import run_ingredient_intelligence
from .ml_model import is_model_available

logger = logging.getLogger(__name__)


class IngredientAnalyzer:
    _instance = None

    def __init__(self):
        pass

    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def analyze(self, ingredients: list, user_profile: dict) -> dict:
        """
        Full ingredient analysis pipeline.
        Stage 3.5: Rule engine + RF ML augmentation
        Stage 6: Final report generation
        """
        intel_report = run_ingredient_intelligence(ingredients, user_profile)

        allergy_alerts = []
        for item in intel_report['flagged_ingredients']:
            severity = item.get('severity', 'MODERATE')

            # ── ML-predicted ingredients get distinct visual treatment ────────
            if severity == 'ML_PREDICTED':
                confidence = item.get('ml_confidence', 0)
                color      = '#FF9500'   # amber — uncertain, not confirmed
                banner     = 'AI PREDICTED RISK'
                explanation = item.get('explanation', '')
                if confidence:
                    explanation += f' (AI confidence: {confidence*100:.0f}%)'
            else:
                color  = '#FF3B30' if severity == 'CRITICAL' else '#FF9500' if severity == 'MODERATE' else '#FFCC00'
                banner = 'DO NOT USE' if severity == 'CRITICAL' else 'USE WITH CAUTION'
                explanation = item.get('explanation', '')

            allergy_alerts.append({
                'ingredient':       item['raw_ingredient'],
                'common_name':      item['common_name'],
                'matched_concern':  item['matched_concern'],
                'severity':         severity,
                'display_color':    color,
                'banner':           f'{banner} — Contains your concern',
                'plain_explanation': explanation,
                'match_source':     item.get('match_source', 'rule_engine'),
                'ml_confidence':    item.get('ml_confidence'),   # None for rule-based
            })

        risk_band     = intel_report['risk_band']
        verdict_color = '#FF3B30' if risk_band == 'High Risk' else '#FF9500' if risk_band == 'Moderate' else '#34C759'
        icon          = 'BLOCKED' if risk_band == 'High Risk' else 'WARNING' if risk_band == 'Moderate' else 'SAFE'
        safety_score  = 100 - min(100, intel_report['total_risk_score'])

        if not allergy_alerts and safety_score < 50:
            safety_score = 100

        return {
            'overall_score': safety_score,
            'risk': {
                'total_score': intel_report['total_risk_score'],
                'risk_band':   risk_band,
            },
            'allergy_result': {
                'overall_verdict':  risk_band.upper(),
                'verdict_color':    verdict_color,
                'verdict_icon':     icon,
                'allergy_alerts':   allergy_alerts,
                'safe_ingredients': intel_report['safe_ingredients'],
                'total_alerts':     len(allergy_alerts),
                'total_safe':       len(intel_report['safe_ingredients']),
            },
            'ingredient_breakdown': intel_report['all_ingredients'],
            # ── Metadata flags for Flutter UI ─────────────────────────────────
            'ml_augmented':    intel_report.get('ml_augmented', False),
            'model_available': is_model_available(),
        }


_analyzer = None

def get_analyzer():
    global _analyzer
    if _analyzer is None:
        _analyzer = IngredientAnalyzer()
    return _analyzer

"""
skin_engine.py  —  PurePick Advanced Skin Analysis Engine  v2
==============================================================
Analysis pipeline:
  1. Face detection     — OpenCV SSD deep-learning detector (res10 300×300)
                          Falls back to Haar cascade if model not present.
  2. Pre-processing     — CLAHE (Contrast Limited Adaptive Histogram Equalization)
                          dramatically improves visibility of subtle conditions
                          (dark circles, mild pigmentation, early fine lines).
  3. Face zone crop     — Extracts periorbital (eye) region as a separate image
                          for the focused second-pass analysis.
  4. PRIMARY analysis   — Gemini Vision Pass 1: full face, all conditions.
  5. FOCUSED analysis   — Gemini Vision Pass 2: cropped eye region only,
                          for dark circles / puffiness / eye bags / tired eyes.
  6. ResNet-50 augment  — If .pt model present (optional, adds disorder signals).
  7. Merge & deduplicate results from both Gemini passes.
  8. Build routine + per-condition treatment recommendations.
  9. Compute overall skin health score.

Output shape:
  {
    has_face, skin_type, skin_type_confidence,
    skin_disorder, skin_disorder_confidence,
    skin_conditions: [{name, severity, confidence, description, zone}],
    zone_analysis:   {forehead, nose, left_cheek, right_cheek, chin, periorbital},
    condition_scores: {name: 0-100},
    ai_notes, image_quality, recommendations,
    condition_recommendations, overall_skin_health_score, analysis_source
  }
"""
from __future__ import annotations

import json
import logging
import os
import tempfile
from pathlib import Path
from typing import Optional, Tuple

logger = logging.getLogger(__name__)

# ── Model paths ────────────────────────────────────────────────────────────────
_HERE       = Path(__file__).parent
_MODELS_DIR = _HERE / "ml_models"

HAARCASCADE_PATH  = str(_MODELS_DIR / "haarcascade_frontalface_default.xml")
SSD_MODEL_PATH    = str(_MODELS_DIR / "res10_300x300_ssd_iter_140000_fp16.caffemodel")
SSD_PROTO_PATH    = str(_MODELS_DIR / "deploy.prototxt")
RESNET_MODEL_PATH = str(_MODELS_DIR / "resnet50-dataset-test_acc_0.66959_epoch-1.pt")
RESNET_JSON_PATH  = str(_MODELS_DIR / "dataset_model_classes.json")

NUM_CLASSES           = 8
PROBABILITY_THRESHOLD = 2.0


# ═══════════════════════════════════════════════════════════════════════════════
# SKIN TYPE TAXONOMY
# ═══════════════════════════════════════════════════════════════════════════════

SKIN_TYPES = {
    'Oily skin', 'Oily', 'Dry skin', 'Dry',
    'Sensitive skin', 'Sensitive', 'Combination skin',
    'Combination', 'Normal skin', 'Normal',
}

_TYPE_NORMALIZER: dict[str, str] = {
    "Oily skin":        "Oily",        "Oily":        "Oily",
    "Dry skin":         "Dry",         "Dry":         "Dry",
    "Sensitive skin":   "Sensitive",   "Sensitive":   "Sensitive",
    "Combination skin": "Combination", "Combination": "Combination",
    "Normal skin":      "Normal",      "Normal":      "Normal",
}


# ═══════════════════════════════════════════════════════════════════════════════
# COMPREHENSIVE CONDITION LIBRARY  (60+ conditions)
# ═══════════════════════════════════════════════════════════════════════════════

ALL_CONDITIONS: dict[str, dict] = {

    # ── ACNE & BREAKOUTS ───────────────────────────────────────────────────────
    "Acne": {
        "category": "Acne & Breakouts",
        "description": "Inflammatory breakouts from clogged pores and bacteria.",
        "severity_guide": {"mild": "few whiteheads/blackheads", "moderate": "papules/pustules", "severe": "cysts/nodules"},
    },
    "Cystic Acne": {
        "category": "Acne & Breakouts",
        "description": "Deep, painful, pus-filled cysts under the skin surface.",
        "severity_guide": {"mild": "1-2 cysts", "moderate": "3-5 cysts", "severe": "widespread cysts"},
    },
    "Hormonal Acne": {
        "category": "Acne & Breakouts",
        "description": "Breakouts concentrated on chin, jawline, and neck from hormonal changes.",
        "severity_guide": {"mild": "occasional", "moderate": "monthly flares", "severe": "persistent"},
    },
    "Blackheads": {
        "category": "Acne & Breakouts",
        "description": "Open comedones — oxidised oil plugs in pores appearing dark.",
        "severity_guide": {"mild": "few on nose", "moderate": "T-zone coverage", "severe": "widespread"},
    },
    "Whiteheads": {
        "category": "Acne & Breakouts",
        "description": "Closed comedones — trapped oil and dead skin under a thin layer.",
        "severity_guide": {"mild": "scattered", "moderate": "clusters", "severe": "widespread clusters"},
    },
    "Fungal Acne": {
        "category": "Acne & Breakouts",
        "description": "Folliculitis caused by Malassezia yeast — uniform small bumps.",
        "severity_guide": {"mild": "few bumps", "moderate": "clusters on forehead", "severe": "widespread"},
    },
    "Steroid Acne": {
        "category": "Acne & Breakouts",
        "description": "Uniform, monomorphic papules/pustules from steroid use.",
        "severity_guide": {"mild": "few lesions", "moderate": "trunk/face", "severe": "widespread"},
    },

    # ── PIGMENTATION ──────────────────────────────────────────────────────────
    "Hyperpigmentation": {
        "category": "Pigmentation",
        "description": "Darkened patches from excess melanin production.",
        "severity_guide": {"mild": "faint patches", "moderate": "noticeable patches", "severe": "widespread/deep"},
    },
    "Dark Spots": {
        "category": "Pigmentation",
        "description": "Localised areas of darker pigmentation (sun spots, age spots).",
        "severity_guide": {"mild": "1-3 spots", "moderate": "4-10 spots", "severe": "10+ spots"},
    },
    "Melasma": {
        "category": "Pigmentation",
        "description": "Symmetrical brown/grey patches on cheeks, forehead, upper lip.",
        "severity_guide": {"mild": "faint", "moderate": "noticeable", "severe": "deep/widespread"},
    },
    "Post-Inflammatory Hyperpigmentation": {
        "category": "Pigmentation",
        "description": "Dark marks left after acne or injury has healed.",
        "severity_guide": {"mild": "few marks", "moderate": "several marks", "severe": "widespread/dark"},
    },
    "Uneven Skin Tone": {
        "category": "Pigmentation",
        "description": "Patchy or inconsistent skin colour without defined borders.",
        "severity_guide": {"mild": "slight variation", "moderate": "visible patchiness", "severe": "significant discolouration"},
    },
    "Vitiligo": {
        "category": "Pigmentation",
        "description": "Loss of pigment causing white patches on skin.",
        "severity_guide": {"mild": "small patch", "moderate": "few patches", "severe": "extensive patches"},
    },
    "Sunspots": {
        "category": "Pigmentation",
        "description": "Solar lentigines — flat brown spots from UV damage.",
        "severity_guide": {"mild": "1-3", "moderate": "4-10", "severe": "10+"},
    },

    # ── AGING & LINES ─────────────────────────────────────────────────────────
    "Fine Lines": {
        "category": "Aging & Lines",
        "description": "Shallow surface lines from repeated facial expressions and dehydration.",
        "severity_guide": {"mild": "visible only on expression", "moderate": "visible at rest", "severe": "deep at rest"},
    },
    "Wrinkles": {
        "category": "Aging & Lines",
        "description": "Deeper creases from collagen loss and repeated muscle movement.",
        "severity_guide": {"mild": "forehead lines", "moderate": "crow's feet/folds", "severe": "deep/widespread"},
    },
    "Crow's Feet": {
        "category": "Aging & Lines",
        "description": "Fan-shaped lines at the outer corners of the eyes.",
        "severity_guide": {"mild": "visible on smiling", "moderate": "visible at rest", "severe": "deep at rest"},
    },
    "Nasolabial Folds": {
        "category": "Aging & Lines",
        "description": "Deep lines running from nose to mouth corners (smile lines).",
        "severity_guide": {"mild": "faint", "moderate": "visible at rest", "severe": "deep grooves"},
    },
    "Forehead Lines": {
        "category": "Aging & Lines",
        "description": "Horizontal lines across the forehead from repeated expression.",
        "severity_guide": {"mild": "faint", "moderate": "visible", "severe": "deep furrows"},
    },
    "Sagging Skin": {
        "category": "Aging & Lines",
        "description": "Loss of skin firmness and elasticity causing drooping.",
        "severity_guide": {"mild": "slight laxity", "moderate": "noticeable sagging", "severe": "significant drooping"},
    },
    "Loss of Elasticity": {
        "category": "Aging & Lines",
        "description": "Reduced skin bounce-back from elastin degradation.",
        "severity_guide": {"mild": "slight", "moderate": "noticeable", "severe": "significant"},
    },

    # ── TEXTURE ISSUES ────────────────────────────────────────────────────────
    "Enlarged Pores": {
        "category": "Texture",
        "description": "Visibly large pore openings, usually on nose and cheeks.",
        "severity_guide": {"mild": "slightly visible", "moderate": "clearly visible", "severe": "very large/clogged"},
    },
    "Uneven Texture": {
        "category": "Texture",
        "description": "Bumpy or rough skin surface from dead skin buildup or scarring.",
        "severity_guide": {"mild": "slightly rough", "moderate": "bumpy patches", "severe": "widespread roughness"},
    },
    "Rough Patches": {
        "category": "Texture",
        "description": "Localised areas of dry, flaky, or hardened skin.",
        "severity_guide": {"mild": "small area", "moderate": "several patches", "severe": "widespread"},
    },
    "Flakiness": {
        "category": "Texture",
        "description": "Visible shedding of dry skin cells.",
        "severity_guide": {"mild": "slight", "moderate": "noticeable flakes", "severe": "heavy peeling"},
    },
    "Acne Scars": {
        "category": "Texture",
        "description": "Permanent indentations or raised scars from healed acne.",
        "severity_guide": {"mild": "1-3 small", "moderate": "several/visible", "severe": "pitted/widespread"},
    },
    "Textural Irregularities": {
        "category": "Texture",
        "description": "General inconsistency in skin surface smoothness.",
        "severity_guide": {"mild": "slight", "moderate": "noticeable", "severe": "significant"},
    },
    "Keratosis Pilaris": {
        "category": "Texture",
        "description": "Tiny rough bumps from keratin build-up in hair follicles.",
        "severity_guide": {"mild": "few bumps", "moderate": "patches", "severe": "widespread"},
    },

    # ── EYE AREA ──────────────────────────────────────────────────────────────
    "Dark Circles": {
        "category": "Eye Area",
        "description": "Discolouration under the eyes — vascular (blue-purple), pigmentation (brown), or structural (hollow shadows).",
        "severity_guide": {"mild": "faint tint, only noticeable in certain lighting", "moderate": "clearly visible discolouration at rest", "severe": "dark, sunken, prominent under both eyes"},
    },
    "Puffiness": {
        "category": "Eye Area",
        "description": "Swelling under or around the eyes from fluid retention.",
        "severity_guide": {"mild": "slight", "moderate": "noticeable bags", "severe": "pronounced swelling"},
    },
    "Under-Eye Wrinkles": {
        "category": "Eye Area",
        "description": "Fine lines on the delicate under-eye skin.",
        "severity_guide": {"mild": "faint lines", "moderate": "visible", "severe": "deep creases"},
    },
    "Eye Bags": {
        "category": "Eye Area",
        "description": "Permanent fat pockets causing a baggy appearance under eyes.",
        "severity_guide": {"mild": "slight", "moderate": "noticeable", "severe": "prominent"},
    },
    "Tired Eyes": {
        "category": "Eye Area",
        "description": "Dull, sunken, or shadowed eye area from fatigue or dehydration.",
        "severity_guide": {"mild": "slightly dull", "moderate": "sunken/shadowed", "severe": "very hollow/dark"},
    },
    "Periorbital Hyperpigmentation": {
        "category": "Eye Area",
        "description": "Brown pigmentation specifically around the orbital rim — constitutional or post-inflammatory.",
        "severity_guide": {"mild": "faint brown tint", "moderate": "visible brown ring", "severe": "deep brown/extensive"},
    },
    "Tear Trough": {
        "category": "Eye Area",
        "description": "Hollow groove between the lower eyelid and cheek creating a shadow.",
        "severity_guide": {"mild": "slight groove", "moderate": "visible hollow", "severe": "deep pronounced trough"},
    },

    # ── SENSITIVITY & REDNESS ─────────────────────────────────────────────────
    "Redness": {
        "category": "Sensitivity",
        "description": "General facial flushing or persistent redness.",
        "severity_guide": {"mild": "slight flush", "moderate": "consistent redness", "severe": "intense/widespread"},
    },
    "Rosacea": {
        "category": "Sensitivity",
        "description": "Chronic redness with visible blood vessels and possible bumps.",
        "severity_guide": {"mild": "flushing only", "moderate": "persistent redness+vessels", "severe": "papules+thickening"},
    },
    "Sensitive Skin": {
        "category": "Sensitivity",
        "description": "Easily reactive skin showing redness, stinging, or burning.",
        "severity_guide": {"mild": "occasional", "moderate": "frequent reactions", "severe": "constant discomfort"},
    },
    "Contact Dermatitis": {
        "category": "Sensitivity",
        "description": "Rash or irritation from allergic reaction to a product or substance.",
        "severity_guide": {"mild": "faint rash", "moderate": "red itchy patches", "severe": "blistering/weeping"},
    },
    "Perioral Dermatitis": {
        "category": "Sensitivity",
        "description": "Red bumpy rash around the mouth.",
        "severity_guide": {"mild": "slight redness", "moderate": "clear rash", "severe": "widespread pustules"},
    },
    "Flushing": {
        "category": "Sensitivity",
        "description": "Temporary redness triggered by heat, emotion, or food.",
        "severity_guide": {"mild": "slight", "moderate": "noticeable", "severe": "intense/frequent"},
    },

    # ── HYDRATION & OIL BALANCE ───────────────────────────────────────────────
    "Dehydration": {
        "category": "Hydration",
        "description": "Lack of water content in skin causing tightness and dullness.",
        "severity_guide": {"mild": "slight tightness", "moderate": "dull/tight", "severe": "pronounced lines from dryness"},
    },
    "Dryness": {
        "category": "Hydration",
        "description": "Lack of natural oils causing flakiness and rough texture.",
        "severity_guide": {"mild": "slight dryness", "moderate": "rough/flaky", "severe": "cracking/bleeding"},
    },
    "Oiliness": {
        "category": "Hydration",
        "description": "Excess sebum production causing shine and greasiness.",
        "severity_guide": {"mild": "T-zone shine", "moderate": "full-face shine", "severe": "heavy grease/breakouts"},
    },
    "Combination Skin Issues": {
        "category": "Hydration",
        "description": "Oily T-zone with dry or normal cheeks creating imbalance.",
        "severity_guide": {"mild": "slight imbalance", "moderate": "clear difference", "severe": "extreme contrast"},
    },
    "Dullness": {
        "category": "Hydration",
        "description": "Lack of radiance and luminosity — skin appears flat and grey.",
        "severity_guide": {"mild": "slight", "moderate": "noticeable", "severe": "very dull/ashy"},
    },
    "Tired Skin": {
        "category": "Hydration",
        "description": "Skin appears fatigued, sallow, and lacking vitality.",
        "severity_guide": {"mild": "slightly dull", "moderate": "visibly fatigued", "severe": "very dull/sallow"},
    },

    # ── SKIN DISORDERS ────────────────────────────────────────────────────────
    "Eczema": {
        "category": "Skin Disorders",
        "description": "Inflamed, itchy, cracked skin — often appears on cheeks.",
        "severity_guide": {"mild": "faint dry patches", "moderate": "red itchy patches", "severe": "weeping/crusting"},
    },
    "Psoriasis": {
        "category": "Skin Disorders",
        "description": "Thick, silvery-scaled red plaques on skin.",
        "severity_guide": {"mild": "small plaque", "moderate": "several plaques", "severe": "widespread/thick"},
    },
    "Seborrhoeic Dermatitis": {
        "category": "Skin Disorders",
        "description": "Flaky, oily patches on scalp, nose, eyebrows.",
        "severity_guide": {"mild": "slight flaking", "moderate": "scaly patches", "severe": "thick crusts"},
    },
    "Milia": {
        "category": "Skin Disorders",
        "description": "Small white cysts under skin from trapped keratin.",
        "severity_guide": {"mild": "1-3 cysts", "moderate": "clusters", "severe": "widespread"},
    },
    "Actinic Keratosis": {
        "category": "Skin Disorders",
        "description": "Rough, scaly pre-cancerous patches from UV damage.",
        "severity_guide": {"mild": "1 patch", "moderate": "2-5 patches", "severe": "multiple/thick"},
    },
    "Photodamage": {
        "category": "Skin Disorders",
        "description": "Visible UV damage — freckles, uneven tone, premature aging.",
        "severity_guide": {"mild": "slight freckling", "moderate": "uneven tone/spots", "severe": "extensive damage"},
    },
    "Broken Capillaries": {
        "category": "Vascular",
        "description": "Visible small red/purple blood vessels near skin surface.",
        "severity_guide": {"mild": "few threads", "moderate": "visible network", "severe": "widespread"},
    },
    "Spider Veins": {
        "category": "Vascular",
        "description": "Thread veins visible through skin, usually on cheeks/nose.",
        "severity_guide": {"mild": "faint", "moderate": "visible", "severe": "prominent network"},
    },
    "Sallowness": {
        "category": "Vascular",
        "description": "Yellowish or greyish skin tone from poor circulation.",
        "severity_guide": {"mild": "slight", "moderate": "noticeable", "severe": "pronounced"},
    },
}

ALL_CONDITION_NAMES = set(ALL_CONDITIONS.keys())

SKIN_DISORDERS = set(ALL_CONDITIONS.keys()) | {
    'Actinic keratoses', 'Adult-onset dermatomyositis', 'Ageing skin',
    'Allergic contact dermatitis', 'Angioedema', 'Angiofibroma',
    'Atopic dermatitis', 'Basal Cell Carcinoma', 'Blepharitis',
    'Cutaneous lupus erythematosus', 'Demodicosis', 'Discoid lupus erythematosus',
    'Eczemaa', 'Erythema dyschromicum perstans', 'Granuloma faciale',
    'Hair follicle tumours', 'Jessner lymphocytic infiltrate',
    'Keratosis pilaris atrophicans faciei', 'Lichen planus pigmentosus',
    'Neonatal lupus erythematosus', 'Pityriasis alba',
    'Poikiloderma of Civatte', 'Pseudofolliculitis barbae',
    'Pyoderma faciale', 'Sarcoidosis', 'Seborrhoea', 'Shaving rash',
    'Solar keratoses', 'Solar/senile comedones',
    'Systemic lupus erythematosus', 'Trigeminal trophic syndrome',
}


# ═══════════════════════════════════════════════════════════════════════════════
# SKINCARE ROUTINES
# ═══════════════════════════════════════════════════════════════════════════════

ROUTINES: dict[str, dict[str, str]] = {
    "Oily": {
        "Cleansing":      "Gentle foaming or gel cleanser twice daily. Look for 'non-comedogenic' and 'oil-free'. Avoid over-washing — strips barrier and triggers more oil.",
        "Exfoliation":    "2-3×/week with BHA (salicylic acid 1-2%) to unclog pores and control shine. Avoid harsh physical scrubs.",
        "Moisturizing":   "Lightweight, water-based or gel moisturiser. Look for hyaluronic acid, niacinamide (controls sebum), glycerin.",
        "Sun Protection": "Oil-free mattifying SPF 30-50 daily. Mineral (zinc/titanium) or hybrid formulas work best.",
        "Lifestyle":      "Blotting papers for midday shine. Clean pillowcases weekly. Avoid touching face. Diet low in high-GI foods (sugar/white bread).",
    },
    "Dry": {
        "Cleansing":      "Creamy, hydrating cleanser once daily (AM: water rinse only). Avoid anything with alcohol, sulphates, or fragrance.",
        "Exfoliation":    "1×/week max. Gentle AHA (lactic acid 5-10%) to remove flakes without stripping. Never physical scrubs on dry skin.",
        "Moisturizing":   "Rich cream with ceramides, shea butter, hyaluronic acid. Apply within 60s of washing (locks moisture in).",
        "Sun Protection": "Moisturising SPF 30-50 with hydrating ingredients. Tinted formulas provide extra glow.",
        "Lifestyle":      "Lukewarm (not hot) showers. Humidifier in bedroom. Drink 2L water daily. Avoid alcohol and caffeine in excess.",
    },
    "Sensitive": {
        "Cleansing":      "Fragrance-free, soap-free gel or micellar water cleanser. Max twice daily. Patch test all new products first.",
        "Exfoliation":    "1×/week maximum. PHA (polyhydroxy acid) is gentler than AHA/BHA. Or skip entirely during flare-ups.",
        "Moisturizing":   "Fragrance-free, hypoallergenic with colloidal oatmeal, ceramides, centella asiatica, aloe vera. Avoid 20+ ingredient products.",
        "Sun Protection": "Mineral-only SPF 30+ (zinc oxide / titanium dioxide). Chemical filters can irritate sensitive skin.",
        "Lifestyle":      "Track triggers (food, stress, products). Avoid extreme temps. Keep routine minimal — fewer products = fewer reactions.",
    },
    "Combination": {
        "Cleansing":      "Gentle balanced cleanser (gel or micellar) twice daily. Avoid anything too stripping or too rich.",
        "Exfoliation":    "2×/week. Use BHA on T-zone (oily areas) and AHA on drier cheeks.",
        "Moisturizing":   "Multi-mask or zone approach: lighter gel on T-zone, richer cream on cheeks. Or use a balanced moisturiser throughout.",
        "Sun Protection": "Balanced SPF 30-50. Gel or emulsion texture works for both zones.",
        "Lifestyle":      "Avoid harsh one-size-fits-all products. Use a toner with niacinamide to balance both zones.",
    },
    "Normal": {
        "Cleansing":      "Gentle cream or gel cleanser twice daily. Your skin is balanced — don't over-complicate it.",
        "Exfoliation":    "1-2×/week with a gentle AHA or enzyme exfoliant to maintain radiance.",
        "Moisturizing":   "Lightweight daily moisturiser with hyaluronic acid or glycerin to maintain hydration.",
        "Sun Protection": "Broad-spectrum SPF 30-50 every morning. The single most important anti-aging step.",
        "Lifestyle":      "Maintain a consistent routine. Diet rich in antioxidants (berries, leafy greens). Adequate sleep (7-9h).",
    },
}


# ═══════════════════════════════════════════════════════════════════════════════
# CONDITION RECOMMENDATIONS
# ═══════════════════════════════════════════════════════════════════════════════

CONDITION_RECOMMENDATIONS: dict[str, dict[str, str]] = {

    "Acne": {
        "Treatment":       "Start with salicylic acid 0.5-2% (BHA) or benzoyl peroxide 2.5-5%. Niacinamide 5-10% reduces redness and oil. Azelaic acid 10% targets bacteria without irritation.",
        "Key Ingredients": "Salicylic acid, Niacinamide, Benzoyl peroxide, Azelaic acid, Tea tree oil (max 5%), Zinc.",
        "Avoid":           "Heavy occlusive oils, synthetic fragrance, physical scrubs, touching/picking.",
        "Product Order":   "Cleanser → Toner (BHA) → Niacinamide serum → Light moisturiser → SPF (AM) | Cleanser → BHA → Spot treatment → Moisturiser (PM).",
        "Lifestyle":       "Change pillowcase every 2-3 days. Clean phone screen. Avoid dairy and high-GI foods if acne is hormonal.",
    },
    "Cystic Acne": {
        "Treatment":       "See a dermatologist — prescription retinoids or antibiotics often needed. OTC: benzoyl peroxide 5-10%, ice to reduce swelling. NEVER squeeze.",
        "Key Ingredients": "Benzoyl peroxide 5-10%, Sulfur, Prescription retinoids (tretinoin), Clindamycin (prescription).",
        "Avoid":           "Picking/squeezing (causes scarring), comedogenic products, hormonal triggers (dairy, stress).",
        "Product Order":   "Gentle cleanser → Prescribed treatment → Non-comedogenic moisturiser → SPF.",
        "Lifestyle":       "Track hormonal cycles. Reduce stress. Consult a dermatologist — OTC is rarely enough.",
    },
    "Hormonal Acne": {
        "Treatment":       "Chin/jaw focus: niacinamide + salicylic acid. Spearmint tea internally (2 cups/day). DIM supplement may help.",
        "Key Ingredients": "Niacinamide 10%, Salicylic acid 2%, Zinc, Azelaic acid 10%, Retinol (0.025% to start).",
        "Avoid":           "High dairy, sugar, processed foods. Testosterone-boosting supplements.",
        "Product Order":   "BHA cleanser → Niacinamide → SPF (AM) | BHA toner → Retinol → Moisturiser (PM).",
        "Lifestyle":       "Track cycle and breakout patterns. Manage stress. Consult GP if severe.",
    },
    "Blackheads": {
        "Treatment":       "BHA (salicylic acid 2%) is the gold standard — dissolves inside the pore. Weekly clay masks draw out impurities. Retinol prevents formation.",
        "Key Ingredients": "Salicylic acid 2%, Retinol, Kaolin/bentonite clay, Niacinamide, AHAs.",
        "Avoid":           "Pore strips (cause capillary damage), manual extraction without steam prep, thick occlusive products.",
        "Product Order":   "BHA cleanser → BHA toner → Clay mask (2×/week) → Moisturiser.",
        "Lifestyle":       "Weekly steam + gentle extraction (or professional facial). Keep skin clean and makeup-free at night.",
    },
    "Dark Circles": {
        "Treatment":       "Identify the type first — vascular (blue-purple: use caffeine + Vitamin K), pigmentation (brown: use niacinamide + kojic acid), structural (hollow: hyaluronic acid filler is most effective). Retinol thickens thin under-eye skin over time.",
        "Key Ingredients": "Caffeine (vasoconstriction), Vitamin K (vascular), Niacinamide 5% (pigmentation), Kojic acid (pigmentation), Peptides (Matrixyl/Argireline), Retinol 0.025%, Hyaluronic acid.",
        "Avoid":           "Rubbing eyes, sleeping with makeup, salty diet (causes puffiness), rubbing harsh products near eyes.",
        "Product Order":   "Eye cream AM (caffeine + Vitamin C) → SPF around eye area. PM: eye cream (retinol or peptides).",
        "Lifestyle":       "Elevate head 15° while sleeping. Cold spoon or chilled eye mask in the morning. Reduce screen time. Sleep 7-9h consistently.",
    },
    "Periorbital Hyperpigmentation": {
        "Treatment":       "Brown pigmentation around the orbital bone. Kojic acid 1%, Alpha-arbutin 1%, Niacinamide 5%, Vitamin C 10-15% — applied consistently 6-8 weeks before seeing improvement.",
        "Key Ingredients": "Kojic acid, Alpha-arbutin, Niacinamide, Vitamin C, Tranexamic acid.",
        "Avoid":           "Sun exposure without SPF (darkens pigmentation), rubbing, fragrance near eyes.",
        "Product Order":   "AM: Niacinamide/arbutin eye serum → SPF. PM: Kojic or tranexamic eye cream.",
        "Lifestyle":       "SPF under eyes daily. Treat any iron deficiency (can cause periorbital pigmentation). See dermatologist for chemical peels.",
    },
    "Tear Trough": {
        "Treatment":       "Structural hollow best treated with hyaluronic acid filler (professional). Topically: peptide eye cream + HA serum plump the area. Lifestyle sleep + hydration helps mild cases.",
        "Key Ingredients": "Hyaluronic acid, Peptides (Argireline, Leuphasyl), Retinol 0.025%, Collagen-support ingredients.",
        "Avoid":           "Heavy products that migrate into eyes. Salt/alcohol that dehydrate the area.",
        "Product Order":   "HA serum → Peptide eye cream → SPF (AM). PM: retinol eye cream (every other night).",
        "Lifestyle":       "Sleep on back with head slightly elevated. Reduce salt. See an aesthetic practitioner for filler if moderate-severe.",
    },
    "Puffiness": {
        "Treatment":       "Cold compress or frozen spoon on eyes for 5 min AM. Caffeine eye cream. Gua sha facial massage drains lymph. Reduce salt intake.",
        "Key Ingredients": "Caffeine, Green tea extract, Peptides, Arnica extract, Aloe vera (chilled).",
        "Avoid":           "Salty foods, alcohol before bed, lying flat on face, hot showers in AM.",
        "Product Order":   "Cold water rinse → Caffeine eye cream → SPF.",
        "Lifestyle":       "Elevate head while sleeping. Limit alcohol and sodium. 8 glasses of water daily.",
    },
    "Tired Eyes": {
        "Treatment":       "Vitamin C eye cream for instant radiance. Caffeine reduces under-eye shadows. Peptides improve firmness. Chilled eye masks work immediately.",
        "Key Ingredients": "Caffeine, Vitamin C, Peptides, Niacinamide, Hyaluronic acid.",
        "Avoid":           "Alcohol-based products, skipping moisturiser, excess caffeine beverages (dehydrates).",
        "Product Order":   "Caffeine eye cream → Vitamin C serum → SPF.",
        "Lifestyle":       "7-9h sleep. Reduce screen exposure before bed. Exercise boosts circulation naturally.",
    },
    "Hyperpigmentation": {
        "Treatment":       "AM: Vitamin C 15-20% + SPF 50. PM: Retinol + AHA alternate nights. Alpha-arbutin and tranexamic acid fade melanin. Patience required — 3-6 months.",
        "Key Ingredients": "Vitamin C, Alpha-arbutin 1-2%, Kojic acid, Tranexamic acid, Niacinamide, Azelaic acid, Retinol, Glycolic/lactic acid.",
        "Avoid":           "Sun without SPF 50, picking, harsh scrubbing of affected areas.",
        "Product Order":   "Cleanser → Vitamin C → SPF 50 (AM). Cleanser → Retinol OR AHA → Moisturiser (PM — alternate nights).",
        "Lifestyle":       "SPF 50 every day, reapply every 2h outdoor. Hat + shade. Consistency is key.",
    },
    "Dark Spots": {
        "Treatment":       "Spot-treat with alpha-arbutin or tranexamic acid. Full-face Vitamin C AM. AHA 2-3×/week for overall brightening.",
        "Key Ingredients": "Tranexamic acid, Alpha-arbutin, Vitamin C, Kojic acid, Niacinamide, Glycolic acid.",
        "Avoid":           "UV without protection (darkens spots), aggressive picking.",
        "Product Order":   "Cleanser → Spot serum (arbutin/tranexamic) → Vitamin C → SPF (AM). AHA 2-3×/week at night.",
        "Lifestyle":       "SPF every day. Eat foods rich in Vitamin C. Antioxidant-rich diet fights pigmentation from inside.",
    },
    "Melasma": {
        "Treatment":       "Hardest pigmentation to treat. Triple combination (hydroquinone 4% + tretinoin + steroid) is gold standard. OTC: tranexamic acid + SPF 50.",
        "Key Ingredients": "Tranexamic acid 5%, Alpha-arbutin 2%, Kojic acid + Vitamin C, Niacinamide, Azelaic acid 20%.",
        "Avoid":           "Any UV exposure (primary trigger), hormonal contraceptives (worsen melasma), heat.",
        "Product Order":   "Gentle cleanser → Brightening serum → SPF 50+ (reapply every 2h).",
        "Lifestyle":       "Wide-brim hat + shade mandatory. Dermatologist for prescription treatment.",
    },
    "Post-Inflammatory Hyperpigmentation": {
        "Treatment":       "Fade marks with niacinamide + Vitamin C. Retinol speeds cell turnover. Takes 3-12 months.",
        "Key Ingredients": "Niacinamide 10%, Vitamin C 15%, Alpha-arbutin, Retinol 0.05%, Azelaic acid.",
        "Avoid":           "Sun (darkens PIH), picking/squeezing spots, harsh actives on active breakouts.",
        "Product Order":   "Cleanser → Niacinamide → SPF (AM). PM: Retinol → Moisturiser.",
        "Lifestyle":       "Treat acne ASAP to prevent new PIH. SPF daily without fail.",
    },
    "Fine Lines": {
        "Treatment":       "Prevention > correction. Retinol is the most evidence-backed anti-aging ingredient. HA plumps. Peptides stimulate collagen.",
        "Key Ingredients": "Retinol 0.025% (start low, go slow), Peptides (Matrixyl 3000), Hyaluronic acid, Vitamin C, Niacinamide.",
        "Avoid":           "Sun without SPF (causes 80% of aging), smoking, dehydration.",
        "Product Order":   "Cleanser → Vitamin C → HA → Moisturiser → SPF 50 (AM). PM: Retinol (every other night) → HA → Rich cream.",
        "Lifestyle":       "SPF every day. Sleep on silk/satin. Stay hydrated. No smoking.",
    },
    "Wrinkles": {
        "Treatment":       "Prescription tretinoin is stronger than OTC retinol. Peptides + HA for plumping. Professional: laser, microneedling, Botox.",
        "Key Ingredients": "Retinol (0.1-0.5%), Tretinoin (prescription), Peptides, Vitamin C, HA.",
        "Avoid":           "Sun, smoking, alcohol excess, dehydration, harsh physical scrubs.",
        "Product Order":   "AM: Vitamin C + SPF 50. PM: Retinoid → Peptide serum → Rich moisturiser.",
        "Lifestyle":       "Sleep quality matters. Antioxidant-rich diet. Facial yoga/massage helps.",
    },
    "Enlarged Pores": {
        "Treatment":       "BHA shrinks pores by removing debris inside. Retinol tightens pore walls over time. Niacinamide reduces appearance. Clay masks draw out oil.",
        "Key Ingredients": "Salicylic acid 2%, Retinol, Niacinamide 10%, Glycolic acid, Kaolin clay.",
        "Avoid":           "Heavy pore-clogging products, over-cleansing, steaming without follow-up BHA.",
        "Product Order":   "BHA cleanser → BHA toner → Niacinamide → Light moisturiser → SPF.",
        "Lifestyle":       "Consistent BHA + retinol makes pores much less visible over time. Be patient.",
    },
    "Uneven Texture": {
        "Treatment":       "AHAs chemically dissolve dead skin for instant smoothness. Retinol normalises cell turnover. BHA for congestion-related bumps.",
        "Key Ingredients": "Glycolic acid 5-10%, Lactic acid 5-12%, Retinol, Salicylic acid 2%, Niacinamide.",
        "Avoid":           "Physical scrubs (microtears create uneven texture), over-exfoliation.",
        "Product Order":   "Cleanser → AHA toner → Serum → Moisturiser → SPF. AHA 2-3×/week only.",
        "Lifestyle":       "Never skip SPF after AHA use (photosensitising). Drink water. Eat collagen-supporting foods.",
    },
    "Acne Scars": {
        "Treatment":       "Atrophic (pitted) scars: microneedling, laser, retinol. Raised scars: silicone sheets, gentle massage. PIH (flat marks): brightening actives.",
        "Key Ingredients": "Retinol 0.05-0.1%, Vitamin C, Niacinamide, AHAs, Rosehip oil.",
        "Avoid":           "Sun (darkens scars), picking existing acne.",
        "Product Order":   "PM: Retinol → Niacinamide → Moisturiser. AM: Vitamin C → SPF.",
        "Lifestyle":       "Microneedling/laser most effective for deep scars. Dermatologist consult recommended.",
    },
    "Redness": {
        "Treatment":       "Centella asiatica and azelaic acid reduce inflammation. Niacinamide calms redness. Green tea extract is anti-inflammatory.",
        "Key Ingredients": "Centella asiatica, Niacinamide 5-10%, Azelaic acid 10%, Green tea extract, Aloe vera, Ceramides.",
        "Avoid":           "Alcohol in products, fragrance, physical exfoliants, very hot water, spicy food.",
        "Product Order":   "Gentle cleanser → Centella/Niacinamide serum → Fragrance-free moisturiser → Mineral SPF.",
        "Lifestyle":       "Track triggers. Use lukewarm water only. Avoid extreme temperature changes.",
    },
    "Rosacea": {
        "Treatment":       "Azelaic acid 15-20% is clinically proven for rosacea. Ivermectin and metronidazole (prescription) for papulopustular. Laser for persistent redness.",
        "Key Ingredients": "Azelaic acid 15-20%, Niacinamide 4%, Centella asiatica, Green tea, Ceramides.",
        "Avoid":           "Alcohol (topical + consumed), fragrance, spicy food, caffeine excess, hot beverages, harsh scrubs, sun.",
        "Product Order":   "Gentle cleanser → Azelaic acid or niacinamide → Minimal moisturiser → Mineral SPF.",
        "Lifestyle":       "Keep a trigger diary. Rosacea is manageable not curable. Dermatologist for prescription treatment.",
    },
    "Eczema": {
        "Treatment":       "Restore barrier FIRST: ceramide-rich moisturiser within 3 minutes of bathing. Colloidal oatmeal soothes. Prescription: mild topical steroids for flares.",
        "Key Ingredients": "Ceramides, Colloidal oatmeal, Glycerin, Shea butter, Panthenol (B5), Allantoin. Fragrance-FREE everything.",
        "Avoid":           "Fragrance (top trigger), soap/SLS, hot water, wool, harsh detergent, stress.",
        "Product Order":   "Soap-free cleanser → Thick ceramide moisturiser immediately after bathing. Repeat as needed.",
        "Lifestyle":       "Wear cotton. Use fragrance-free laundry detergent. Manage stress. Humidifier helps.",
    },
    "Dryness": {
        "Treatment":       "Layer hydration: humectant (HA) → emollient (oils/ceramides) → occlusive (shea/petrolatum) to lock moisture in.",
        "Key Ingredients": "Hyaluronic acid, Ceramides, Shea butter, Glycerin, Squalane, Urea 5-10%, Panthenol.",
        "Avoid":           "Hot showers, sulphate cleansers, alcohol-based toners, harsh actives without moisturiser.",
        "Product Order":   "Creamy cleanser → HA serum (damp skin) → Ceramide moisturiser → Occlusive at night.",
        "Lifestyle":       "Humidifier. Lukewarm showers (max 5 min). Drink 2L water. Omega-3 rich foods improve skin lipids.",
    },
    "Dehydration": {
        "Treatment":       "Dehydration is water loss (not oil). Fix: humectant-rich products. Apply HA on damp skin for maximum absorption.",
        "Key Ingredients": "Hyaluronic acid (all molecular weights), Glycerin, Aloe vera, Beta-glucan, Panthenol.",
        "Avoid":           "Alcohol-based products, over-cleansing, skipping moisturiser, diuretics.",
        "Product Order":   "Apply HA serum on damp skin → seal with moisturiser immediately.",
        "Lifestyle":       "Drink 2L+ water. Eat water-rich foods (cucumber, watermelon). Reduce caffeine/alcohol. Humidifier in dry climates.",
    },
    "Oiliness": {
        "Treatment":       "Oil-stripping products worsen oiliness (skin overcompensates). Use balancing ingredients. Niacinamide regulates sebum at 10%.",
        "Key Ingredients": "Niacinamide 10%, Salicylic acid 0.5-2%, Zinc, Clay (occasional), Hyaluronic acid.",
        "Avoid":           "Over-washing, alcohol astringents, heavy oils, skipping moisturiser.",
        "Product Order":   "Gel cleanser → BHA toner → Niacinamide serum → Gel moisturiser → Mattifying SPF.",
        "Lifestyle":       "Blotting papers. Balanced diet — reduce dairy and high-GI foods. Manage stress.",
    },
    "Dullness": {
        "Treatment":       "Chemical exfoliation weekly reveals fresh radiant skin. Vitamin C brightens instantly. Niacinamide adds glow.",
        "Key Ingredients": "Vitamin C 10-15%, Glycolic acid 5%, Lactic acid 8%, Niacinamide, Rosehip oil, Bakuchiol.",
        "Avoid":           "Skipping exfoliation, heavy occlusive products that dull complexion, dehydration.",
        "Product Order":   "AM: Vitamin C → SPF. PM: AHA 2×/week → Glow-boosting serum → Moisturiser.",
        "Lifestyle":       "Regular exercise (increases circulation = natural glow). Sleep. Antioxidant diet. Hydration.",
    },
    "Sensitive Skin": {
        "Treatment":       "Simplify routine to 5 products max. Patch test everything. Barrier repair is priority.",
        "Key Ingredients": "Ceramides, Colloidal oatmeal, Centella asiatica, Allantoin, Panthenol, Aloe vera. All fragrance-FREE.",
        "Avoid":           "Fragrance, alcohol, essential oils, AHAs initially, multiple actives at once, over-exfoliation.",
        "Product Order":   "Gentle cleanser → Barrier serum → Fragrance-free moisturiser → Mineral SPF.",
        "Lifestyle":       "Keep a reaction diary. Use as few products as possible. Test on inner arm first.",
    },
    "Broken Capillaries": {
        "Treatment":       "Cannot fix topically — need laser (IPL or Nd:YAG). Prevention: avoid extreme temps, harsh scrubbing. Vitamin K and horse chestnut extract may slightly help.",
        "Key Ingredients": "Vitamin K, Horse chestnut extract, Arnica, Centella asiatica (prevention).",
        "Avoid":           "Harsh scrubbing, very hot water/saunas, alcohol, nose-squeezing.",
        "Product Order":   "Gentle cleanser → Calming serum (centella) → Mineral SPF.",
        "Lifestyle":       "Laser treatment from a dermatologist is most effective. Avoid temperature extremes.",
    },
    "Photodamage": {
        "Treatment":       "Vitamin C fades UV damage. Retinol reverses photoaging. AHAs resurface sun-damaged skin. SPF 50 prevents further damage.",
        "Key Ingredients": "Vitamin C 20%, Retinol 0.05-0.1%, Niacinamide, AHAs, Antioxidant blend.",
        "Avoid":           "Any UV without SPF 50 — completely undoes treatment.",
        "Product Order":   "AM: Vitamin C + Antioxidant → SPF 50. PM: Retinol → Rich moisturiser.",
        "Lifestyle":       "SPF 50 every day. Wide-brim hat outdoor. Reapply every 2h.",
    },
}


# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

def get_routine(skin_type: str) -> dict[str, str]:
    normalised = _TYPE_NORMALIZER.get(skin_type, skin_type)
    return ROUTINES.get(normalised, {})


def get_condition_recommendation(condition: str) -> dict:
    if condition in CONDITION_RECOMMENDATIONS:
        return CONDITION_RECOMMENDATIONS[condition]
    condition_lower = condition.lower()
    for key, val in CONDITION_RECOMMENDATIONS.items():
        if key.lower() in condition_lower or condition_lower in key.lower():
            return val
    return {}


def _compute_skin_health_score(skin_type: str, conditions: list) -> int:
    score = 100
    severity_deductions = {'severe': 20, 'moderate': 10, 'mild': 4}
    severe_conditions = {'Cystic Acne', 'Rosacea', 'Eczema', 'Psoriasis', 'Actinic Keratosis', 'Photodamage'}
    for cond in conditions:
        name     = cond.get('name', '')     if isinstance(cond, dict) else str(cond)
        severity = (cond.get('severity', 'mild') if isinstance(cond, dict) else 'mild').lower()
        deduction = severity_deductions.get(severity, 5)
        if name in severe_conditions:
            deduction += 5
        score -= deduction
    return max(10, min(100, score))


# ═══════════════════════════════════════════════════════════════════════════════
# IMAGE PRE-PROCESSING
# ═══════════════════════════════════════════════════════════════════════════════

def _preprocess_for_analysis(image_path: str) -> str:
    """
    Apply CLAHE (Contrast Limited Adaptive Histogram Equalization) to the image.
    Returns path to enhanced image (written to a temp file).

    CLAHE dramatically improves detectability of:
      - Dark circles (subtle periorbital discolouration)
      - Mild pigmentation and melasma
      - Early fine lines and texture
      - Broken capillaries

    The original file is NOT modified.
    """
    try:
        import cv2
        import numpy as np

        img = cv2.imread(image_path)
        if img is None:
            return image_path

        # Convert to LAB colour space — apply CLAHE only on L (luminance) channel
        lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
        l, a, b = cv2.split(lab)

        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        l_enhanced = clahe.apply(l)

        enhanced_lab = cv2.merge([l_enhanced, a, b])
        enhanced_bgr = cv2.cvtColor(enhanced_lab, cv2.COLOR_LAB2BGR)

        # Write to temp file
        suffix = os.path.splitext(image_path)[1] or '.jpg'
        tmp = tempfile.NamedTemporaryFile(
            delete=False, suffix=f'_clahe{suffix}',
            dir=os.path.dirname(image_path)
        )
        cv2.imwrite(tmp.name, enhanced_bgr)
        tmp.close()
        return tmp.name

    except Exception as exc:
        logger.warning('CLAHE preprocessing failed (non-critical): %s', exc)
        return image_path


# ═══════════════════════════════════════════════════════════════════════════════
# FACE DETECTION  —  SSD (primary) + Haar (fallback)
# ═══════════════════════════════════════════════════════════════════════════════

def _fix_exif_rotation(image_path: str) -> str:
    """
    Correct EXIF orientation on mobile photos before face detection.
    OpenCV ignores EXIF, so rotated selfies appear sideways to the detector.
    Returns path to corrected image (new temp file) or original path on failure.
    """
    try:
        from PIL import Image as PILImage, ExifTags
        pil_img = PILImage.open(image_path)
        exif = pil_img._getexif() if hasattr(pil_img, '_getexif') else None
        orientation = 1
        if exif:
            for tag_id, val in exif.items():
                if ExifTags.TAGS.get(tag_id) == 'Orientation':
                    orientation = val
                    break

        rotation_map = {3: 180, 6: 270, 8: 90}
        angle = rotation_map.get(orientation, 0)
        if angle == 0:
            return image_path

        import cv2
        img = cv2.imread(image_path)
        if img is None:
            return image_path

        rotate_flags = {90: cv2.ROTATE_90_CLOCKWISE, 180: cv2.ROTATE_180, 270: cv2.ROTATE_90_COUNTERCLOCKWISE}
        img = cv2.rotate(img, rotate_flags[angle])

        suffix = os.path.splitext(image_path)[1] or '.jpg'
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=f'_rot{suffix}',
                                          dir=os.path.dirname(image_path))
        cv2.imwrite(tmp.name, img)
        tmp.close()
        logger.info('EXIF rotation corrected: %d degrees', angle)
        return tmp.name

    except Exception as exc:
        logger.warning('EXIF rotation fix failed (non-critical): %s', exc)
        return image_path


def _detect_face_mediapipe(image_path: str) -> tuple[bool, Optional[tuple]]:
    """
    MediaPipe BlazeFace — the best detector for mobile selfies.
    Handles close-up faces, varied skin tones, angles, and lighting.
    Returns (found, bbox_xywh) or (False, None).
    """
    try:
        import mediapipe as mp
        import cv2

        img = cv2.imread(image_path)
        if img is None:
            logger.error('MediaPipe: cv2.imread returned None for %s', image_path)
            return False, None

        h, w = img.shape[:2]
        img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

        mp_face = mp.solutions.face_detection
        with mp_face.FaceDetection(model_selection=1, min_detection_confidence=0.3) as detector:
            results = detector.process(img_rgb)

        if results.detections:
            det = results.detections[0]
            bbox = det.location_data.relative_bounding_box
            x = max(0, int(bbox.xmin * w))
            y = max(0, int(bbox.ymin * h))
            bw = min(w - x, int(bbox.width * w))
            bh = min(h - y, int(bbox.height * h))
            logger.info('MediaPipe detected face: score=%.2f bbox=(%d,%d,%d,%d)',
                        det.score[0], x, y, bw, bh)
            return True, (x, y, bw, bh)

        logger.info('MediaPipe: no face found (image %dx%d)', w, h)
        return False, None

    except Exception as exc:
        logger.warning('MediaPipe face detection error: %s', exc)
        return False, None


def _detect_face_ssd_relaxed(image_path: str) -> tuple[bool, Optional[tuple]]:
    """SSD DNN detector with lowered confidence threshold (0.3 instead of 0.5)."""
    try:
        import cv2
        import numpy as np

        if not os.path.exists(SSD_MODEL_PATH) or not os.path.exists(SSD_PROTO_PATH):
            logger.warning('SSD model files missing — skipping SSD')
            return False, None

        net = cv2.dnn.readNetFromCaffe(SSD_PROTO_PATH, SSD_MODEL_PATH)
        img = cv2.imread(image_path)
        if img is None:
            return False, None

        h, w = img.shape[:2]
        blob = cv2.dnn.blobFromImage(
            cv2.resize(img, (300, 300)), 1.0,
            (300, 300), (104.0, 177.0, 123.0)
        )
        net.setInput(blob)
        detections = net.forward()

        best_conf, best_bbox = 0.0, None
        for i in range(detections.shape[2]):
            confidence = float(detections[0, 0, i, 2])
            if confidence < 0.3:          # lowered from 0.5
                continue
            if confidence > best_conf:
                best_conf = confidence
                box = detections[0, 0, i, 3:7] * [w, h, w, h]
                x1, y1, x2, y2 = box.astype(int)
                best_bbox = (max(0, x1), max(0, y1),
                             min(w, x2) - max(0, x1), min(h, y2) - max(0, y1))

        if best_bbox:
            logger.info('SSD detected face: conf=%.2f', best_conf)
            return True, best_bbox
        return False, None

    except Exception as exc:
        logger.warning('SSD face detection error: %s', exc)
        return False, None


def _detect_face_haar(image_path: str) -> tuple[bool, Optional[tuple]]:
    """Haar cascade — last resort. Tries multiple scale/neighbor settings."""
    try:
        import cv2
        img = cv2.imread(image_path)
        if img is None:
            return False, None

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        cv2.equalizeHist(gray, gray)   # improves detection on dark/bright selfies

        cp = HAARCASCADE_PATH
        if not os.path.exists(cp):
            cp = cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
        cascade = cv2.CascadeClassifier(cp)

        h_img, w_img = img.shape[:2]
        for scale, neighbors, min_size_ratio in [
            (1.1, 4, 0.15),
            (1.05, 3, 0.10),
            (1.1, 2, 0.08),
            (1.05, 2, 0.05),
        ]:
            min_dim = int(min(h_img, w_img) * min_size_ratio)
            faces = cascade.detectMultiScale(
                gray, scaleFactor=scale,
                minNeighbors=neighbors, minSize=(min_dim, min_dim)
            )
            if len(faces) > 0:
                x, y, fw, fh = [int(v) for v in faces[0]]
                logger.info('Haar detected face (scale=%.2f neighbors=%d)', scale, neighbors)
                return True, (x, y, fw, fh)

        logger.info('Haar: no face found')
        return False, None
    except Exception as exc:
        logger.warning('Haar face detection error: %s', exc)
        return False, None


def detect_face(image_path: str, already_rotated: bool = False) -> tuple[bool, Optional[tuple], list]:
    """
    Detect a face using three methods in order of reliability for mobile selfies:
      1. MediaPipe BlazeFace (best for selfies — handles close-ups, all skin tones)
      2. OpenCV SSD DNN (confidence threshold 0.3)
      3. Haar cascade (last resort, histogram-equalised)

    Pass already_rotated=True if EXIF correction was already applied upstream
    (avoids creating a redundant rotated temp file).
    Returns (has_face, bbox_xywh_or_None, temp_files_to_clean).
    """
    temp_files = []

    if already_rotated:
        path = image_path
    else:
        path = _fix_exif_rotation(image_path)
        if path != image_path:
            temp_files.append(path)

    # 1. MediaPipe (primary — built for mobile selfies)
    found, bbox = _detect_face_mediapipe(path)
    if found:
        return True, bbox, temp_files

    # 2. SSD DNN (secondary)
    found, bbox = _detect_face_ssd_relaxed(path)
    if found:
        return True, bbox, temp_files

    # 3. Haar (last resort)
    found, bbox = _detect_face_haar(path)
    return found, bbox, temp_files


def has_human_face(image_path: str) -> bool:
    found, _, _ = detect_face(image_path)
    return found


# ═══════════════════════════════════════════════════════════════════════════════
# FACE ZONE EXTRACTION
# ═══════════════════════════════════════════════════════════════════════════════

def _extract_periorbital_region(image_path: str, face_bbox: Optional[tuple]) -> Optional[str]:
    """
    Crop the periorbital (eye + under-eye) zone from the face.
    This region is passed to Gemini Pass 2 for focused dark-circle
    and eye-area analysis at much higher resolution detail.

    Returns path to cropped image temp file, or None if extraction fails.
    """
    try:
        import cv2

        img = cv2.imread(image_path)
        if img is None:
            return None

        h_img, w_img = img.shape[:2]

        if face_bbox:
            fx, fy, fw, fh = face_bbox
        else:
            fx, fy, fw, fh = 0, 0, w_img, h_img

        # Periorbital zone = upper 20%-60% of face height (eyes + under-eye area)
        # With generous horizontal margin
        eye_top    = fy + int(fh * 0.18)
        eye_bottom = fy + int(fh * 0.62)
        eye_left   = max(0, fx - int(fw * 0.05))
        eye_right  = min(w_img, fx + fw + int(fw * 0.05))

        cropped = img[eye_top:eye_bottom, eye_left:eye_right]
        if cropped.size == 0:
            return None

        # Scale up by 2× so Gemini gets more pixel detail on subtle areas
        scaled = cv2.resize(cropped, (cropped.shape[1] * 2, cropped.shape[0] * 2),
                            interpolation=cv2.INTER_LANCZOS4)

        suffix = os.path.splitext(image_path)[1] or '.jpg'
        tmp = tempfile.NamedTemporaryFile(
            delete=False, suffix=f'_eye{suffix}',
            dir=os.path.dirname(image_path)
        )
        cv2.imwrite(tmp.name, scaled)
        tmp.close()
        return tmp.name

    except Exception as exc:
        logger.warning('Periorbital crop failed (non-critical): %s', exc)
        return None


# ═══════════════════════════════════════════════════════════════════════════════
# LEGACY RESNET-50 (kept for backward compatibility — rarely used now)
# ═══════════════════════════════════════════════════════════════════════════════

_predictor = None


def _get_predictor():
    global _predictor
    if _predictor is not None:
        return _predictor
    if not os.path.exists(RESNET_MODEL_PATH):
        raise FileNotFoundError(f"ResNet model not found: {RESNET_MODEL_PATH}")
    if not os.path.exists(RESNET_JSON_PATH):
        raise FileNotFoundError(f"Model JSON not found: {RESNET_JSON_PATH}")
    from imageai.Classification.Custom import CustomImageClassification
    pred = CustomImageClassification()
    pred.setModelTypeAsResNet50()
    pred.setModelPath(RESNET_MODEL_PATH)
    pred.setJsonPath(RESNET_JSON_PATH)
    pred.loadModel()
    _predictor = pred
    return _predictor


def classify_skin(image_path: str) -> Tuple[list, list]:
    pred = _get_predictor()
    return pred.classifyImage(image_path, result_count=NUM_CLASSES)


# ═══════════════════════════════════════════════════════════════════════════════
# GEMINI VISION  —  PRIMARY ENGINE
# ═══════════════════════════════════════════════════════════════════════════════

# ── Pass 1: Full face clinical analysis ────────────────────────────────────────
_GEMINI_FULL_FACE_PROMPT = """You are a board-certified dermatology AI with expertise equivalent to a consultant dermatologist with 15 years of clinical experience.

You are performing a comprehensive skin analysis on this facial image. Your analysis must be as precise and detailed as a clinical skin consultation.

═══ ANALYSIS INSTRUCTIONS ═══

Step 1 — FACE ZONES
Mentally divide the face into zones and inspect each carefully:
• FOREHEAD: look for lines, texture, shine/dryness, acne, seborrhoeic scaling
• T-ZONE (nose + central forehead): enlarged pores, oiliness, blackheads, redness
• LEFT CHEEK: pigmentation, dryness, redness, broken capillaries, texture
• RIGHT CHEEK: same as left cheek
• CHIN/JAWLINE: acne (especially hormonal), skin texture
• PERIORBITAL (eye area): CRITICAL — examine extremely carefully:
  - Under-eye colour: blue-purple tint = vascular dark circles; brown tint = pigmentation dark circles; grey shadowing + hollowness = structural/tear trough
  - Even FAINT discolouration under the eyes must be reported as "Dark Circles" with severity "mild"
  - Puffy or swollen lower lids = Puffiness or Eye Bags
  - Fine lines under or beside eyes = Under-Eye Wrinkles or Crow's Feet
  - Hollow groove between lower lid and cheek = Tear Trough
  - Brown ring around entire orbital bone = Periorbital Hyperpigmentation

Step 2 — SKIN TYPE
Assess: Oily | Dry | Combination | Sensitive | Normal

Step 3 — CONDITION DETECTION
Flag every visible condition. Use clinical sensitivity — do NOT miss subtle findings.
DO NOT require a condition to be severe to report it. Report mild conditions.

[ACNE & BREAKOUTS]
Acne, Cystic Acne, Hormonal Acne, Blackheads, Whiteheads, Fungal Acne, Steroid Acne

[PIGMENTATION]
Hyperpigmentation, Dark Spots, Melasma, Post-Inflammatory Hyperpigmentation,
Uneven Skin Tone, Vitiligo, Sunspots

[AGING & LINES]
Fine Lines, Wrinkles, Crow's Feet, Nasolabial Folds, Forehead Lines,
Sagging Skin, Loss of Elasticity

[TEXTURE]
Enlarged Pores, Uneven Texture, Rough Patches, Flakiness, Acne Scars,
Textural Irregularities, Keratosis Pilaris

[EYE AREA — examine extremely carefully]
Dark Circles, Puffiness, Under-Eye Wrinkles, Eye Bags, Tired Eyes,
Periorbital Hyperpigmentation, Tear Trough

[SENSITIVITY & REDNESS]
Redness, Rosacea, Sensitive Skin, Contact Dermatitis, Perioral Dermatitis, Flushing

[HYDRATION & OIL BALANCE]
Dehydration, Dryness, Oiliness, Combination Skin Issues, Dullness, Tired Skin

[SKIN DISORDERS]
Eczema, Psoriasis, Seborrhoeic Dermatitis, Milia, Actinic Keratosis, Photodamage,
Broken Capillaries, Spider Veins, Sallowness, Sebaceous Hyperplasia

═══ SEVERITY SCALE ═══
mild     — present but subtle, requires close inspection
moderate — clearly visible to a casual observer
severe   — prominent, affecting significant skin area or causing concern

═══ ZONE-LEVEL ANALYSIS ═══
Provide a one-line assessment for each face zone.

═══ OUTPUT FORMAT ═══
Respond ONLY with valid JSON (no markdown, no explanation):

{
  "skin_type": "Combination",
  "skin_type_confidence": 85,
  "conditions": [
    {
      "name": "Dark Circles",
      "severity": "mild",
      "confidence": 78,
      "description": "Faint blue-purple tint visible under both eyes, consistent with vascular dark circles. More pronounced under left eye.",
      "zone": "periorbital"
    },
    {
      "name": "Enlarged Pores",
      "severity": "moderate",
      "confidence": 82,
      "description": "Visibly enlarged pores across T-zone, most prominent on nose.",
      "zone": "t_zone"
    }
  ],
  "zone_analysis": {
    "forehead":    "Slight oiliness visible, two small closed comedones present.",
    "t_zone":      "Enlarged pores and moderate shine. Blackheads visible on nose.",
    "left_cheek":  "Relatively clear with minor uneven texture.",
    "right_cheek": "One PIH mark from healed spot. Skin texture uneven.",
    "chin":        "Two active papules visible along jawline.",
    "periorbital": "Faint vascular dark circles bilaterally. Mild puffiness under left eye."
  },
  "primary_condition": "Enlarged Pores",
  "primary_condition_confidence": 82,
  "overall_skin_health": 72,
  "ai_notes": "Combination skin with active congestion in T-zone. Eye area shows early vascular dark circles — lifestyle factors (sleep, hydration) likely contributing. Good overall skin health with targeted treatment needed.",
  "image_quality": "good"
}

═══ CRITICAL RULES ═══
• image_quality: "good" | "poor_lighting" | "blurry" | "too_far" | "angle_issue"
• overall_skin_health: 100 = flawless, 0 = severe multi-condition skin
• List conditions from MOST to LEAST prominent
• ALWAYS include a "zone" field: forehead | t_zone | left_cheek | right_cheek | chin | periorbital | full_face
• If image is blurry/dark: report fewer conditions, lower confidence scores
• Be honest — do NOT inflate confidence above what the image supports
• Minimum 1 condition, maximum 15 conditions
• If you can see the periorbital area at all, you MUST assess it — even "no issues detected" should be noted in zone_analysis
"""

# ── Pass 2: Focused periorbital / eye area analysis ────────────────────────────
_GEMINI_EYE_FOCUS_PROMPT = """You are a consultant dermatologist specialising in periorbital skin conditions.

This is a CROPPED, ZOOMED image of the eye and under-eye area only.
Your single task: provide an expert, detailed analysis of this periorbital region.

═══ WHAT TO DETECT (examine each carefully) ═══

1. DARK CIRCLES
   - Blue-purple tint under eyes = VASCULAR dark circles (visible through thin skin)
   - Brown/tan discolouration = PIGMENTATION dark circles (melanin excess)
   - Grey shadow + visible hollow = STRUCTURAL dark circles (tear trough / fat loss)
   - Even FAINT or ONE-SIDED discolouration counts as "mild"

2. PUFFINESS — swelling/fluid retention under or above the eye
3. EYE BAGS — permanent fat herniation appearing as persistent pockets
4. UNDER-EYE WRINKLES — fine lines on the delicate lower eyelid skin
5. CROW'S FEET — fan lines at the outer eye corners
6. TEAR TROUGH — a visible groove/hollow between lower lid and cheek
7. PERIORBITAL HYPERPIGMENTATION — brown pigment ring around the orbital rim
8. TIRED EYES — dull, sunken, lacking vitality in the overall eye area
9. MILIA — tiny white cysts on the eyelid/under-eye skin
10. XANTHELASMA — yellowish plaques on or near eyelids

═══ SEVERITY SCALE ═══
mild     — present but subtle, only noticed on careful inspection
moderate — clearly visible
severe   — prominent, significant, affecting appearance markedly

═══ OUTPUT FORMAT ═══
Respond ONLY with valid JSON:

{
  "eye_conditions": [
    {
      "name": "Dark Circles",
      "severity": "mild",
      "confidence": 80,
      "type": "vascular",
      "description": "Faint blue-purple undertone visible under both eyes. More noticeable under the right eye. Consistent with vascular dark circles from visible underlying vessels through thin periorbital skin.",
      "zone": "periorbital"
    }
  ],
  "periorbital_notes": "Mild vascular dark circles with early tear trough formation. No significant puffiness or milia present. Eye area appears slightly fatigued.",
  "image_quality": "good"
}

═══ RULES ═══
• You MUST report dark circles if there is ANY discolouration, even faint
• "type" for Dark Circles: "vascular" | "pigmentation" | "structural" | "mixed"
• image_quality: "good" | "poor_lighting" | "blurry" | "too_close" | "angle_issue"
• Be clinically precise. Do not miss subtle findings.
• Return empty eye_conditions array ONLY if the skin is genuinely flawless
"""


def _call_gemini_vision(prompt: str, image_path: str, model_name: str, api_key: str) -> Optional[dict]:
    """
    Single Gemini Vision call. Returns parsed JSON dict or None.
    """
    import re
    try:
        import google.generativeai as genai
        import PIL.Image

        img = PIL.Image.open(image_path)
        # Resize to max 1280px — large enough for subtle detail, small enough for speed
        max_dim = 1280
        if max(img.size) > max_dim:
            ratio = max_dim / max(img.size)
            img = img.resize(
                (int(img.size[0] * ratio), int(img.size[1] * ratio)),
                PIL.Image.LANCZOS
            )

        genai.configure(api_key=api_key)
        gen_config = genai.GenerationConfig(temperature=0.15, max_output_tokens=2048)
        model      = genai.GenerativeModel(model_name)
        response   = model.generate_content([prompt, img], generation_config=gen_config)

        if not response or not response.text:
            return None

        text = response.text.strip()
        text = re.sub(r'^```json\s*', '', text)
        text = re.sub(r'^```\s*', '', text)
        text = re.sub(r'\s*```$', '', text)

        match = re.search(r'\{.*\}', text, re.DOTALL)
        if match:
            return json.loads(match.group())
        return None

    except json.JSONDecodeError as e:
        logger.warning('Gemini JSON parse error (%s): %s', model_name, e)
        return None
    except Exception as e:
        logger.debug('Gemini call failed (%s): %s', model_name, e)
        return None


def _gemini_analyse_full_face(image_path: str, api_key: str) -> dict:
    """Pass 1 — full face comprehensive analysis."""
    for model_name in ['gemini-2.0-flash', 'gemini-2.5-flash', 'gemini-1.5-flash']:
        result = _call_gemini_vision(_GEMINI_FULL_FACE_PROMPT, image_path, model_name, api_key)
        if result:
            result['_model'] = model_name
            logger.info('Gemini Pass 1 OK: model=%s', model_name)
            return result
    logger.error('All Gemini models failed for Pass 1')
    return {}


def _gemini_analyse_eye_region(eye_image_path: str, api_key: str) -> dict:
    """Pass 2 — focused periorbital analysis on cropped eye region."""
    for model_name in ['gemini-2.0-flash', 'gemini-2.5-flash', 'gemini-1.5-flash']:
        result = _call_gemini_vision(_GEMINI_EYE_FOCUS_PROMPT, eye_image_path, model_name, api_key)
        if result:
            logger.info('Gemini Pass 2 (eye focus) OK: model=%s', model_name)
            return result
    logger.warning('Gemini Pass 2 eye analysis failed — using Pass 1 results only')
    return {}


def _merge_eye_conditions(full_conditions: list, eye_data: dict) -> list:
    """
    Merge Pass 2 eye findings into Pass 1 conditions list.
    Rules:
      - If Pass 2 finds a condition that Pass 1 missed → add it
      - If both found the same condition → keep the one with higher confidence,
        but upgrade the description with Pass 2's detail (closer crop = better)
      - Eye conditions from Pass 2 take priority for description quality
    """
    if not eye_data or not eye_data.get('eye_conditions'):
        return full_conditions

    existing = {
        (c['name'] if isinstance(c, dict) else str(c)): i
        for i, c in enumerate(full_conditions)
    }

    for eye_cond in eye_data['eye_conditions']:
        name = eye_cond.get('name', '')
        if not name:
            continue

        if name in existing:
            idx       = existing[name]
            pass1_cond = full_conditions[idx]
            p2_conf   = eye_cond.get('confidence', 0)
            p1_conf   = pass1_cond.get('confidence', 0) if isinstance(pass1_cond, dict) else 0

            # Pass 2 always gets priority for description (closer crop)
            if isinstance(full_conditions[idx], dict):
                full_conditions[idx]['description'] = eye_cond.get('description', pass1_cond.get('description', ''))
                # Upgrade confidence to the higher value
                full_conditions[idx]['confidence']  = max(p1_conf, p2_conf)
                # Upgrade severity if Pass 2 found it worse
                sev_order = {'mild': 1, 'moderate': 2, 'severe': 3}
                p1_sev = pass1_cond.get('severity', 'mild')
                p2_sev = eye_cond.get('severity', 'mild')
                if sev_order.get(p2_sev, 1) > sev_order.get(p1_sev, 1):
                    full_conditions[idx]['severity'] = p2_sev
                # Add dark circle type if present
                if 'type' in eye_cond:
                    full_conditions[idx]['dark_circle_type'] = eye_cond['type']
        else:
            # Pass 2 found a condition missed by Pass 1 — add it
            new_cond = {
                'name':        name,
                'severity':    eye_cond.get('severity', 'mild'),
                'confidence':  eye_cond.get('confidence', 65),
                'description': eye_cond.get('description', ''),
                'zone':        'periorbital',
                '_source':     'pass2_eye_focus',
            }
            if 'type' in eye_cond:
                new_cond['dark_circle_type'] = eye_cond['type']
            full_conditions.append(new_cond)

    return full_conditions


# ═══════════════════════════════════════════════════════════════════════════════
# SKIN TYPE INFERENCE  (from multi-label condition probabilities)
# ═══════════════════════════════════════════════════════════════════════════════

def _infer_skin_type(all_probs: dict) -> tuple[str, float]:
    """
    Infer skin type from the model's condition probabilities.
    Returns (skin_type_string, confidence_0_to_100).
    """
    dry_prob   = all_probs.get('Dry_Skin',  0.0)
    oily_prob  = all_probs.get('Oily_Skin', 0.0)
    acne_prob  = all_probs.get('Acne',      0.0)
    eczema_prob = all_probs.get('Eczema_Dermatitis', 0.0)
    rosacea_prob = all_probs.get('Rosacea_Redness', 0.0)

    # Sensitive: high eczema or rosacea signal
    if max(eczema_prob, rosacea_prob) > 0.50:
        return 'Sensitive', round(max(eczema_prob, rosacea_prob) * 100, 1)

    # Dry
    if dry_prob > 0.55 and dry_prob > oily_prob:
        return 'Dry', round(dry_prob * 100, 1)

    # Oily
    if oily_prob > 0.55 and oily_prob > dry_prob:
        return 'Oily', round(oily_prob * 100, 1)

    # Combination: moderate oily + some dry OR acne + dry signals
    if oily_prob > 0.35 and (dry_prob > 0.25 or acne_prob > 0.40):
        conf = round(max(oily_prob, dry_prob) * 100, 1)
        return 'Combination', conf

    # Default to Normal
    return 'Normal', round(max(0.5, 1.0 - max(dry_prob, oily_prob, eczema_prob)) * 100, 1)


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN ANALYSIS PIPELINE
# ═══════════════════════════════════════════════════════════════════════════════

def _verify_image_readable(image_path: str) -> bool:
    """Confirm the file is a valid, openable image using PIL."""
    try:
        from PIL import Image as PILImage
        with PILImage.open(image_path) as img:
            img.verify()
        return True
    except Exception:
        return False


def analyse_face_image(image_path: str) -> dict:
    """
    Full skin analysis pipeline — your EfficientNet-B4 model is the primary engine.

    Pipeline:
      1. Image validity check  — PIL verify (rejects corrupt/non-image files)
      2. EXIF rotation fix     — corrects portrait selfies stored as landscape
      3. CLAHE preprocessing   — enhances subtle skin features
      4. EfficientNet-B4       — your trained model: 14-condition multi-label inference
      5. Face detection        — MediaPipe/SSD/Haar used ONLY to confirm a face is
                                  present; if all fail the model result still proceeds
                                  (mobile app is trusted to send selfies)
      6. Skin type inference   — derived from model probability distribution
      7. Recommendations       — routine + per-condition treatment plans
      8. Health score          — computed from detected conditions and severities

    Returns rich structured report for Flutter UI.
    """
    result = {
        "has_face":                    False,
        "skin_type":                   None,
        "skin_type_confidence":        0.0,
        "skin_disorder":               None,
        "skin_disorder_confidence":    0.0,
        "skin_conditions":             [],
        "zone_analysis":               {},
        "condition_scores":            {},
        "ai_notes":                    "",
        "image_quality":               "good",
        "recommendations":             {},
        "condition_recommendations":   {},
        "overall_skin_health_score":   75,
        "analysis_source":             "none",
        "error":                       None,
    }

    temp_files = []

    try:
        logger.info('=== SKIN ANALYSIS START: path=%s exists=%s size=%s ===',
                    image_path, os.path.exists(image_path),
                    os.path.getsize(image_path) if os.path.exists(image_path) else 'N/A')

        # ── Step 1: Image validity — reject corrupt or non-image files ───────────
        readable = _verify_image_readable(image_path)
        logger.info('Step1 PIL verify: readable=%s', readable)
        if not readable:
            logger.error('FAIL Step1: image not readable: %s', image_path)
            result["error"] = "no_face"
            return result

        # ── Step 2: Fix EXIF rotation so portrait selfies aren't sideways ────────
        rotated_path = _fix_exif_rotation(image_path)
        if rotated_path != image_path:
            temp_files.append(rotated_path)
        working_path = rotated_path
        logger.info('Step2 EXIF fix: rotated=%s working_path=%s', rotated_path != image_path, working_path)

        # ── Step 3: CLAHE preprocessing ──────────────────────────────────────────
        enhanced_path = _preprocess_for_analysis(working_path)
        if enhanced_path != working_path:
            temp_files.append(enhanced_path)
        logger.info('Step3 CLAHE: enhanced=%s path=%s', enhanced_path != working_path, enhanced_path)

        # ── Step 4: Your EfficientNet-B4 model (primary engine) ──────────────────
        from .skin_classifier import classify_face, is_model_available, MODEL_PATH as SKIN_MODEL_PATH

        model_exists = is_model_available()
        logger.info('Step4 model check: available=%s path=%s', model_exists, SKIN_MODEL_PATH)

        if not model_exists:
            logger.error('FAIL Step4: model file missing at %s', SKIN_MODEL_PATH)
            result["error"] = "model_missing:purepick_skin_model.pt"
            return result

        clf_result = classify_face(enhanced_path)
        logger.info('Step4 classify_face result: %s', 'None' if clf_result is None else f"{len(clf_result.get('conditions',[]))} conditions")
        if clf_result is None:
            logger.error('FAIL Step4: classify_face returned None — check skin_classifier logs above')
            result["error"] = "no_face"
            return result

        raw_conditions  = clf_result.get('conditions', [])
        all_probs       = clf_result.get('all_probabilities', {})
        analysis_source = f"purepick_efficientnet_b4_v{clf_result.get('model_version', '2')}"

        skin_conditions  = []
        condition_scores = {}
        for c in raw_conditions:
            if c['label'] == 'Normal_Skin' and len(raw_conditions) > 1:
                continue
            skin_conditions.append({
                "name":        c['name'],
                "severity":    c['severity'],
                "confidence":  c['confidence'],
                "description": c['description'],
                "zone":        c['zone'],
                "_source":     "efficientnet_b4",
            })
            condition_scores[c['name']] = c['confidence']

        skin_type, type_conf = _infer_skin_type(all_probs)
        result["skin_type"]            = skin_type
        result["skin_type_confidence"] = type_conf

        non_normal = [c for c in skin_conditions if c['name'] != 'Normal Skin']
        if non_normal:
            top = non_normal[0]
            result["skin_disorder"]            = top["name"]
            result["skin_disorder_confidence"] = float(top["confidence"])

        logger.info('EfficientNet-B4: type=%s conditions=%d', skin_type, len(skin_conditions))

        # ── Step 5: Face detection — confirmation only, not a gate ───────────────
        # EXIF rotation already applied at step 2, so pass already_rotated=True.
        # A miss does NOT block the result — the mobile app sends selfies.
        face_found, _, det_temps = detect_face(working_path, already_rotated=True)
        temp_files.extend(det_temps)
        result["has_face"] = True   # model ran successfully — image is valid
        logger.info('Face detection (confirmation): found=%s', face_found)

        result["skin_conditions"]  = skin_conditions
        result["condition_scores"] = condition_scores
        result["analysis_source"]  = analysis_source

        # ── Step 6: Fallback skin type ────────────────────────────────────────
        if not result["skin_type"]:
            result["skin_type"]            = "Normal"
            result["skin_type_confidence"] = 0.0

        # ── Step 7: Build AI notes summary ───────────────────────────────────
        if skin_conditions:
            top_names = [c['name'] for c in skin_conditions[:3]]
            result["ai_notes"] = (
                f"Analysis detected {len(skin_conditions)} skin condition(s). "
                f"Primary concerns: {', '.join(top_names)}. "
                f"Skin type: {result['skin_type']}. "
                f"Follow the targeted recommendations below for best results."
            )
        else:
            result["ai_notes"] = (
                f"Skin appears healthy with {result['skin_type'].lower()} characteristics. "
                "Maintain your current routine and ensure daily SPF protection."
            )

        # ── Step 8: Skin-type routine ─────────────────────────────────────────
        result["recommendations"] = get_routine(result["skin_type"])

        # ── Step 9: Per-condition treatment plans (top 8) ────────────────────
        cond_recs = {}
        for cond in result["skin_conditions"][:8]:
            name = cond['name'] if isinstance(cond, dict) else str(cond)
            rec  = get_condition_recommendation(name)
            if rec:
                cond_recs[name] = rec
        result["condition_recommendations"] = cond_recs

        # ── Step 10: Overall health score ─────────────────────────────────────
        result["overall_skin_health_score"] = _compute_skin_health_score(
            result["skin_type"], result["skin_conditions"]
        )

    finally:
        for tmp in temp_files:
            try:
                if os.path.exists(tmp):
                    os.unlink(tmp)
            except Exception:
                pass

    logger.info(
        "Skin analysis complete: type=%s conditions=%d score=%d source=%s",
        result["skin_type"],
        len(result["skin_conditions"]),
        result["overall_skin_health_score"],
        result["analysis_source"],
    )
    return result

"""
PurePick Ingredient Intelligence Layer — Stage 3.5
Scientific Name Resolver + Allergy Scoring Engine + RF ML Fallback

Batch 3 changes:
  ✓ RF classifier wired in for UNRESOLVED ingredients (dead code finally activated)
  ✓ predict_batch() used for efficiency — one inference call for all unknowns
  ✓ ML-predicted risks shown with 'ML_PREDICTED' severity band and confidence score
  ✓ Confidence threshold: only flag if RF says 'high' with ≥ 60% confidence
  ✓ Rule engine stays authoritative for all resolved ingredients
  ✓ Zero breaking changes to existing report shape
"""

# ── PART 1 — SCIENTIFIC NAME MASTER MAP ──────────────────────────────────────
INGREDIENT_MASTER_MAP = {
    # VITAMINS
    "vitamin c": [
        "ascorbic acid", "l-ascorbic acid", "ascorbyl glucoside",
        "sodium ascorbyl phosphate", "magnesium ascorbyl phosphate",
        "ascorbyl palmitate", "ascorbyl tetraisopalmitate",
        "3-o-ethyl ascorbic acid", "ethyl ascorbic acid",
        "ascorbate", "ascorbyl", "ascorbic acid 2-glucoside"
    ],
    "vitamin e": [
        "tocopherol", "alpha-tocopherol", "tocopheryl acetate",
        "tocopheryl linoleate", "tocopheryl nicotinate",
        "dl-alpha tocopherol", "mixed tocopherols", "tocophersolan"
    ],
    "vitamin a": [
        "retinol", "retinyl palmitate", "retinyl acetate",
        "retinaldehyde", "retinal", "retinoic acid", "tretinoin",
        "adapalene", "hydroxypinacolone retinoate",
        "granactive retinoid", "bakuchiol"
    ],
    "vitamin b3": ["niacinamide", "nicotinamide", "niacin", "nicotinic acid", "vitamin pp"],
    "vitamin b5": ["panthenol", "d-panthenol", "dl-panthenol", "pantothenic acid", "dexpanthenol"],
    "vitamin k": ["phylloquinone", "menaquinone", "phytonadione", "vitamin k1", "vitamin k2"],
    # ACIDS & EXFOLIANTS
    "salicylic acid": [
        "bha", "beta hydroxy acid", "beta-hydroxy acid",
        "2-hydroxybenzoic acid", "willow bark extract",
        "salix alba", "salicylate"
    ],
    "glycolic acid": ["aha", "alpha hydroxy acid", "alpha-hydroxy acid", "hydroacetic acid", "2-hydroxyacetic acid"],
    "lactic acid": ["2-hydroxypropanoic acid", "lactate", "sodium lactate", "ammonium lactate"],
    "hyaluronic acid": [
        "sodium hyaluronate", "ha", "hyaluronan",
        "hydrolyzed hyaluronic acid", "hyaluronic acid crosspolymer",
        "sodium hyaluronate crosspolymer", "potassium hyaluronate"
    ],
    "kojic acid": ["5-hydroxy-2-(hydroxymethyl)-4h-pyran-4-one", "kojic acid dipalmitate"],
    "azelaic acid": ["nonanedioic acid", "1,7-heptanedicarboxylic acid"],
    "ferulic acid": ["4-hydroxy-3-methoxycinnamic acid", "trans-ferulic acid"],
    "citric acid": ["2-hydroxypropane-1,2,3-tricarboxylic acid", "citrate", "sodium citrate", "trisodium citrate"],
    # PRESERVATIVES
    "paraben": [
        "methylparaben", "ethylparaben", "propylparaben",
        "butylparaben", "isobutylparaben", "isopropylparaben",
        "benzylparaben", "methyl 4-hydroxybenzoate",
        "ethyl 4-hydroxybenzoate", "propyl 4-hydroxybenzoate",
        "parahydroxybenzoate"
    ],
    "formaldehyde": [
        "quaternium-15", "dmdm hydantoin", "imidazolidinyl urea",
        "diazolidinyl urea", "bronopol", "2-bromo-2-nitropropane-1,3-diol",
        "5-bromo-5-nitro-1,3-dioxane", "sodium hydroxymethylglycinate", "methenamine",
        "polyoxymethylene urea", "glyoxal"
    ],
    "methylisothiazolinone": [
        "mi", "mit", "methylchloroisothiazolinone", "mci", "kathon cg",
        "neolone", "isothiazolinone", "2-methyl-4-isothiazolin-3-one"
    ],
    "phenoxyethanol": ["2-phenoxyethanol", "ethylene glycol monophenyl ether", "phenoxetol", "rose ether"],
    "triclosan": ["5-chloro-2-(2,4-dichlorophenoxy)phenol", "irgasan dp300"],

    # SURFACTANTS
    "sodium lauryl sulfate": ["sls", "sodium dodecyl sulfate", "sds", "lauryl sodium sulfate", "monododecyl ester"],
    "sodium laureth sulfate": ["sles", "sodium lauryl ether sulfate", "sodium lauryl ether sulphate"],
    "ammonium lauryl sulfate": ["als", "ammonium dodecyl sulfate"],
    "cocamidopropyl betaine": ["capb", "tegobetaine", "cadp"],

    # FRAGRANCES
    "fragrance": [
        "parfum", "aroma", "linalool", "limonene", "citronellol", "geraniol", "eugenol", "cinnamal",
        "cinnamyl alcohol", "benzyl alcohol", "benzyl salicylate", "benzyl benzoate", "amyl cinnamal", "coumarin",
        "farnesol", "hexyl cinnamal", "hydroxycitronellal", "isoeugenol", "lilial", "alpha-isomethyl ionone",
        "evernia prunastri", "evernia furfuracea", "butylphenyl methylpropional"
    ],

    # PHTHALATES & CONTROVERSIAL
    "phthalate": [
        "dibutyl phthalate", "dbp", "diethyl phthalate", "dep",
        "dimethyl phthalate", "dmp", "phthalic acid"
    ],
    "hydroquinone": ["1,4-dihydroxybenzene", "quinol", "benzene-1,4-diol"],
    "coal tar": ["p-phenylenediamine", "coal tar solution", "tar", "carbo-cort"],

    # OILS & EMOLLIENTS
    "peanut oil": ["arachis oil", "arachis hypogaea seed oil", "groundnut oil", "arachidic oil"],
    "coconut oil": ["cocos nucifera oil", "cocos nucifera", "fractionated coconut oil", "caprylic/capric triglyceride"],
    "almond oil": ["prunus amygdalus dulcis oil", "sweet almond oil", "prunus dulcis", "amygdalus communis"],
    "argan oil": ["argania spinosa kernel oil", "moroccan oil"],
    "shea butter": ["butyrospermum parkii butter", "vitellaria paradoxa", "karite butter", "shea oil"],
    "lanolin": ["wool wax", "wool fat", "adeps lanae", "lanolin alcohol", "acetylated lanolin", "hydroxylated lanolin", "lanolin cera"],
    # SILICONES
    "silicone": [
        "dimethicone", "cyclomethicone", "cyclopentasiloxane", "cyclohexasiloxane",
        "phenyl trimethicone", "amomodimethicone", "siloxane", "methicone", "dimethiconol"
    ],
    # ALCOHOLS
    "alcohol": ["ethanol", "denatured alcohol", "alcohol denat", "sd alcohol", "isopropyl alcohol", "isopropanol", "ethyl alcohol", "benzyl alcohol"],
    "fatty alcohol": ["cetyl alcohol", "stearyl alcohol", "cetearyl alcohol", "behenyl alcohol", "myristyl alcohol", "lauryl alcohol"],
    # SUNSCREEN ACTIVES
    "oxybenzone": ["benzophenone-3", "2-hydroxy-4-methoxybenzophenone"],
    "avobenzone": ["butyl methoxydibenzoylmethane", "parsol 1789"],
    "octinoxate": ["ethylhexyl methoxycinnamate", "octyl methoxycinnamate"],
    "zinc oxide": ["zno", "zinc white", "ci 77947"],
    "titanium dioxide": ["tio2", "titanium white", "ci 77891"],
    # COLORANTS
    "carmine": ["cochineal", "carminic acid", "crimson lake", "natural red 4", "ci 75470", "e120"],
}

# ── PART 2 — RESOLVER ─────────────────────────────────────────────────────────
def resolve_ingredient(raw_ingredient: str) -> dict:
    raw_lower = raw_ingredient.lower().strip()
    for common_name, aliases in INGREDIENT_MASTER_MAP.items():
        if raw_lower == common_name:
            return {"raw": raw_ingredient, "common_name": common_name.title(), "all_aliases": aliases, "match_method": "common_name_exact", "resolved": True}
        if raw_lower in common_name or common_name in raw_lower:
            return {"raw": raw_ingredient, "common_name": common_name.title(), "all_aliases": aliases, "match_method": "common_name_partial", "resolved": True}
        for alias in aliases:
            if raw_lower == alias or raw_lower in alias or alias in raw_lower:
                return {"raw": raw_ingredient, "common_name": common_name.title(), "all_aliases": aliases, "match_method": "alias_match", "matched_alias": alias, "resolved": True}
    return {"raw": raw_ingredient, "common_name": raw_ingredient, "all_aliases": [], "match_method": "unresolved", "resolved": False}

# ── PART 3 — ALLERGY MAPS ─────────────────────────────────────────────────────
PRESET_ALLERGY_MAP = {
    "Nut Allergy": ["peanut oil", "arachis oil", "almond oil", "prunus amygdalus dulcis oil", "walnut", "hazelnut", "tree nut", "macadamia", "cashew"],
    "Fragrance Allergy": ["fragrance", "parfum", "linalool", "limonene", "geraniol", "eugenol", "cinnamal", "coumarin", "citronellol", "butylphenyl methylpropional"],
    "Latex Allergy": ["natural rubber", "latex", "hevea brasiliensis", "hevein"],
    "Gluten Sensitivity": ["wheat germ oil", "triticum vulgare", "hydrolyzed wheat protein", "barley extract", "oat extract", "avena sativa"],
    "Sulfate Sensitivity": ["sodium lauryl sulfate", "sls", "sodium laureth sulfate", "sles", "ammonium lauryl sulfate", "als"],
    "Paraben Sensitivity": ["paraben", "methylparaben", "ethylparaben", "propylparaben", "butylparaben"],
    "Alcohol Sensitivity": ["alcohol denat", "ethanol", "isopropyl alcohol", "sd alcohol", "isopropyl alcohol"],
    "Silicone Sensitivity": ["dimethicone", "cyclopentasiloxane", "cyclomethicone", "silicone", "dimethiconol"],
    "Lanolin Allergy": ["lanolin", "wool wax", "adeps lanae", "acetylated lanolin"],
    "Formaldehyde Allergy": ["formaldehyde", "quaternium-15", "dmdm hydantoin", "imidazolidinyl urea", "diazolidinyl urea", "bronopol"],
    "Sunscreen Chemical Allergy": ["oxybenzone", "benzophenone-3", "octinoxate", "avobenzone", "octocrylene"],
    "Nickel Allergy": ["nickel sulfate", "nickel", "cobalt"],
    "Soy Allergy": ["soy", "soybean", "glycine soja", "hydrolyzed soy protein", "tofu"],
    "Dairy Allergy": ["milk protein", "whey protein", "casein", "lactose", "dairy"],
    "Phthalate Sensitivity": ["phthalate", "dibutyl phthalate", "diethyl phthalate"],
}

SKIN_CONDITION_MAP = {
    "acne": ["coconut oil", "cocoa butter", "algae extract", "soybean oil", "flaxseed oil", "sodium chloride", "isopropyl myristate", "acetylated lanolin alcohol", "wheat germ oil", "mineral oil", "petrolatum", "dimethicone", "ethylhexyl palmitate"],
    "eczema": ["sodium lauryl sulfate", "sls", "fragrance", "parfum", "alcohol denat", "ethanol", "methylisothiazolinone", "formaldehyde", "propylene glycol", "lanolin", "essential oils"],
    "rosacea": ["alcohol denat", "witch hazel", "menthol", "peppermint", "eucalyptus oil", "fragrance", "sodium lauryl sulfate", "glycolic acid", "salicylic acid", "retinol", "cinnamaldehyde"],
    "psoriasis": ["alcohol", "fragrance", "sodium lauryl sulfate", "artificial dyes", "synthetic preservatives", "parabens"],
    "sensitive skin": ["fragrance", "parfum", "alcohol denat", "sodium lauryl sulfate", "glycolic acid", "retinol", "benzoyl peroxide", "synthetic dyes"],
    "dry skin": ["alcohol denat", "sd alcohol", "sodium lauryl sulfate", "salicylic acid", "bentonite", "kaolin"],
    "oily skin": ["mineral oil", "petrolatum", "heavy silicones", "dimethicone", "isopropyl myristate", "shea butter"],
    "hyperpigmentation": ["fragrance", "photosensitizing agents", "benzophenone", "citrus oils"],
}

SEVERITY_RULES = {
    "CRITICAL": ["Nut Allergy", "Latex Allergy", "Formaldehyde Allergy", "acne"],
    "MODERATE": ["Fragrance Allergy", "Sulfate Sensitivity", "Paraben Sensitivity", "Lanolin Allergy",
                 "Sunscreen Chemical Allergy", "Nickel Allergy", "eczema", "rosacea", "psoriasis"],
    "LOW": ["Gluten Sensitivity", "Alcohol Sensitivity", "Silicone Sensitivity", "Soy Allergy",
            "Dairy Allergy", "sensitive skin", "dry skin", "oily skin", "hyperpigmentation"],
}

SCORE_TABLE = {
    ("CRITICAL", "Strong"): ("R10", 2.0, 30, True),
    ("CRITICAL", "Mild"):   ("R8",  1.6, 20, True),
    ("MODERATE", "Strong"): ("R8",  1.6, 20, True),
    ("MODERATE", "Mild"):   ("R7",  1.3, 15, True),
    ("LOW",      "Strong"): ("R5",  1.0, 10, False),
    ("LOW",      "Mild"):   ("R4",  0.8,  8, False),
    ("SAFE",     "None"):   ("R1",  0.0,  0, False),
}

def _score_rule(severity: str, match_strength: str) -> dict:
    key = (severity, match_strength)
    rule, weight, pts, trig = SCORE_TABLE.get(key, ("R1", 0.0, 0, False))
    return {"rule": rule, "contribution_weight": weight, "risk_points": pts, "band_trigger": trig}

# ── PART 3.5 — TOXIC / CONCONTROVERSIAL MAP ──────────────────────────────────
# These are flagged for ALL users, regardless of profile
TOXIC_INGREDIENTS_MAP = {
    "Mercury": ["mercury", "calomel", "mercuric", "mercurous chloride"],
    "Lead": ["lead acetate", "lead"],
    "Arsenic": ["arsenic"],
    "Phthalates (High Risk)": ["dibutyl phthalate", "dbp", "diethyl phthalate", "dep"],
    "Formaldehyde (Toxic)": ["formaldehyde", "glyoxal"],
    "Hydroquinone (Restricted)": ["hydroquinone"],
    "Triclosan": ["triclosan"],
    "Coal Tar": ["coal tar", "p-phenylenediamine"],
}

def match_ingredient_to_profile(resolved: dict, user_profile: dict) -> dict:
    raw_lower    = resolved["raw"].lower()
    common_lower = resolved["common_name"].lower()
    alias_list   = [a.lower() for a in resolved.get("all_aliases", [])]
    all_forms    = list(set([raw_lower, common_lower] + alias_list))

    def overlaps(trigger: str) -> bool:
        t = trigger.lower()
        return any(t in form or form in t for form in all_forms)

    # 1. Check for universally toxic ingredients first
    for concern, triggers in TOXIC_INGREDIENTS_MAP.items():
        for trigger in triggers:
            if overlaps(trigger):
                return {"flagged": True, "match_source": "toxic_watch", "matched_concern": concern, "severity": "CRITICAL",
                        "matched_via": trigger, "display_name": resolved["common_name"],
                        "explanation": f"'{resolved['raw']}' is flagged as a high-risk/toxic ingredient by safety regulators.",
                        "score_rule": _score_rule("CRITICAL", "Strong")}

    # 2. Check for user-specific allergies
    for allergy in user_profile.get("allergies", []):
        # Case-insensitive lookup: profile stores lowercase, map keys are title-case
        allergy_key = next((k for k in PRESET_ALLERGY_MAP if k.lower() == allergy.lower()), allergy)
        for trigger in PRESET_ALLERGY_MAP.get(allergy_key, []):
            if overlaps(trigger):
                severity = "MODERATE"
                allergy_norm = allergy.lower()
                for level, items in SEVERITY_RULES.items():
                    if any(i.lower() == allergy_norm for i in items): severity = level; break
                return {"flagged": True, "match_source": "preset_allergy", "matched_concern": allergy, "severity": severity,
                        "matched_via": trigger, "display_name": resolved["common_name"],
                        "explanation": f"'{resolved['raw']}' (also known as '{resolved['common_name']}') was detected. Your profile includes '{allergy}'.",
                        "score_rule": _score_rule(severity, "Strong")}

    for condition in user_profile.get("skin_conditions", []):
        condition_key = next((k for k in SKIN_CONDITION_MAP if k.lower() == condition.lower()), condition)
        for trigger in SKIN_CONDITION_MAP.get(condition_key, []):
            if overlaps(trigger):
                severity = "MODERATE"
                condition_norm = condition.lower()
                for level, items in SEVERITY_RULES.items():
                    if any(i.lower() == condition_norm for i in items): severity = level; break
                return {"flagged": True, "match_source": "skin_condition", "matched_concern": condition, "severity": severity,
                        "matched_via": trigger, "display_name": resolved["common_name"],
                        "explanation": f"'{resolved['raw']}' (also known as '{resolved['common_name']}') was detected. Your profile includes '{condition}'.",
                        "score_rule": _score_rule(severity, "Mild")}

    for custom in user_profile.get("custom_allergens", []):
        custom_lower = custom.lower()
        if any(custom_lower in form or form in custom_lower for form in all_forms):
            return {"flagged": True, "match_source": "custom_allergen_direct", "matched_concern": f"Custom: {custom}",
                    "severity": "MODERATE", "matched_via": custom, "display_name": resolved["common_name"],
                    "explanation": f"'{resolved['raw']}' matches your custom allergen '{custom}'.",
                    "score_rule": _score_rule("MODERATE", "Strong")}
        custom_resolved = resolve_ingredient(custom)
        if custom_resolved["resolved"] and custom_resolved["common_name"].lower() == common_lower:
            return {"flagged": True, "match_source": "custom_allergen_alias", "matched_concern": f"Custom: {custom}",
                    "severity": "MODERATE", "matched_via": custom_resolved["common_name"], "display_name": resolved["common_name"],
                    "explanation": f"'{resolved['raw']}' matches your custom allergen '{custom}' (both are '{resolved['common_name']}').",
                    "score_rule": _score_rule("MODERATE", "Strong")}

    return {"flagged": False, "match_source": "none", "matched_concern": None, "severity": None,
            "display_name": resolved["common_name"], "explanation": None, "score_rule": None}


# ── PART 4 — RF ML AUGMENTATION ───────────────────────────────────────────────
# Confidence threshold: only surface RF predictions above this level
_RF_HIGH_RISK_THRESHOLD = 0.60

def _augment_with_ml(results: list, unresolved_indices: list) -> list:
    """
    For ingredients the rule engine couldn't resolve, run batch RF prediction.
    Only flags 'high' predictions with confidence ≥ RF_HIGH_RISK_THRESHOLD.

    WHY batch: one vec.transform() call is far cheaper than N individual calls.
    WHY only unresolved: rule engine has higher precision for known ingredients.
    WHY confidence gate: RF trained on small dataset — low-confidence predictions
    cause more noise than signal.
    """
    if not unresolved_indices:
        return results

    try:
        from .ml_model import predict_batch, is_model_available

        if not is_model_available():
            return results  # graceful no-op

        names_to_predict = [results[i]['raw_ingredient'] for i in unresolved_indices]
        predictions      = predict_batch(names_to_predict)

        for idx, ingredient_name in zip(unresolved_indices, names_to_predict):
            pred = predictions.get(ingredient_name)
            if pred is None:
                continue

            predicted_class = pred['predicted_class']
            confidence      = pred['confidence']

            # Only act on high-confidence 'high' risk predictions
            if predicted_class == 'high' and confidence >= _RF_HIGH_RISK_THRESHOLD:
                entry = results[idx]
                entry['flagged']         = True
                entry['match_source']    = 'rf_model'
                entry['matched_concern'] = 'ML Predicted Risk'
                entry['severity']        = 'ML_PREDICTED'
                entry['explanation']     = (
                    f"'{entry['raw_ingredient']}' is not in our curated database, but our "
                    f"AI model predicts it carries a potential risk "
                    f"(confidence: {confidence*100:.0f}%). Review carefully."
                )
                entry['risk_points']     = 10   # conservative — less than rule engine MODERATE
                entry['rule']            = 'R_ML'
                entry['ml_confidence']   = confidence
                entry['ml_probabilities'] = pred['probabilities']
            elif predicted_class in ('safe', 'moderate'):
                # Annotate safe/moderate predictions as informational — not flagged
                results[idx]['ml_prediction'] = {
                    'class': predicted_class,
                    'confidence': confidence,
                }

    except Exception as exc:
        import logging
        logging.getLogger(__name__).warning('ML augmentation failed: %s', exc)
        # Always return results — never let ML failure break the pipeline

    return results


# ── PART 5 — MAIN PIPELINE ────────────────────────────────────────────────────
def run_ingredient_intelligence(ingredients: list, user_profile: dict) -> dict:
    """
    Full ingredient intelligence pipeline:
      1. Resolve each ingredient (INCI alias mapping)
      2. Match against user allergy/skin profile (rule engine)
      3. For unresolved ingredients: RF ML classifier augmentation
      4. Aggregate scores and assign risk band
    """
    results           = []
    flagged_items     = []
    safe_items        = []
    total_score       = 0
    triggered         = False
    unresolved_indices = []          # indices of ingredients the rule engine couldn't identify

    for idx, raw in enumerate(ingredients):
        resolved  = resolve_ingredient(raw)
        match     = match_ingredient_to_profile(resolved, user_profile)
        score_info = match.get("score_rule") or _score_rule("SAFE", "None")

        total_score += score_info["risk_points"]
        if score_info["band_trigger"]:
            triggered = True

        entry = {
            "raw_ingredient":   raw,
            "common_name":      resolved["common_name"],
            "resolved":         resolved["resolved"],
            "flagged":          match["flagged"],
            "matched_concern":  match.get("matched_concern"),
            "severity":         match.get("severity"),
            "explanation":      match.get("explanation"),
            "risk_points":      score_info["risk_points"],
            "rule":             score_info["rule"],
            "match_source":     match.get("match_source", "none"),
        }
        results.append(entry)

        if not resolved["resolved"] and not match["flagged"]:
            unresolved_indices.append(idx)

    # ── RF augmentation pass (batch, only for unresolved ingredients) ─────────
    results = _augment_with_ml(results, unresolved_indices)

    # ── Re-aggregate after ML augmentation ────────────────────────────────────
    total_score = 0
    triggered   = False
    for entry in results:
        total_score += entry.get("risk_points", 0)
        if entry.get("flagged") and entry.get("rule") in ("R7", "R8", "R10"):
            triggered = True
        if entry["flagged"]:
            flagged_items.append(entry)
        else:
            safe_items.append(entry["raw_ingredient"])

    risk_band = (
        "High Risk" if (total_score >= 51 or triggered)
        else "Moderate" if total_score >= 21
        else "Safe"
    )

    return {
        "all_ingredients":  results,
        "flagged_ingredients": flagged_items,
        "safe_ingredients": safe_items,
        "total_risk_score": total_score,
        "risk_band":        risk_band,
        "total_flagged":    len(flagged_items),
        "ml_augmented":     len(unresolved_indices) > 0,
    }

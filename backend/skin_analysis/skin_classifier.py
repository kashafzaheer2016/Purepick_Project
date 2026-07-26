"""
skin_classifier.py  —  PurePick EfficientNet-B4 Skin Condition Classifier
==========================================================================
Loads the trained PurePick skin model (purepick_skin_model.pt) and runs
multi-label inference on a face image.

This module replaces Gemini Vision for skin condition detection.
No internet or API key required — fully local inference.

Model specs:
  Backbone:   EfficientNet-B4 (ImageNet pretrained → fine-tuned on DermNet)
  Task:       Multi-label classification (14 skin conditions)
  Input:      380×380 RGB image
  Output:     Per-condition probabilities (0.0 – 1.0)

Usage:
  from skin_analysis.skin_classifier import SkinClassifier
  clf = SkinClassifier()            # loads model once (cached)
  result = clf.predict('/path/to/face.jpg')
"""
from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Optional

import torch
import torch.nn as nn
import numpy as np

logger = logging.getLogger(__name__)

# ── Model file paths ──────────────────────────────────────────────────────────
_HERE             = Path(__file__).parent
_MODELS_DIR       = _HERE / "ml_models"
MODEL_PATH        = str(_MODELS_DIR / "purepick_skin_model.pt")
CLASSES_JSON_PATH = str(_MODELS_DIR / "purepick_skin_classes.json")

# ── Fallback defaults (in case JSON is missing) ───────────────────────────────
DEFAULT_CONDITIONS = [
    'Acne', 'Dark_Circles', 'Hyperpigmentation', 'Rosacea_Redness',
    'Eczema_Dermatitis', 'Dry_Skin', 'Oily_Skin', 'Fine_Lines_Wrinkles',
    'Enlarged_Pores', 'Acne_Scars', 'Melasma_Dark_Spots', 'Psoriasis',
    'Normal_Skin', 'Photodamage',
]
DEFAULT_IMAGE_SIZE = 380
DEFAULT_THRESHOLD  = 0.40

# ── Display name mapping (model label → user-friendly name) ───────────────────
_LABEL_TO_DISPLAY = {
    'Acne':               'Acne',
    'Dark_Circles':       'Dark Circles',
    'Hyperpigmentation':  'Hyperpigmentation',
    'Rosacea_Redness':    'Rosacea',
    'Eczema_Dermatitis':  'Eczema',
    'Dry_Skin':           'Dryness',
    'Oily_Skin':          'Oiliness',
    'Fine_Lines_Wrinkles':'Fine Lines',
    'Enlarged_Pores':     'Enlarged Pores',
    'Acne_Scars':         'Acne Scars',
    'Melasma_Dark_Spots': 'Melasma / Dark Spots',
    'Psoriasis':          'Psoriasis',
    'Normal_Skin':        'Normal Skin',
    'Photodamage':        'Photodamage',
}

# ── Zone mapping — which face zone each condition is most associated with ──────
_LABEL_TO_ZONE = {
    'Acne':               'full_face',
    'Dark_Circles':       'periorbital',
    'Hyperpigmentation':  'full_face',
    'Rosacea_Redness':    'full_face',
    'Eczema_Dermatitis':  'full_face',
    'Dry_Skin':           'full_face',
    'Oily_Skin':          't_zone',
    'Fine_Lines_Wrinkles':'full_face',
    'Enlarged_Pores':     't_zone',
    'Acne_Scars':         'full_face',
    'Melasma_Dark_Spots': 'full_face',
    'Psoriasis':          'full_face',
    'Normal_Skin':        'full_face',
    'Photodamage':        'full_face',
}

# ── Severity thresholds (probability → severity string) ───────────────────────
def _prob_to_severity(prob: float) -> str:
    if prob >= 0.75:
        return 'severe'
    elif prob >= 0.55:
        return 'moderate'
    else:
        return 'mild'


# ── Description templates per condition ───────────────────────────────────────
_DESCRIPTIONS = {
    'Acne':               'Active breakouts detected. Inflammatory papules or comedones present.',
    'Dark_Circles':       'Periorbital discolouration detected under the eye area.',
    'Hyperpigmentation':  'Areas of increased melanin producing darker patches on the skin.',
    'Rosacea_Redness':    'Persistent facial redness or flushing detected, consistent with rosacea.',
    'Eczema_Dermatitis':  'Inflamed, irritated skin patches consistent with eczema or dermatitis.',
    'Dry_Skin':           'Reduced sebum/moisture levels indicated by texture and surface appearance.',
    'Oily_Skin':          'Excess sebum production and shine visible, particularly in the T-zone.',
    'Fine_Lines_Wrinkles':'Surface lines and/or deeper wrinkles visible on facial skin.',
    'Enlarged_Pores':     'Visibly enlarged pore openings, most prominent in the T-zone.',
    'Acne_Scars':         'Post-acne marks, indentations, or textural scarring detected.',
    'Melasma_Dark_Spots': 'Patches of brown discolouration consistent with melasma or solar lentigines.',
    'Psoriasis':          'Scaled, thickened skin patches consistent with psoriatic changes.',
    'Normal_Skin':        'Balanced skin with no significant visible concerns detected.',
    'Photodamage':        'Signs of UV-related skin damage including uneven tone and premature aging.',
}


# ═══════════════════════════════════════════════════════════════════════════════
# MODEL ARCHITECTURE  (must match training notebook exactly)
# ═══════════════════════════════════════════════════════════════════════════════

class _PurePickSkinModel(nn.Module):
    """
    EfficientNet-B4 + custom multi-label head.
    Identical architecture to the training notebook.
    """
    def __init__(self, num_classes: int):
        super().__init__()
        import timm
        self.backbone = timm.create_model(
            'efficientnet_b4',
            pretrained=False,       # weights loaded from .pt file
            num_classes=0,
            global_pool='avg',
        )
        in_features = self.backbone.num_features  # 1792

        self.classifier = nn.Sequential(
            nn.Dropout(p=0.4),
            nn.Linear(in_features, 512),
            nn.BatchNorm1d(512),
            nn.ReLU(inplace=True),
            nn.Dropout(p=0.3),
            nn.Linear(512, num_classes),
        )

    def forward(self, x):
        return self.classifier(self.backbone(x))

    def predict_proba(self, x):
        return torch.sigmoid(self.forward(x))


# ═══════════════════════════════════════════════════════════════════════════════
# IMAGE PREPROCESSING  (must match training transforms exactly)
# ═══════════════════════════════════════════════════════════════════════════════

def _preprocess_image(image_path: str, image_size: int) -> Optional[torch.Tensor]:
    """
    Resize → Normalize(ImageNet mean/std) → Tensor  (pure PIL + torch, no numpy).

    Avoids numpy entirely on the inference path so torch/numpy version
    mismatches on the server cannot break preprocessing.
    Returns (1, 3, H, W) float32 tensor or None on error.
    """
    try:
        from PIL import Image as PILImage

        img = PILImage.open(image_path).convert('RGB')
        img = img.resize((image_size, image_size), PILImage.BILINEAR)

        # PIL → raw bytes → torch tensor, no numpy involved
        raw = img.tobytes()                                          # HxWx3 uint8
        tensor = torch.frombuffer(bytearray(raw), dtype=torch.uint8)
        tensor = tensor.view(image_size, image_size, 3)             # H W C
        tensor = tensor.permute(2, 0, 1).float().div(255.0)        # C H W, [0,1]

        # ImageNet normalisation
        mean = torch.tensor([0.485, 0.456, 0.406], dtype=torch.float32).view(3, 1, 1)
        std  = torch.tensor([0.229, 0.224, 0.225], dtype=torch.float32).view(3, 1, 1)
        tensor = (tensor - mean) / std

        return tensor.unsqueeze(0)   # (1, 3, H, W)

    except Exception as exc:
        logger.error('Image preprocessing failed: %s', exc)
        return None


# ═══════════════════════════════════════════════════════════════════════════════
# CLASSIFIER  (singleton — loaded once, cached for all subsequent requests)
# ═══════════════════════════════════════════════════════════════════════════════

class SkinClassifier:
    """
    Singleton skin condition classifier.

    Usage:
        clf    = SkinClassifier()
        result = clf.predict('/path/to/face.jpg')

    Result shape:
        {
            'conditions': [
                {
                    'name':        'Dark Circles',
                    'label':       'Dark_Circles',
                    'probability': 0.73,
                    'confidence':  73,
                    'severity':    'moderate',
                    'description': '...',
                    'zone':        'periorbital',
                },
                ...
            ],
            'condition_scores':  {'Dark Circles': 73, 'Acne': 45, ...},
            'all_probabilities': {'Dark_Circles': 0.73, ...},
            'is_normal':         False,
            'model_version':     '2.0',
        }
    """

    _instance: Optional['SkinClassifier'] = None
    _model:    Optional[_PurePickSkinModel] = None
    _meta:     Optional[dict] = None
    _device:   Optional[torch.device] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def is_loaded(self) -> bool:
        return self._model is not None

    def load(self) -> bool:
        """
        Load model weights from disk. Returns True on success.
        Safe to call multiple times — no-op if already loaded.
        """
        if self._model is not None:
            return True

        if not os.path.exists(MODEL_PATH):
            logger.warning(
                'PurePick skin model not found at %s. '
                'Train the model using the Colab notebook and place the .pt file there.',
                MODEL_PATH
            )
            return False

        try:
            # Load metadata
            meta = self._load_meta()

            # Detect device
            self._device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
            logger.info('Loading skin model on %s', self._device)

            # Build model architecture
            model = _PurePickSkinModel(num_classes=meta['num_classes'])

            # Load checkpoint
            checkpoint = torch.load(MODEL_PATH, map_location=self._device)

            # Handle both raw state_dict and wrapped checkpoint
            if isinstance(checkpoint, dict) and 'model_state_dict' in checkpoint:
                state_dict = checkpoint['model_state_dict']
                # Update meta with checkpoint metadata
                for key in ('conditions', 'num_classes', 'image_size', 'threshold', 'version'):
                    if key in checkpoint:
                        meta[key] = checkpoint[key]
            else:
                state_dict = checkpoint

            model.load_state_dict(state_dict, strict=True)
            model.to(self._device)
            model.eval()

            self._model = model
            self._meta  = meta
            logger.info(
                'PurePick skin model loaded: v%s | %d conditions | device=%s',
                meta.get('version', '?'), meta['num_classes'], self._device
            )
            return True

        except Exception as exc:
            logger.error('Failed to load skin model: %s', exc)
            self._model = None
            return False

    def _load_meta(self) -> dict:
        """Load class metadata from JSON, fall back to defaults."""
        if os.path.exists(CLASSES_JSON_PATH):
            with open(CLASSES_JSON_PATH) as f:
                return json.load(f)
        return {
            'conditions':  DEFAULT_CONDITIONS,
            'num_classes': len(DEFAULT_CONDITIONS),
            'image_size':  DEFAULT_IMAGE_SIZE,
            'threshold':   DEFAULT_THRESHOLD,
            'version':     'unknown',
        }

    @torch.no_grad()
    def predict(self, image_path: str) -> Optional[dict]:
        """
        Run inference on a face image.

        Args:
            image_path: Path to the face image (any format OpenCV supports).

        Returns:
            Prediction dict (see class docstring) or None if model not loaded.
        """
        if not self.is_loaded():
            if not self.load():
                return None

        meta       = self._meta
        conditions = meta['conditions']
        image_size = meta.get('image_size', DEFAULT_IMAGE_SIZE)
        threshold  = meta.get('threshold',  DEFAULT_THRESHOLD)

        # Preprocess
        tensor = _preprocess_image(image_path, image_size)
        if tensor is None:
            return None

        tensor = tensor.to(self._device)

        # Inference — use .tolist() not .numpy() to avoid numpy dependency
        probs = self._model.predict_proba(tensor)
        probs_list = probs.squeeze(0).cpu().tolist()   # plain Python list of floats

        # Build results
        all_probs  = {label: float(probs_list[i]) for i, label in enumerate(conditions)}

        detected = []
        for i, label in enumerate(conditions):
            prob = float(probs_list[i])
            if prob < threshold:
                continue
            if label == 'Normal_Skin':
                continue  # handled separately

            display_name = _LABEL_TO_DISPLAY.get(label, label.replace('_', ' '))
            detected.append({
                'name':        display_name,
                'label':       label,
                'probability': round(prob, 3),
                'confidence':  int(round(prob * 100)),
                'severity':    _prob_to_severity(prob),
                'description': _DESCRIPTIONS.get(label, ''),
                'zone':        _LABEL_TO_ZONE.get(label, 'full_face'),
            })

        # Sort by probability descending
        detected.sort(key=lambda x: x['probability'], reverse=True)

        # Is skin normal?
        normal_prob = all_probs.get('Normal_Skin', 0.0)
        is_normal   = (len(detected) == 0) or (normal_prob > 0.7 and len(detected) <= 1)

        if is_normal and not detected:
            detected.append({
                'name':        'Normal Skin',
                'label':       'Normal_Skin',
                'probability': round(normal_prob, 3),
                'confidence':  int(round(normal_prob * 100)),
                'severity':    'mild',
                'description': 'No significant skin concerns detected. Skin appears healthy and balanced.',
                'zone':        'full_face',
            })

        condition_scores = {c['name']: c['confidence'] for c in detected}

        return {
            'conditions':       detected,
            'condition_scores': condition_scores,
            'all_probabilities': all_probs,
            'is_normal':        is_normal,
            'model_version':    meta.get('version', 'unknown'),
        }


# ── Module-level singleton ────────────────────────────────────────────────────
_classifier = SkinClassifier()


def get_classifier() -> SkinClassifier:
    """Return the module-level classifier singleton."""
    return _classifier


def classify_face(image_path: str) -> Optional[dict]:
    """
    Convenience function — run prediction using the module singleton.
    Returns prediction dict or None if model is not available.
    """
    return _classifier.predict(image_path)


def is_model_available() -> bool:
    """Return True if the trained model file exists."""
    return os.path.exists(MODEL_PATH)

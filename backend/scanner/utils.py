"""
scanner/utils.py
================
Scan audit trail storage.

WHY replaced pickle with JSON:
  - Pickle files are executable — a malicious .pkl file in the scans/
    directory could run arbitrary code on deserialization.
  - JSON is human-readable, queryable, and safely loaded with json.loads().
  - Old save_scan_pkl() kept as deprecated alias for migration compatibility.
"""
import json
import logging
import os
import uuid
from datetime import datetime, timezone

from django.conf import settings

logger = logging.getLogger(__name__)


def save_scan_json(original_scan_data: dict, user_id) -> str | None:
    """
    Save raw scan data (OCR text + ingredient tokens) to a .json file.
    Returns the relative path string, or None on failure.
    """
    try:
        timestamp = datetime.now(tz=timezone.utc).strftime('%Y%m%d_%H%M%S')
        uid = uuid.uuid4().hex[:6]
        filename = f'scan_{user_id}_{timestamp}_{uid}.json'

        scans_dir = os.path.join(settings.BASE_DIR, 'scans')
        os.makedirs(scans_dir, exist_ok=True)

        filepath = os.path.join(scans_dir, filename)
        with open(filepath, 'w', encoding='utf-8') as fh:
            json.dump(original_scan_data, fh, ensure_ascii=False, default=str)

        return f'scans/{filename}'

    except Exception as exc:
        logger.error('save_scan_json failed: %s', exc)
        return None


# ⚠ DEPRECATED: kept only for any call sites not yet updated to save_scan_json
def save_scan_pkl(original_scan_data: dict, user_id) -> str | None:
    """
    Deprecated — use save_scan_json instead.
    Pickle is a security risk when files may be written by external sources.
    """
    logger.warning(
        'save_scan_pkl() is deprecated. Redirecting to save_scan_json(). '
        'Remove all pickle usage before production deployment.'
    )
    return save_scan_json(original_scan_data, user_id)

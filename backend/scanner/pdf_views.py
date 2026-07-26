"""
scanner/pdf_views.py
=====================
PDF export for scan results.

GET /api/scan/<scan_id>/export-pdf/
  → generates a formatted PDF of the scan result
  → returns as application/pdf download

WHY server-side PDF:
  - Consistent rendering across all devices
  - Can include server-computed data (alternatives, AI analysis)
  - No client-side PDF library needed in Flutter
  - Works even on low-end devices

Requires: reportlab (pip install reportlab)
Falls back to a plain text file if reportlab not installed.
"""
from __future__ import annotations

import io
import json
import logging

from django.http import HttpResponse, JsonResponse
from django.utils import timezone

from purepick_core.auth_utils import jwt_required, require_own_user
from purepick_core.models import ScanRecord

logger = logging.getLogger(__name__)


@jwt_required
def export_scan_pdf(request, scan_id: int):
    """
    GET /api/scan/<scan_id>/export-pdf/
    JWT required. Returns PDF if scan belongs to authenticated user.
    """
    user_id = request.auth_user_id

    try:
        scan = ScanRecord.objects.filter(
            id=scan_id,
            user_id=user_id,    # ownership enforced inline
        ).first()

        if not scan:
            return JsonResponse(
                {'error': 'Scan not found or access denied'}, status=404
            )

        pdf_bytes = _generate_pdf(scan)
        safe_name = scan.product_name.replace(' ', '_')[:40]
        filename  = f'purepick_{safe_name}_{scan.scanned_at.strftime("%Y%m%d")}.pdf'

        response = HttpResponse(pdf_bytes, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        response['Content-Length'] = len(pdf_bytes)
        return response

    except Exception as exc:
        logger.error('export_scan_pdf error for scan %s: %s', scan_id, exc)
        return JsonResponse({'error': 'PDF generation failed'}, status=500)


def _generate_pdf(scan: ScanRecord) -> bytes:
    """Generate a PDF report for a scan record. Returns bytes."""
    try:
        return _generate_with_reportlab(scan)
    except ImportError:
        logger.warning('reportlab not installed — generating plain text PDF substitute')
        return _generate_plain_text_fallback(scan)


def _generate_with_reportlab(scan: ScanRecord) -> bytes:
    """Full PDF with formatting using reportlab."""
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import cm
    from reportlab.lib import colors
    from reportlab.platypus import (
        SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable
    )

    buffer    = io.BytesIO()
    doc       = SimpleDocTemplate(buffer, pagesize=A4, topMargin=2*cm, bottomMargin=2*cm)
    styles    = getSampleStyleSheet()
    story     = []

    # ── Color palette ─────────────────────────────────────────────────────────
    SAGE_GREEN  = colors.HexColor('#9DC183')
    DARK_TEXT   = colors.HexColor('#1A1A1A')
    MUTED_TEXT  = colors.HexColor('#666666')
    risk_colors = {
        'safe':     colors.HexColor('#2E7D32'),
        'moderate': colors.HexColor('#E65100'),
        'high':     colors.HexColor('#C62828'),
    }
    risk_color = risk_colors.get(scan.risk_level, colors.HexColor('#666666'))

    # ── Header ────────────────────────────────────────────────────────────────
    header_style = ParagraphStyle(
        'Header',
        parent=styles['Heading1'],
        fontSize=22,
        textColor=SAGE_GREEN,
        spaceAfter=4,
    )
    story.append(Paragraph('PurePick AI', header_style))
    story.append(Paragraph(
        'Ingredient Safety Report',
        ParagraphStyle('SubHeader', parent=styles['Normal'],
                       fontSize=12, textColor=MUTED_TEXT, spaceAfter=12),
    ))
    story.append(HRFlowable(width='100%', color=SAGE_GREEN, thickness=1.5))
    story.append(Spacer(1, 0.4*cm))

    # ── Product metadata ──────────────────────────────────────────────────────
    meta_style = ParagraphStyle(
        'Meta', parent=styles['Normal'], fontSize=10, textColor=MUTED_TEXT
    )
    story.append(Paragraph(
        f'<b>Product:</b> {scan.product_name}', styles['Normal']
    ))
    story.append(Paragraph(
        f'<b>Scanned:</b> {scan.scanned_at.strftime("%B %d, %Y at %H:%M UTC")}',
        meta_style,
    ))
    story.append(Paragraph(
        f'<b>Source:</b> {scan.get_scan_source_display()}', meta_style
    ))
    if scan.barcode:
        story.append(Paragraph(f'<b>Barcode:</b> {scan.barcode}', meta_style))
    story.append(Spacer(1, 0.5*cm))

    # ── Score summary ─────────────────────────────────────────────────────────
    score_label = f'{scan.safety_score}/100'
    risk_label  = scan.risk_level.upper()
    summary_data = [
        ['Safety Score', 'Risk Level', 'Flagged Ingredients'],
        [score_label, risk_label, str(len(scan.get_flagged_list()))],
    ]
    t = Table(summary_data, colWidths=[5*cm, 5*cm, 5*cm])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), SAGE_GREEN),
        ('TEXTCOLOR',  (0, 0), (-1, 0), colors.white),
        ('FONTNAME',   (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE',   (0, 0), (-1, 0), 10),
        ('ALIGN',      (0, 0), (-1, -1), 'CENTER'),
        ('TEXTCOLOR',  (0, 1), (-1, 1), risk_color),
        ('FONTNAME',   (0, 1), (-1, 1), 'Helvetica-Bold'),
        ('FONTSIZE',   (0, 1), (-1, 1), 14),
        ('BOX',        (0, 0), (-1, -1), 0.5, colors.grey),
        ('INNERGRID',  (0, 0), (-1, -1), 0.25, colors.lightgrey),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.HexColor('#F9F9F9')]),
        ('TOPPADDING', (0, 0), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
    ]))
    story.append(t)
    story.append(Spacer(1, 0.5*cm))

    # ── Flagged ingredients ───────────────────────────────────────────────────
    flagged = scan.get_flagged_list()
    if flagged:
        story.append(Paragraph(
            '<b>Flagged Ingredients</b>',
            ParagraphStyle('SectionHead', parent=styles['Normal'],
                           fontSize=12, textColor=DARK_TEXT, spaceBefore=8, spaceAfter=4),
        ))
        for name in flagged:
            story.append(Paragraph(
                f'• {name}',
                ParagraphStyle('Flag', parent=styles['Normal'],
                               fontSize=10, textColor=risk_color, leftIndent=12),
            ))
        story.append(Spacer(1, 0.3*cm))

    # ── Raw ingredients ───────────────────────────────────────────────────────
    if scan.ingredients_raw:
        story.append(Paragraph(
            '<b>Full Ingredient List</b>',
            ParagraphStyle('SectionHead', parent=styles['Normal'],
                           fontSize=12, textColor=DARK_TEXT, spaceBefore=6, spaceAfter=4),
        ))
        story.append(Paragraph(
            scan.ingredients_raw,
            ParagraphStyle('Ings', parent=styles['Normal'],
                           fontSize=9, textColor=MUTED_TEXT, leading=14),
        ))
        story.append(Spacer(1, 0.3*cm))

    # ── AI analysis ───────────────────────────────────────────────────────────
    if scan.ai_analysis:
        story.append(HRFlowable(width='100%', color=colors.lightgrey, thickness=0.5))
        story.append(Spacer(1, 0.2*cm))
        story.append(Paragraph(
            '<b>AI Safety Analysis</b>',
            ParagraphStyle('SectionHead', parent=styles['Normal'],
                           fontSize=12, textColor=DARK_TEXT, spaceBefore=4, spaceAfter=4),
        ))
        story.append(Paragraph(
            scan.ai_analysis,
            ParagraphStyle('AI', parent=styles['Normal'], fontSize=10, leading=15),
        ))

    # ── Footer ────────────────────────────────────────────────────────────────
    story.append(Spacer(1, 0.5*cm))
    story.append(HRFlowable(width='100%', color=SAGE_GREEN, thickness=0.5))
    story.append(Spacer(1, 0.2*cm))
    footer_text = (
        f'Generated by PurePick AI · {timezone.now().strftime("%B %d, %Y")} · '
        f'For informational purposes only. Not a substitute for medical advice.'
    )
    story.append(Paragraph(
        footer_text,
        ParagraphStyle('Footer', parent=styles['Normal'],
                       fontSize=8, textColor=MUTED_TEXT),
    ))

    doc.build(story)
    return buffer.getvalue()


def _generate_plain_text_fallback(scan: ScanRecord) -> bytes:
    """Plain text report for when reportlab is not available."""
    lines = [
        'PUREPICK AI - INGREDIENT SAFETY REPORT',
        '=' * 40,
        f'Product:        {scan.product_name}',
        f'Scanned:        {scan.scanned_at.strftime("%B %d, %Y")}',
        f'Safety Score:   {scan.safety_score}/100',
        f'Risk Level:     {scan.risk_level.upper()}',
        '',
        'FLAGGED INGREDIENTS:',
        *[f'  - {f}' for f in scan.get_flagged_list()],
        '',
        'FULL INGREDIENTS:',
        scan.ingredients_raw,
        '',
        'AI ANALYSIS:',
        scan.ai_analysis or 'Not available',
        '',
        '=' * 40,
        'Generated by PurePick AI. For informational purposes only.',
    ]
    content = '\n'.join(lines)
    # Return as bytes with PDF content-type header — browser will handle it
    return content.encode('utf-8')

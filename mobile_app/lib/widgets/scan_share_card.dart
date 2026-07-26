import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

/// ScanShareCard renders a branded share card and provides the
/// share functionality.
class ScanShareCard extends StatelessWidget {
  final GlobalKey repaintKey;
  final String productName;
  final double score;
  final String riskLevel;
  final List<String> topFlagged;   // top 3 flagged ingredients
  final String? brandName;

  const ScanShareCard({
    super.key,
    required this.repaintKey,
    required this.productName,
    required this.score,
    required this.riskLevel,
    required this.topFlagged,
    this.brandName,
  });

  Color get _bgColor {
    final band = riskLevel.toLowerCase();
    if (band.contains('high')) return const Color(0xFFFFEBEE);
    if (band.contains('moderate')) return const Color(0xFFFFF8E1);
    return const Color(0xFFE8F5E9);
  }

  Color get _accentColor {
    final band = riskLevel.toLowerCase();
    if (band.contains('high')) return const Color(0xFFE53935);
    if (band.contains('moderate')) return const Color(0xFFF57F17);
    return const Color(0xFF2E7D32);
  }

  String get _icon {
    final band = riskLevel.toLowerCase();
    if (band.contains('high')) return '🚫';
    if (band.contains('moderate')) return '⚠️';
    return '✅';
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _accentColor.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9DC183),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'PurePick',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _icon,
                  style: const TextStyle(fontSize: 24),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Product name
            Text(
              productName,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (brandName != null && brandName!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                brandName!,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Score pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${score.toInt()}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _accentColor,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Safety Score',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        riskLevel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _accentColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Flagged ingredients
            if (topFlagged.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Flagged ingredients',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: topFlagged
                    .take(3)
                    .map(
                      (name) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _accentColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: _accentColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 11,
                            color: _accentColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],

            const SizedBox(height: 16),
            Divider(color: _accentColor.withOpacity(0.2)),
            const SizedBox(height: 8),
            Text(
              'Scanned with PurePick AI · purepick.app',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Service to capture the share card widget as an image and share it.
class ShareCardService {
  /// Captures the RepaintBoundary widget as PNG bytes.
  static Future<Uint8List?> captureCard(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('ShareCardService.captureCard error: $e');
      return null;
    }
  }

  /// Share the card using the system share sheet.
  static Future<void> shareCard(
    GlobalKey key,
    String productName, {
    BuildContext? context,
  }) async {
    try {
      final bytes = await captureCard(key);
      if (bytes == null) {
        _showError(context, 'Could not generate share image.');
        return;
      }

      // 1. Save to temp file
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/purepick_share.png').create();
      await file.writeAsBytes(bytes);

      // 2. Share using share_plus
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Check out this $productName analysis on PurePick! #PurePick #SkincareSafety',
        subject: 'PurePick Scan Result',
      );
      
    } catch (e) {
      debugPrint('ShareCardService.shareCard error: $e');
      _showError(context, 'Sharing failed. Please try again.');
    }
  }

  static void _showError(BuildContext? context, String message) {
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red[700],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import '../services/task_poller.dart';
import 'result_screen.dart';

/// Barcode scanner screen.
///
/// Lookup chain (transparent to the user — backend handles all tiers):
///   Tier 1 → Open Beauty Facts  (200k+ cosmetic products)
///   Tier 2 → Open Food Facts    (general goods)
///   Tier 3 → Gemini AI          (LLM training-data knowledge)
///
/// If all three tiers fail, prompts manual ingredient entry.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool   _isBusy     = false;
  bool   _hasScanned = false;
  String _statusMessage = 'Point camera at product barcode';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    // Debounce: only process first detection
    if (_isBusy || _hasScanned) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null) return;

    setState(() {
      _hasScanned   = true;
      _isBusy       = true;
      _statusMessage = 'Found barcode: $rawValue';
    });
    await _controller.stop();

    await _lookupBarcode(rawValue);
  }

  Future<void> _lookupBarcode(String barcode) async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;

      setState(() => _statusMessage = 'Looking up product...');

      // Step 1: Enqueue barcode analysis task
      final enqueueResponse = await ApiService.barcodeAnalysis(barcode, userId);
      final taskId = enqueueResponse['task_id'] as String?;
      if (taskId == null) throw Exception('No task ID returned.');

      // Step 2: Poll with live status updates
      final result = await TaskPoller.poll(
        taskId,
        onProgress: (status) {
          if (!mounted) return;
          setState(() {
            _statusMessage = switch (status) {
              'PENDING' => 'Searching product database...',
              'STARTED' => 'Analyzing ingredients...',
              _         => 'Processing...',
            };
          });
        },
      );

      if (!mounted) return;

      // Product not found in any database
      final resultStatus = result['status'] as String?;
      if (resultStatus == 'not_found' || resultStatus == 'no_ingredients') {
        _showProductNotFound(
          barcode,
          result['product_name'] as String? ?? barcode,
          result['message'] as String? ?? 'Product not found.',
        );
        return;
      }

      // ── Success — navigate to result screen ──────────────────────────────
      final totalScore    = (result['overall_score'] ?? 0).toDouble();
      final riskBand      = result['risk']?['risk_band'] ?? 'Safe';
      final aiInsight     = result['ai_insight'] ?? '';
      final personalWarn  = result['personal_warnings'] ?? '';
      final scanId        = result['scan_id'] as int?;
      final aiSourced     = result['ai_sourced'] as bool? ?? false;
      final lookupSource  = result['lookup_source'] as String? ?? '';

      final alerts      = result['allergy_result']?['allergy_alerts'] as List? ?? [];
      final dangerItems = alerts.map<Map<String, dynamic>>((item) => {
        'name':        item['ingredient'] ?? 'Unknown',
        'severity':    item['severity'] ?? 'MODERATE',
        'reason':      item['plain_explanation'] ?? item['matched_concern'] ?? '',
      }).toList();

      // Show a one-time info banner if Gemini AI supplied the ingredients
      if (aiSourced && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ingredients sourced from AI knowledge base — not found in product databases. '
                  'Verify on product label.',
                  style: PP.body(12, color: Colors.white),
                ),
              ),
            ]),
            backgroundColor: PP.gold,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: PP.r12),
            margin: const EdgeInsets.all(12),
          ),
        );
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            score:            totalScore.clamp(0, 100).toDouble(),
            riskLevel:        riskBand.toString(),
            dangerItems:      dangerItems,
            aiInsight:        aiInsight,
            personalWarnings: personalWarn,
            productName:      result['product_name'] as String?,
            brandName:        result['brand'] as String?,
            imageUrl:         result['image_url'] as String?,
            scanId:           scanId,
            lookupSource:     aiSourced ? 'gemini_knowledge' : lookupSource,
          ),
        ),
      );

    } on TaskFailedException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Lookup failed: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ── Not-found dialog ──────────────────────────────────────────────────────

  void _showProductNotFound(String barcode, String productName, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF261A1F) : PP.surface,
        shape: RoundedRectangleBorder(borderRadius: PP.r20),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: PP.warnTint, borderRadius: PP.r10),
            child: Icon(Icons.search_off_rounded, color: PP.warn, size: 22),
          ),
          const SizedBox(width: 12),
          Text('Product Not Found', style: PP.heading(16, color: Theme.of(context).colorScheme.onSurface)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: PP.body(13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1015) : PP.roseTint,
                borderRadius: PP.r12,
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: PP.rose, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'This barcode wasn\'t found in Open Beauty Facts, Open Food Facts, '
                  'or the AI knowledge base. You can enter the ingredient list manually.',
                  style: PP.body(11),
                )),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);   // back to home
            },
            child: Text('Cancel', style: PP.body(14, color: PP.muted)),
          ),
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              _showManualEntrySheet(barcode);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(gradient: PP.roseGrad, borderRadius: PP.pill),
              child: Text('Enter Manually', style: PP.heading(13, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Manual ingredient entry ───────────────────────────────────────────────

  void _showManualEntrySheet(String barcode) {
    final ctrl   = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1015) : PP.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: isDark ? Colors.white24 : PP.border, borderRadius: PP.pill),
              )),
              const SizedBox(height: 20),
              Text('Enter Ingredients', style: PP.heading(18, color: Theme.of(ctx).colorScheme.onSurface)),
              const SizedBox(height: 6),
              Text('Paste or type the full ingredient list from the product label.',
                  style: PP.body(13)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                maxLines: 6,
                style: PP.body(13, color: Theme.of(ctx).colorScheme.onSurface),
                decoration: PP.input('Ingredients', icon: Icons.list_alt_outlined,
                    hint: 'Water, Glycerin, Niacinamide, ...'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: LuxButton(
                  label: 'Analyze Ingredients',
                  icon: Icons.auto_awesome,
                  onPressed: () async {
                    final text = ctrl.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(ctx);
                    await _analyzeManual(text);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _analyzeManual(String ingredientsText) async {
    setState(() { _isBusy = true; _statusMessage = 'Analyzing ingredients...'; });
    try {
      final prefs  = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;

      // Parse comma-separated ingredients
      final ingredients = ingredientsText
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.length >= 2)
          .toList();

      if (ingredients.isEmpty) {
        throw Exception('No valid ingredients found. Please enter a comma-separated list.');
      }

      final enqueueResponse = await ApiService.analyzeIngredients(ingredients, userId);
      final taskId = enqueueResponse['task_id'] as String?;
      if (taskId == null) throw Exception('No task ID returned.');

      final result = await TaskPoller.poll(
        taskId,
        onProgress: (status) {
          if (!mounted) return;
          setState(() {
            _statusMessage = switch (status) {
              'PENDING' => 'Waiting in queue...',
              'STARTED' => 'Analyzing...',
              _         => 'Processing...',
            };
          });
        },
      );

      if (!mounted) return;

      final totalScore     = (result['overall_score'] ?? 0).toDouble();
      final riskBand       = result['risk']?['risk_band'] ?? 'Safe';
      final aiInsight      = result['ai_insight'] ?? '';
      final personalWarn   = result['personal_warnings'] ?? '';
      final scanId         = result['scan_id'] as int?;

      final alerts      = result['allergy_result']?['allergy_alerts'] as List? ?? [];
      final dangerItems = alerts.map<Map<String, dynamic>>((item) => {
        'name':        item['ingredient'] ?? 'Unknown',
        'severity':    item['severity'] ?? 'MODERATE',
        'reason':      item['plain_explanation'] ?? item['matched_concern'] ?? '',
      }).toList();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            score:            totalScore.clamp(0, 100).toDouble(),
            riskLevel:        riskBand.toString(),
            dangerItems:      dangerItems,
            aiInsight:        aiInsight,
            personalWarnings: personalWarn,
            scanId:           scanId,
          ),
        ),
      );

    } on TaskFailedException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red[700]),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ── Error helper ─────────────────────────────────────────────────────────────

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              _hasScanned    = false;
              _isBusy        = false;
              _statusMessage = 'Point camera at product barcode';
            });
            _controller.start();
          },
        ),
      ),
    );
    setState(() { _hasScanned = false; _isBusy = false; });
    _controller.start();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Scan Barcode',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onBarcodeDetected,
          ),

          // Scan guide overlay
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 260,
                  height: 140,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _isBusy ? PP.gold : PP.safe,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 20),
                // Source info chips
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SourceChip(label: 'Beauty Facts'),
                    const SizedBox(width: 6),
                    _SourceChip(label: 'Food Facts'),
                    const SizedBox(width: 6),
                    _SourceChip(label: 'AI Lookup', gold: true),
                  ],
                ),
              ],
            ),
          ),

          // Status + loading
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_isBusy) ...[
                  CircularProgressIndicator(color: PP.safe, strokeWidth: 3),
                  const SizedBox(height: 16),
                ],
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    key: ValueKey(_statusMessage),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Lookup source chip ────────────────────────────────────────────────────────
class _SourceChip extends StatelessWidget {
  final String label;
  final bool gold;
  const _SourceChip({required this.label, this.gold = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: gold ? PP.gold.withOpacity(0.25) : Colors.black45,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: gold ? PP.gold.withOpacity(0.6) : Colors.white24),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(gold ? Icons.auto_awesome : Icons.check_circle_outline,
              color: gold ? PP.gold : Colors.white60, size: 11),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(
              color: gold ? PP.gold : Colors.white60,
              fontSize: 10,
              fontWeight: gold ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );
}

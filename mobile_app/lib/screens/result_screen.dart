import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import '../widgets/scan_share_card.dart';

class ResultScreen extends StatefulWidget {
  final double score;
  final String riskLevel;
  final List<Map<String, dynamic>> dangerItems;
  final String aiInsight;
  final String personalWarnings;
  final String? productName;
  final String? brandName;
  final String? imageUrl;
  final int? scanId;
  /// Non-null when ingredients were sourced from Gemini AI knowledge base
  final String? lookupSource;

  const ResultScreen({
    super.key,
    required this.score,
    required this.riskLevel,
    required this.dangerItems,
    this.aiInsight = '',
    this.personalWarnings = '',
    this.productName,
    this.brandName,
    this.imageUrl,
    this.scanId,
    this.lookupSource,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  bool _isSaving = false;
  bool _isSaved  = false;
  bool _isDownloading = false;
  List<dynamic> _alternatives = [];
  bool _loadingAlts = true;
  final GlobalKey _shareKey = GlobalKey();
  late AnimationController _scoreCtrl;
  late Animation<double> _scoreAnim;

  Color get _riskColor {
    final l = widget.riskLevel.toLowerCase();
    if (l.contains('high')) return PP.danger;
    if (l.contains('moderate')) return PP.warn;
    return PP.safe;
  }

  Color get _riskTint {
    final l = widget.riskLevel.toLowerCase();
    if (l.contains('high')) return PP.dangerTint;
    if (l.contains('moderate')) return PP.warnTint;
    return PP.safeTint;
  }

  String get _riskLabel {
    final l = widget.riskLevel.toLowerCase();
    if (l.contains('high')) return 'High Risk';
    if (l.contains('moderate')) return 'Moderate';
    return 'Safe';
  }

  @override
  void initState() {
    super.initState();
    _scoreCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _scoreAnim = Tween<double>(begin: 0, end: widget.score / 100)
        .animate(CurvedAnimation(parent: _scoreCtrl, curve: Curves.easeOutCubic));
    _scoreCtrl.forward();
    _fetchAlternatives();
  }

  @override
  void dispose() { _scoreCtrl.dispose(); super.dispose(); }

  Future<void> _fetchAlternatives() async {
    // Fetch Clean Swaps based on product name/category
    try {
      final res = await ApiService.getAlternatives(
        category: widget.productName ?? 'moisturizer',
      );
      if (mounted) setState(() { _alternatives = res; _loadingAlts = false; });
    } catch (_) { if (mounted) setState(() => _loadingAlts = false); }
  }

  Future<void> _handleSave() async {
    final nameCtrl = TextEditingController(text: widget.productName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PP.surface,
        shape: RoundedRectangleBorder(borderRadius: PP.r20),
        title: Text('Save Product', style: PP.heading(18, color: PP.ink)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: PP.body(15, color: PP.ink),
          decoration: PP.input('Product Name', icon: Icons.spa_outlined),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: PP.body(14, color: PP.muted))),
          GestureDetector(
            onTap: () => Navigator.pop(ctx, nameCtrl.text),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(gradient: PP.roseGrad, borderRadius: PP.pill),
              child: Text('Save', style: PP.heading(14, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getInt('user_id') ?? 0;
      if (uid == 0) throw Exception('User not logged in');
      await ApiService.saveProduct(
        userId: uid, name: name,
        score: widget.score.toInt(), riskLevel: widget.riskLevel,
        ingredients: widget.dangerItems.map((e) => e['name']).join(', '),
      );
      if (mounted) {
        setState(() { _isSaved = true; _isSaving = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved to collection', style: PP.body(13, color: Colors.white)),
          backgroundColor: PP.safe,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: PP.r12),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: PP.body(13, color: Colors.white)),
          backgroundColor: PP.danger,
        ));
      }
    }
  }

  Future<void> _shareResult() async {
    // Show a loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: PP.rose)),
    );

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      await ShareCardService.shareCard(
        _shareKey, 
        widget.productName ?? 'Scanned Product', 
        context: context
      );
    } finally {
      if (mounted) Navigator.pop(context); // remove loading
    }
  }

  Future<void> _downloadPdf() async {
    if (widget.scanId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No scan ID available for this report.', style: PP.body(13, color: Colors.white)),
        backgroundColor: PP.warn, behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _isDownloading = true);
    try {
      // 1. Fetch PDF from backend
      final headers = await ApiService.authHeaders();
      final url = Uri.parse('${ApiService.baseUrl}/scan/${widget.scanId}/export-pdf/');
      final response = await http.get(url, headers: headers);

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      if (bytes.isEmpty) throw Exception('Empty PDF received');

      // 2. Save to temp directory
      final dir  = await getTemporaryDirectory();
      final name = 'PurePick_Scan_${widget.scanId}.pdf';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);

      // 3. Share / save via system sheet (user can pick Downloads, Drive, etc.)
      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: 'PurePick Safety Report — ${widget.productName ?? 'Scan #${widget.scanId}'}',
          subject: 'PurePick Scan Report',
        );
      }

    } catch (e) {
      debugPrint('PDF download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF failed: ${e.toString().replaceAll('Exception:', '').trim()}',
              style: PP.body(13, color: Colors.white)),
          backgroundColor: PP.danger, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: PP.r12),
          margin: const EdgeInsets.all(16),
        ));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Off-screen share card
          Positioned(
            left: -2000, top: 0,
            child: ScanShareCard(
              repaintKey: _shareKey,
              productName: widget.productName ?? 'Scanned Product',
              score: widget.score,
              riskLevel: widget.riskLevel,
              topFlagged: widget.dangerItems.take(3).map((e) => e['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList(),
              brandName: widget.brandName,
            ),
          ),

          CustomScrollView(
            slivers: [
              // ── Header ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF261A1F) : _riskTint,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      child: Column(
                        children: [
                          // Top bar
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1A1015) : Colors.white,
                                    borderRadius: PP.r10,
                                    boxShadow: PP.softShadow,
                                  ),
                                  child: Icon(Icons.arrow_back_ios_new, size: 16, color: theme.colorScheme.onSurface),
                                ),
                              ),
                              Text('Analysis Result', style: PP.heading(17, color: theme.colorScheme.onSurface)),
                              Row(children: [
                                GestureDetector(
                                  onTap: _shareResult,
                                  child: Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1A1015) : Colors.white, 
                                      borderRadius: PP.r10, 
                                      boxShadow: PP.softShadow,
                                    ),
                                    child: Icon(Icons.share_outlined, size: 18, color: theme.colorScheme.onSurface),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: (_isSaving || _isSaved) ? null : _handleSave,
                                  child: Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1A1015) : Colors.white, 
                                      borderRadius: PP.r10, 
                                      boxShadow: PP.softShadow,
                                    ),
                                    child: _isSaving
                                        ? Padding(padding: const EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: PP.rose))
                                        : Icon(_isSaved ? Icons.bookmark : Icons.bookmark_outline, size: 20, color: _isSaved ? PP.rose : theme.colorScheme.onSurface),
                                  ),
                                ),
                                if (widget.scanId != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: GestureDetector(
                                      onTap: _isDownloading ? null : _downloadPdf,
                                      child: Container(
                                        width: 40, height: 40,
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF1A1015) : Colors.white, 
                                          borderRadius: PP.r10, 
                                          boxShadow: PP.softShadow,
                                        ),
                                        child: _isDownloading
                                            ? Padding(padding: const EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: PP.rose))
                                            : Icon(Icons.picture_as_pdf_outlined, size: 20, color: theme.colorScheme.onSurface),
                                      ),
                                    ),
                                  ),
                              ]),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Score ring
                          AnimatedBuilder(
                            animation: _scoreAnim,
                            builder: (_, __) => SizedBox(
                              width: 140, height: 140,
                              child: Stack(alignment: Alignment.center, children: [
                                SizedBox(
                                  width: 140, height: 140,
                                  child: CircularProgressIndicator(
                                    value: _scoreAnim.value,
                                    strokeWidth: 10,
                                    backgroundColor: _riskColor.withOpacity(0.15),
                                    valueColor: AlwaysStoppedAnimation(_riskColor),
                                    strokeCap: StrokeCap.round,
                                  ),
                                ),
                                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Text('${(_scoreAnim.value * 100).toInt()}',
                                      style: PP.display(38, color: _riskColor, weight: FontWeight.w700)),
                                  Text('/ 100', style: PP.label(12, color: isDark ? Colors.white54 : PP.muted)),
                                ]),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Risk badge
                          SafetyBadge(level: widget.riskLevel, score: widget.score),
                          if (widget.dangerItems.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('${widget.dangerItems.length} concerns identified',
                                style: PP.label(10, color: _riskColor, weight: FontWeight.w500)),
                          ],
                          if (widget.productName != null) ...[
                            const SizedBox(height: 8),
                            Text(widget.productName!, style: PP.heading(15, color: theme.colorScheme.onSurface), textAlign: TextAlign.center),
                            if (widget.brandName != null)
                              Text(widget.brandName!, style: PP.label(12, color: isDark ? Colors.white60 : PP.muted)),
                          ],
                          // AI-sourced badge
                          if (widget.lookupSource == 'gemini_knowledge') ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: PP.gold.withOpacity(0.15),
                                borderRadius: PP.pill,
                                border: Border.all(color: PP.gold.withOpacity(0.4)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.auto_awesome, color: PP.gold, size: 13),
                                const SizedBox(width: 5),
                                Text('Ingredients sourced from AI — verify on label',
                                    style: PP.label(10, color: PP.gold, weight: FontWeight.w600)),
                              ]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                sliver: SliverList(delegate: SliverChildListDelegate([

                  // ── Flagged ingredients ──────────────────────────────────
                  if (widget.dangerItems.isNotEmpty) ...[
                    _Section(
                      icon: Icons.warning_amber_outlined,
                      iconColor: _riskColor,
                      title: 'Flagged Ingredients',
                      child: Column(
                        children: widget.dangerItems.map((item) {
                          final sev = (item['severity'] ?? '').toString().toUpperCase();
                          final isML = sev == 'ML_PREDICTED';
                          final color = sev == 'CRITICAL' ? PP.danger
                              : sev == 'ML_PREDICTED' ? PP.warn
                              : sev == 'MODERATE' ? PP.warn
                              : PP.muted;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.06),
                              borderRadius: PP.r12,
                              border: Border.all(color: color.withOpacity(0.2)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  margin: const EdgeInsets.only(top: 5),
                                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(child: Text(item['name']?.toString() ?? '',
                                          style: PP.heading(13, color: theme.colorScheme.onSurface))),
                                      if (isML)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: PP.warnTint, borderRadius: PP.pill,
                                              border: Border.all(color: PP.warn.withOpacity(0.3))),
                                          child: Text('AI Predicted', style: PP.label(9, color: PP.warn, weight: FontWeight.w600)),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: PP.pill),
                                          child: Text(sev, style: PP.label(9, color: color, weight: FontWeight.w600)),
                                        ),
                                    ]),
                                    if (item['reason'] != null && item['reason'].toString().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(item['reason'].toString(), style: PP.body(12, color: theme.colorScheme.onSurface.withOpacity(0.7)), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    ],
                                  ],
                                )),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Personal warnings ────────────────────────────────────
                  if (widget.personalWarnings.isNotEmpty) ...[
                    _Section(
                      icon: Icons.person_pin_outlined,
                      iconColor: PP.rose,
                      title: 'Your Profile Alerts',
                      child: Text(widget.personalWarnings, style: PP.body(13, color: theme.colorScheme.onSurface.withOpacity(0.9), weight: FontWeight.w400)),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── AI Insight ───────────────────────────────────────────
                  if (widget.aiInsight.isNotEmpty) ...[
                    _Section(
                      icon: Icons.auto_awesome_outlined,
                      iconColor: PP.gold,
                      title: 'AI Analysis',
                      gradient: isDark ? null : const LinearGradient(
                        colors: [Color(0xFFFBF6EE), Color(0xFFF5EEF0)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      child: Text(widget.aiInsight, style: PP.body(13, color: theme.colorScheme.onSurface.withOpacity(0.9))),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Clean Swaps (One-Tap Alternatives) ────────────────────────────────
                  if (!_loadingAlts && _alternatives.isNotEmpty && widget.score < 80) ...[
                    _Section(
                      icon: Icons.auto_awesome,
                      iconColor: PP.safe,
                      title: 'Clean Swaps (Highly Rated)',
                      child: Column(
                        children: _alternatives.map((alt) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E3A24) : PP.safeTint,
                            borderRadius: PP.r12,
                            border: Border.all(color: PP.safe.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(color: isDark ? const Color(0xFF261A1F) : Colors.white, borderRadius: PP.r10),
                                child: Icon(Icons.shopping_bag_outlined, color: PP.safe, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(alt['brand'] ?? '', style: PP.label(10, color: PP.safe)),
                                  Text(alt['name'] ?? '', style: PP.heading(13, color: theme.colorScheme.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
                                ],
                              )),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Safe badge ───────────────────────────────────────────
                  if (widget.dangerItems.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: PP.card(color: isDark ? const Color(0xFF261A1F) : PP.safeTint, borderColor: PP.safe.withOpacity(0.2)),
                      child: Column(children: [
                        Container(width: 56, height: 56,
                          decoration: BoxDecoration(color: PP.safe.withOpacity(0.15), shape: BoxShape.circle),
                          child: Icon(Icons.verified_outlined, color: PP.safe, size: 28)),
                        const SizedBox(height: 12),
                        Text('All Clear', style: PP.heading(18, color: PP.safe)),
                        const SizedBox(height: 6),
                        Text('No concerning ingredients found for your profile.',
                            style: PP.body(13, color: theme.colorScheme.onSurface.withOpacity(0.7)), textAlign: TextAlign.center),
                      ]),
                    ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: LuxButton(
                      label: 'Scan Another Product',
                      outlined: true,
                      icon: Icons.camera_alt_outlined,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ])),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Section Card ──────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;
  final Gradient? gradient;
  const _Section({required this.icon, required this.iconColor, required this.title,
      required this.child, this.gradient});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: gradient == null ? (isDark ? const Color(0xFF261A1F) : PP.surface) : null,
        gradient: gradient,
        borderRadius: PP.r16,
        border: Border.all(color: isDark ? const Color(0xFF3D2A30) : PP.border, width: 0.8),
        boxShadow: PP.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: iconColor.withOpacity(0.12), borderRadius: PP.r8),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 10),
          Text(title, style: PP.heading(14, color: theme.colorScheme.onSurface)),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}


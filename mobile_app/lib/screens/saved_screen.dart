import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import 'result_screen.dart';

class SavedScreen extends StatefulWidget {
  final bool isTab;
  const SavedScreen({super.key, this.isTab = false});
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  List<dynamic> _products = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    // Small delay to avoid concurrent startup request conflicts with other tabs
    await Future.delayed(const Duration(milliseconds: 400));
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getInt('user_id') ?? 0;
      if (uid == 0) throw Exception('Please log in to view saved products');
      final list = await ApiService.getSavedProducts(uid);
      if (mounted) setState(() { _products = list; _loading = false; });
    } catch (e) {
      debugPrint('SavedScreen load error: $e');
      if (mounted) setState(() {
        _error = e.toString().replaceAll('Exception:', '').trim();
        _loading = false;
      });
    }
  }

  Future<void> _delete(int id) async {
    try {
      await ApiService.deleteSavedProduct(id);
      if (mounted) {
        setState(() => _products.removeWhere((p) => p['id'] == id));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Removed from collection', style: PP.body(13, color: Colors.white)),
          backgroundColor: PP.muted,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: PP.r12),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: LuxAppBar(title: 'My Collection', showBack: !widget.isTab),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: PP.rose, strokeWidth: 2))
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.wifi_off_rounded, color: PP.muted, size: 48),
                    const SizedBox(height: 16),
                    Text('Could not load collection', style: PP.heading(15, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 8),
                    Text(_error!, style: PP.body(12, color: PP.muted), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PP.rose, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: PP.pill),
                      ),
                    ),
                  ]),
                ))
              : _products.isEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: isDark ? PP.gold.withOpacity(0.15) : PP.goldTint,
                            borderRadius: PP.r20,
                          ),
                          child: Icon(Icons.bookmark_outline, color: PP.gold, size: 34)),
                        const SizedBox(height: 16),
                        Text('Your collection is empty', style: PP.heading(16, color: theme.colorScheme.onSurface)),
                        const SizedBox(height: 6),
                        Text('Save product scans here for quick reference', style: PP.body(13, color: theme.colorScheme.onSurface.withOpacity(0.7)), textAlign: TextAlign.center),
                      ]),
                    ))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                      itemCount: _products.length,
                      itemBuilder: (_, i) {
                        final p = _products[i];
                        final score = (p['safety_score'] ?? 0).toDouble();
                        final band  = (p['risk_level'] ?? '').toString().toLowerCase();
                        final color = band.contains('high') ? PP.danger : band.contains('moderate') ? PP.warn : PP.safe;
                        final tint  = isDark
                            ? color.withOpacity(0.18)
                            : (band.contains('high') ? PP.dangerTint : band.contains('moderate') ? PP.warnTint : PP.safeTint);

                        return Dismissible(
                          key: Key('${p['id']}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(color: PP.dangerTint, borderRadius: PP.r16),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: Icon(Icons.delete_outline, color: PP.danger),
                          ),
                          onDismissed: (_) => _delete(p['id']),
                          child: GestureDetector(
                            onTap: () {
                              final ings = (p['ingredients'] ?? '').toString();
                              final dangerItems = ings.isNotEmpty 
                                ? ings.split(',').map((e) => {
                                    'name': e.trim(),
                                    'severity': 'MODERATE',
                                  }).toList()
                                : <Map<String, dynamic>>[];

                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ResultScreen(
                                  score: score, riskLevel: band,
                                  dangerItems: dangerItems, productName: p['name']
                                )));
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: PP.card(dark: isDark),
                              child: Row(children: [
                                Container(width: 48, height: 48,
                                  decoration: BoxDecoration(color: tint, borderRadius: PP.r12),
                                  child: Icon(Icons.spa_outlined, color: color, size: 22)),
                                const SizedBox(width: 14),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p['name'] ?? 'Unknown', style: PP.heading(14, color: theme.colorScheme.onSurface),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 3),
                                  Text(p['saved_at'] != null
                                      ? _formatDate(p['saved_at'])
                                      : p['date'] ?? '', style: PP.label(11)),
                                ])),
                                SafetyBadge(level: band, score: score),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return iso; }
  }
}

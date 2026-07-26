import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import 'result_screen.dart';
import 'skin_result_screen.dart';

class HistoryScreen extends StatefulWidget {
  final bool isTab;
  const HistoryScreen({super.key, this.isTab = false});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  late Future<List<dynamic>> _productFuture;
  late Future<List<dynamic>> _skinFuture;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _productFuture = _loadHistory();
    _skinFuture = _loadSkinHistory();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<List<dynamic>> _loadHistory() async {
    await Future.delayed(const Duration(milliseconds: 300));
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getInt('user_id');
    if (uid == null) return [];
    return ApiService.getHistory(uid);
  }

  Future<List<dynamic>> _loadSkinHistory() async {
    await Future.delayed(const Duration(milliseconds: 500));
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getInt('user_id');
    if (uid == null) return [];
    return ApiService.getSkinHistory(uid);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Check if this screen is part of a bottom nav (no back button needed)
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.isTab ? null : GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF261A1F) : PP.roseTint, 
              borderRadius: PP.r8, 
              border: Border.all(color: isDark ? const Color(0xFF3D2A30) : PP.border),
            ),
            child: Icon(Icons.arrow_back_ios_new, size: 16, color: theme.colorScheme.onSurface),
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF261A1F) : PP.roseTint, 
              borderRadius: PP.r12,
            ),
            child: TabBar(
              controller: _tab,
              indicator: BoxDecoration(gradient: PP.roseGrad, borderRadius: PP.r10),
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? Colors.white38 : PP.muted,
              labelStyle: PP.label(13, weight: FontWeight.w600),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Product Scans'),
                Tab(text: 'Skin Analysis'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_ProductTab(future: _productFuture), _SkinTab(future: _skinFuture)],
      ),
    );
  }
}

class _ProductTab extends StatefulWidget {
  final Future<List<dynamic>> future;
  const _ProductTab({required this.future});
  @override
  State<_ProductTab> createState() => _ProductTabState();
}

class _ProductTabState extends State<_ProductTab> {
  late Future<List<dynamic>> _f;
  @override
  void initState() { super.initState(); _f = widget.future; }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        final prefs = await SharedPreferences.getInstance();
        final uid = prefs.getInt('user_id');
        if (uid != null) setState(() => _f = ApiService.getHistory(uid));
      },
      child: FutureBuilder<List<dynamic>>(
        future: _f,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return Center(child: CircularProgressIndicator(color: PP.rose, strokeWidth: 2));
          if (snap.hasError)
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.wifi_off_rounded, color: PP.muted, size: 48),
                    const SizedBox(height: 16),
                    Text('Could not load history', style: PP.heading(15, color: Theme.of(ctx).colorScheme.onSurface)),
                    const SizedBox(height: 8),
                    Text(snap.error.toString().replaceAll('Exception:', '').trim(),
                        style: PP.body(12, color: PP.muted), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        final uid = prefs.getInt('user_id');
                        if (uid != null) setState(() => _f = ApiService.getHistory(uid));
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(backgroundColor: PP.rose, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: PP.pill)),
                    ),
                  ]),
                )),
              ),
            );
          if (!snap.hasData || snap.data!.isEmpty)
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: _Empty('No product scans yet', 'Scan a product to see your history here'),
              ),
            );
          final scans = snap.data!;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            itemCount: scans.length,
            itemBuilder: (_, i) {
              final s = scans[i];
              final score = (s['score'] ?? 0).toDouble();
              final band  = (s['risk_level'] ?? s['band'] ?? '').toString().toLowerCase();
              final color = band.contains('high') ? PP.danger : band.contains('moderate') ? PP.warn : PP.safe;
              final tint  = isDark
                  ? color.withOpacity(0.18)
                  : (band.contains('high') ? PP.dangerTint : band.contains('moderate') ? PP.warnTint : PP.safeTint);
              return GestureDetector(
                onTap: () {
                  final flagged = s['flagged_ingredients'] as List? ?? [];
                  final dangerItems = flagged.map<Map<String, dynamic>>((f) => {
                    'name': f.toString(),
                    'severity': 'CRITICAL',
                    'reason': 'Saved in your history.',
                  }).toList();

                  Navigator.push(ctx, MaterialPageRoute(builder: (_) => ResultScreen(
                    score: score, riskLevel: s['risk_level'] ?? s['band'] ?? '',
                    dangerItems: dangerItems, aiInsight: s['ai_analysis'] ?? '',
                    personalWarnings: s['personal_warnings'] ?? '',
                    productName: s['product_name'],
                    scanId: s['id'],
                  )));
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: PP.card(dark: isDark),
                  child: Row(children: [
                    Container(width: 48, height: 48,
                      decoration: BoxDecoration(color: tint, borderRadius: PP.r12),
                      child: Icon(Icons.inventory_2_outlined, color: color, size: 22)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        (s['product_name'] == null || s['product_name'].toString().isEmpty || s['product_name'] == 'Scanned Product' || s['product_name'] == 'Unknown Product')
                            ? 'Label Scan — ${s['date'] ?? ''}'
                            : s['product_name'].toString(),
                        style: PP.heading(14, color: theme.colorScheme.onSurface),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(s['date'] ?? '', style: PP.label(11)),
                    ])),
                    SafetyBadge(level: band, score: score),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SkinTab extends StatefulWidget {
  final Future<List<dynamic>> future;
  const _SkinTab({required this.future});
  @override
  State<_SkinTab> createState() => _SkinTabState();
}

class _SkinTabState extends State<_SkinTab> {
  late Future<List<dynamic>> _f;
  @override
  void initState() { super.initState(); _f = widget.future; }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        final prefs = await SharedPreferences.getInstance();
        final uid = prefs.getInt('user_id');
        if (uid != null) setState(() => _f = ApiService.getSkinHistory(uid));
      },
      child: FutureBuilder<List<dynamic>>(
        future: _f,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return Center(child: CircularProgressIndicator(color: PP.rose, strokeWidth: 2));
          if (snap.hasError)
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.wifi_off_rounded, color: PP.muted, size: 48),
                    const SizedBox(height: 16),
                    Text('Could not load skin history', style: PP.heading(15, color: Theme.of(ctx).colorScheme.onSurface)),
                    const SizedBox(height: 8),
                    Text(snap.error.toString().replaceAll('Exception:', '').trim(),
                        style: PP.body(12, color: PP.muted), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        final uid = prefs.getInt('user_id');
                        if (uid != null) setState(() => _f = ApiService.getSkinHistory(uid));
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(backgroundColor: PP.rose, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: PP.pill)),
                    ),
                  ]),
                )),
              ),
            );
          if (!snap.hasData || snap.data!.isEmpty)
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: _Empty('No skin analyses yet', 'Try the AI Skin Analysis feature'),
              ),
            );
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            itemCount: snap.data!.length,
            itemBuilder: (_, i) {
              final r = snap.data![i];
              return GestureDetector(
                onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => SkinResultScreen(result: Map<String, dynamic>.from(r)))),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: PP.card(dark: isDark),
                  child: Row(children: [
                    Container(width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: isDark ? PP.rose.withOpacity(0.15) : PP.roseTint,
                        borderRadius: PP.r12,
                      ),
                      child: Icon(Icons.face_retouching_natural, color: PP.rose, size: 24)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['skin_type'] ?? 'Analysis', style: PP.heading(14, color: theme.colorScheme.onSurface)),
                      if (r['skin_disorder'] != null && r['skin_disorder'].toString().isNotEmpty)
                        Text(r['skin_disorder'], style: PP.body(12, color: theme.colorScheme.onSurface.withOpacity(0.7))),
                      Text(r['date'] ?? '', style: PP.label(11)),
                    ])),
                    Icon(Icons.chevron_right, color: isDark ? Colors.white38 : PP.muted, size: 20),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String title, sub;
  const _Empty(this.title, this.sub);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 72, height: 72,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF261A1F) : PP.roseTint, 
            borderRadius: PP.r20,
          ),
          child: Icon(Icons.spa_outlined, color: PP.roseLt, size: 34)),
        const SizedBox(height: 16),
        Text(title, style: PP.heading(16, color: theme.colorScheme.onSurface)),
        const SizedBox(height: 6),
        Text(sub, style: PP.body(13, color: theme.colorScheme.onSurface.withOpacity(0.7)), textAlign: TextAlign.center),
      ]),
    ));
  }
}

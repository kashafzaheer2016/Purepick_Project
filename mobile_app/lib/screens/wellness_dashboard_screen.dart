import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';

/// Wellness Dashboard — shows scan streak, safety overview, recent activity.
class WellnessDashboardScreen extends StatefulWidget {
  const WellnessDashboardScreen({super.key});
  @override
  State<WellnessDashboardScreen> createState() => _WellnessDashboardScreenState();
}

class _WellnessDashboardScreenState extends State<WellnessDashboardScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  late AnimationController _animCtrl;
  late Animation<double> _scoreAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _scoreAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _load();
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getInt('user_id') ?? 0;
      final data = await ApiService.getHomeStats(uid);
      if (mounted) {
        setState(() { _stats = data; _loading = false; });
        _animCtrl.forward();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: LuxAppBar(title: 'Wellness Dashboard'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PP.rose))
          : RefreshIndicator(
              color: PP.rose,
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Column(children: [
                  _buildScoreRing(isDark),
                  const SizedBox(height: 24),
                  _buildStatsRow(isDark),
                  const SizedBox(height: 24),
                  _buildHealthProfile(isDark),
                  const SizedBox(height: 24),
                  _buildScanTimeline(isDark),
                ]),
              ),
            ),
    );
  }

  Widget _buildScoreRing(bool isDark) {
    final score = (_stats?['avg_safety_score'] ?? 75) as int;
    
    // Streak can be int or Map depending on API version sync
    int currentStreak = 0;
    final streakData = _stats?['streak'];
    if (streakData is Map) {
      currentStreak = (streakData['current'] ?? 0) as int;
    } else if (streakData is int) {
      currentStreak = streakData;
    }

    final color = score >= 70 ? PP.safe : score >= 40 ? PP.warn : PP.danger;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark ? [const Color(0xFF1A1215), const Color(0xFF261418)] : [PP.roseTint, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? const Color(0xFF3D2A30) : PP.border),
        boxShadow: PP.softShadow,
      ),
      child: Column(children: [
        Text('Wellness Score', style: PP.heading(14, color: isDark ? Colors.white70 : PP.muted, weight: FontWeight.w600)),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: _scoreAnim,
          builder: (_, __) => SizedBox(
            width: 140, height: 140,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(child: CircularProgressIndicator(value: 1, strokeWidth: 10, color: color.withOpacity(0.12))),
              SizedBox.expand(child: CircularProgressIndicator(
                value: _scoreAnim.value * (score / 100),
                strokeWidth: 10, color: color, strokeCap: StrokeCap.round,
              )),
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  '${(_scoreAnim.value * score).toInt()}',
                  style: GoogleFonts.poppins(fontSize: 38, fontWeight: FontWeight.bold, color: isDark ? Colors.white : PP.ink),
                ),
                Text('/ 100', style: PP.label(12, color: PP.muted)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.local_fire_department, color: PP.gold, size: 18),
          const SizedBox(width: 6),
          Text('$currentStreak day streak', style: PP.heading(14, color: isDark ? Colors.white : PP.ink)),
        ]),
      ]),
    );
  }

  Widget _buildStatsRow(bool isDark) {
    final totalScans = (_stats?['total_scans'] ?? 0) as int;
    final safeProducts = (_stats?['safe_products'] ?? 0) as int;
    final flaggedProducts = (_stats?['flagged_products'] ?? 0) as int;

    return Row(children: [
      _StatTile(label: 'Total Scans', value: '$totalScans', icon: Icons.qr_code_scanner, color: PP.rose, isDark: isDark),
      const SizedBox(width: 12),
      _StatTile(label: 'Safe', value: '$safeProducts', icon: Icons.check_circle_outline, color: PP.safe, isDark: isDark),
      const SizedBox(width: 12),
      _StatTile(label: 'Flagged', value: '$flaggedProducts', icon: Icons.warning_amber_rounded, color: PP.danger, isDark: isDark),
    ]);
  }

  Widget _buildScanTimeline(bool isDark) {
    final recentScans = (_stats?['recent_scans'] as List?) ?? [];
    final safeCount    = ((_stats?['safe_products']   ?? 0) as num).toInt();
    final flaggedCount = ((_stats?['flagged_products'] ?? 0) as num).toInt();
    final totalScans   = ((_stats?['total_scans']      ?? 0) as num).toInt();
    final moderateCount = totalScans - safeCount - flaggedCount;

    final safePct    = totalScans > 0 ? safeCount    / totalScans : 0.0;
    final flaggedPct = totalScans > 0 ? flaggedCount / totalScans : 0.0;
    final modPct     = totalScans > 0 ? moderateCount.clamp(0, totalScans) / totalScans : 0.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Safety breakdown bars ─────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161213) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? const Color(0xFF3D2A30) : PP.border, width: 0.8),
          boxShadow: PP.softShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 4, height: 18,
                decoration: BoxDecoration(color: PP.rose, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text('Product Safety Overview', style: PP.heading(15, color: isDark ? Colors.white : PP.ink)),
          ]),
          const SizedBox(height: 16),
          _BarRow(label: 'Safe', count: safeCount, pct: safePct, color: PP.safe, anim: _scoreAnim),
          const SizedBox(height: 12),
          _BarRow(label: 'Moderate', count: moderateCount.clamp(0, totalScans), pct: modPct, color: PP.warn, anim: _scoreAnim),
          const SizedBox(height: 12),
          _BarRow(label: 'High Risk', count: flaggedCount, pct: flaggedPct, color: PP.danger, anim: _scoreAnim),
        ]),
      ),

      if (recentScans.isNotEmpty) ...[
        const SizedBox(height: 24),
        // ── Scan history timeline ─────────────────────────────────
        Text('Scan History', style: PP.heading(16, color: isDark ? Colors.white : PP.ink)),
        const SizedBox(height: 12),
        ...recentScans.take(5).toList().asMap().entries.map((entry) {
          final i    = entry.key;
          final scan = entry.value as Map;
          final name  = (scan['product_name'] ?? 'Unknown').toString();
          final risk  = (scan['risk_level'] ?? scan['band'] ?? 'moderate').toString().toLowerCase();
          final score = ((scan['safety_score'] ?? scan['score'] ?? 50) as num).toInt();
          final date  = (scan['date'] ?? '').toString();
          final riskColor = risk.contains('high') ? PP.danger : risk.contains('safe') ? PP.safe : PP.warn;
          final isLast = i == recentScans.take(5).length - 1;

          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Timeline line
              Column(children: [
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: riskColor, shape: BoxShape.circle)),
                if (!isLast)
                  Expanded(child: Container(width: 1.5,
                      color: isDark ? Colors.white12 : PP.border)),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161213) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: riskColor.withOpacity(0.2), width: 0.8),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: PP.heading(13, color: isDark ? Colors.white : PP.ink),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (date.isNotEmpty)
                        Text(date, style: PP.label(10, color: PP.muted)),
                    ])),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: riskColor.withOpacity(isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text('$score/100', style: PP.label(11, color: riskColor, weight: FontWeight.w700)),
                    ),
                  ]),
                ),
              ),
            ]),
          );
        }),
      ],
    ]);
  }

  Widget _buildHealthProfile(bool isDark) {
    final profile = _stats?['health_profile'];
    if (profile == null) return const SizedBox.shrink();
    
    final allergies = List<String>.from(profile['allergies'] ?? []);
    final conditions = List<String>.from(profile['skin_conditions'] ?? []);
    final custom = List<String>.from(profile['custom_concerns'] ?? []);
    final type = profile['skin_type'] ?? 'Normal';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161213) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PP.rose.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.shield_outlined, color: PP.rose, size: 20),
            const SizedBox(width: 10),
            Text('Health Profile Summary', style: PP.heading(15, color: isDark ? Colors.white : PP.ink)),
          ]),
          const SizedBox(height: 16),
          _ProfileRow(label: 'Skin Type', value: type),
          const Divider(height: 24),
          _ProfileList(label: 'Allergies', items: allergies),
          const SizedBox(height: 12),
          _ProfileList(label: 'Skin Conditions', items: conditions),
          if (custom.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ProfileList(label: 'Custom Concerns', items: custom),
          ],
        ],
      ),
    );
  }

}

class _BarRow extends StatelessWidget {
  final String label;
  final int count;
  final double pct;
  final Color color;
  final Animation<double> anim;
  const _BarRow({required this.label, required this.count, required this.pct, required this.color, required this.anim});

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(width: 72, child: Text(label, style: PP.label(11, color: PP.muted))),
    Expanded(child: AnimatedBuilder(
      animation: anim,
      builder: (_, __) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: anim.value * pct,
          minHeight: 8,
          backgroundColor: color.withOpacity(0.12),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    )),
    const SizedBox(width: 8),
    SizedBox(width: 28, child: Text('$count', style: PP.heading(13, color: color), textAlign: TextAlign.right)),
  ]);
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool isDark;
  const _StatTile({required this.label, required this.value, required this.icon, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161213) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: PP.softShadow,
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : PP.ink)),
        const SizedBox(height: 2),
        Text(label, style: PP.label(11, color: PP.muted), textAlign: TextAlign.center),
      ]),
    ),
  );
}

class _ProfileRow extends StatelessWidget {
  final String label, value;
  const _ProfileRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: PP.body(13, color: PP.muted)),
      Text(value, style: PP.heading(14, color: Theme.of(context).colorScheme.onSurface)),
    ],
  );
}

class _ProfileList extends StatelessWidget {
  final String label;
  final List<String> items;
  const _ProfileList({required this.label, required this.items});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: PP.label(10, color: PP.muted, weight: FontWeight.w700)),
      const SizedBox(height: 6),
      if (items.isEmpty)
        Text('None saved', style: PP.body(12, color: PP.muted.withOpacity(0.5)))
      else
        Wrap(
          spacing: 6, runSpacing: 6,
          children: items.map((i) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: PP.rose.withOpacity(0.1),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(i, style: PP.label(10, color: PP.rose, weight: FontWeight.w600)),
          )).toList(),
        ),
    ],
  );
}

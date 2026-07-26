import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import '../services/task_poller.dart';

class IngredientCompareScreen extends StatefulWidget {
  const IngredientCompareScreen({super.key});
  @override
  State<IngredientCompareScreen> createState() => _IngredientCompareScreenState();
}

class _IngredientCompareScreenState extends State<IngredientCompareScreen> {
  final _ctrl1  = TextEditingController();
  final _ctrl2  = TextEditingController();
  final _name1  = TextEditingController(text: 'Product A');
  final _name2  = TextEditingController(text: 'Product B');

  Map<String, dynamic>? _r1, _r2;
  bool _loading = false;

  // User profile
  List<String> _userAllergies   = [];
  String       _userSkinType    = '';
  List<String> _userConditions  = [];
  String       _userName        = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _ctrl1.dispose(); _ctrl2.dispose();
    _name1.dispose(); _name2.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid   = prefs.getInt('user_id');
      final name  = prefs.getString('user_name') ?? '';
      if (uid == null) return;
      final data  = await ApiService.getProfile(uid);
      setState(() {
        _userAllergies  = List<String>.from(data['allergies'] ?? []);
        _userSkinType   = (data['skin_type'] ?? '').toString();
        _userConditions = List<String>.from(data['skin_conditions'] ?? []);
        _userName       = name;
      });
    } catch (_) {}
  }

  List<String> _parse(String raw) => raw
      .split(RegExp(r'[,\n;]'))
      .map((e) => e.trim())
      .where((e) => e.length > 1)
      .toList();

  Future<void> _compare() async {
    final t1 = _ctrl1.text.trim();
    final t2 = _ctrl2.text.trim();
    if (t1.isEmpty || t2.isEmpty) {
      _snack('Please enter ingredients for both products.'); return;
    }
    final list1 = _parse(t1);
    final list2 = _parse(t2);
    if (list1.length < 2 || list2.length < 2) {
      _snack('Please enter at least 2 ingredients per product for a meaningful comparison.'); return;
    }

    setState(() { _loading = true; _r1 = null; _r2 = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid   = prefs.getInt('user_id') ?? 0;
      final futures = await Future.wait([
        ApiService.analyzeIngredients(list1, uid),
        ApiService.analyzeIngredients(list2, uid),
      ]);
      final t1id = futures[0]['task_id'] as String?;
      final t2id = futures[1]['task_id'] as String?;
      final results = await Future.wait([
        t1id != null ? TaskPoller.poll(t1id) : Future.value(futures[0]),
        t2id != null ? TaskPoller.poll(t2id) : Future.value(futures[1]),
      ]);
      if (mounted) setState(() { _r1 = results[0]; _r2 = results[1]; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); _snack('$e'); }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: PP.body(13, color: Colors.white)),
      backgroundColor: PP.warn,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: PP.r12),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: LuxAppBar(title: 'Compare Products'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(children: [

          // ── Profile badge ─────────────────────────────────────────────
          if (_userSkinType.isNotEmpty)
            _ProfileBadge(
              name: _userName,
              skinType: _userSkinType,
              allergies: _userAllergies,
              conditions: _userConditions,
              isDark: isDark,
            ),
          const SizedBox(height: 16),

          // ── Info banner ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? PP.rose.withOpacity(0.1) : PP.roseTint,
              borderRadius: PP.r12,
              border: Border.all(color: PP.rose.withOpacity(0.2)),
            ),
            child: Row(children: [
              Icon(Icons.compare_arrows_rounded, color: PP.rose, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'Paste full ingredient lists. We\'ll compare safety for your specific skin type, allergies and conditions.',
                style: PP.body(12, color: isDark ? PP.roseLt : PP.rose),
              )),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Input cards ───────────────────────────────────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _InputCard(ctrl: _ctrl1, nameCtrl: _name1, label: 'Product A', accent: PP.safe, isDark: isDark)),
            const SizedBox(width: 12),
            Expanded(child: _InputCard(ctrl: _ctrl2, nameCtrl: _name2, label: 'Product B', accent: const Color(0xFF0277BD), isDark: isDark)),
          ]),
          const SizedBox(height: 20),

          SizedBox(width: double.infinity, child: LuxButton(
            label: _loading ? 'Analysing...' : 'Compare Products',
            icon: _loading ? null : Icons.compare_arrows_rounded,
            onPressed: _loading ? null : _compare,
            isLoading: _loading,
          )),

          if (_loading) ...[
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: PP.rose),
            const SizedBox(height: 12),
            Text('Comparing for your skin profile...', style: PP.body(13, color: PP.muted), textAlign: TextAlign.center),
          ],

          // ── Results ───────────────────────────────────────────────────
          if (_r1 != null && _r2 != null) ...[
            const SizedBox(height: 28),
            _WinnerCard(
              r1: _r1!, r2: _r2!,
              name1: _name1.text.trim().isEmpty ? 'Product A' : _name1.text.trim(),
              name2: _name2.text.trim().isEmpty ? 'Product B' : _name2.text.trim(),
              skinType: _userSkinType,
              allergies: _userAllergies,
              conditions: _userConditions,
              isDark: isDark,
            ),
            const SizedBox(height: 16),

            // Profile-specific insights
            if (_userAllergies.isNotEmpty || _userSkinType.isNotEmpty)
              _ProfileInsights(
                r1: _r1!, r2: _r2!,
                name1: _name1.text.trim().isEmpty ? 'Product A' : _name1.text.trim(),
                name2: _name2.text.trim().isEmpty ? 'Product B' : _name2.text.trim(),
                allergies: _userAllergies,
                skinType: _userSkinType,
                conditions: _userConditions,
                isDark: isDark,
              ),
            const SizedBox(height: 16),

            // Side by side detail
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _DetailCard(
                label: _name1.text.trim().isEmpty ? 'Product A' : _name1.text.trim(),
                result: _r1!, accent: PP.safe,
                userAllergies: _userAllergies,
                isDark: isDark,
              )),
              const SizedBox(width: 12),
              Expanded(child: _DetailCard(
                label: _name2.text.trim().isEmpty ? 'Product B' : _name2.text.trim(),
                result: _r2!, accent: const Color(0xFF0277BD),
                userAllergies: _userAllergies,
                isDark: isDark,
              )),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ── Profile Badge ─────────────────────────────────────────────────────────────
class _ProfileBadge extends StatelessWidget {
  final String name, skinType;
  final List<String> allergies, conditions;
  final bool isDark;
  const _ProfileBadge({required this.name, required this.skinType, required this.allergies, required this.conditions, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(colors: [PP.rose.withOpacity(0.15), PP.gold.withOpacity(0.08)])
            : LinearGradient(colors: [PP.roseTint, PP.goldTint]),
        borderRadius: PP.r12,
        border: Border.all(color: PP.rose.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(gradient: PP.roseGrad, shape: BoxShape.circle),
          child: const Icon(Icons.person, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Comparing for ${name.isNotEmpty ? name : 'you'}',
              style: PP.heading(13, color: isDark ? Colors.white : PP.ink)),
          const SizedBox(height: 2),
          Wrap(spacing: 6, children: [
            _MiniPill(skinType, PP.rose),
            if (allergies.isNotEmpty) _MiniPill('${allergies.length} allergens', PP.warn),
            if (conditions.isNotEmpty) _MiniPill(conditions.first, PP.muted),
          ]),
        ])),
      ]),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniPill(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: PP.pill,
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label, style: PP.label(10, color: color, weight: FontWeight.w600)),
  );
}

// ── Input Card ────────────────────────────────────────────────────────────────
class _InputCard extends StatelessWidget {
  final TextEditingController ctrl, nameCtrl;
  final String label;
  final Color accent;
  final bool isDark;
  const _InputCard({required this.ctrl, required this.nameCtrl, required this.label, required this.accent, required this.isDark});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: PP.heading(12, color: accent)),
    ]),
    const SizedBox(height: 6),
    TextField(
      controller: nameCtrl,
      style: PP.heading(13, color: isDark ? Colors.white : PP.ink),
      decoration: InputDecoration(
        hintText: label, hintStyle: PP.body(12, color: PP.muted),
        border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true,
      ),
    ),
    const SizedBox(height: 6),
    Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1418) : Colors.white,
        borderRadius: PP.r12,
        border: Border.all(color: accent.withOpacity(0.3)),
        boxShadow: PP.softShadow,
      ),
      child: TextField(
        controller: ctrl, maxLines: 8,
        style: PP.body(11, color: isDark ? Colors.white : PP.ink),
        decoration: InputDecoration(
          hintText: 'Water, Glycerin,\nNiacinamide...',
          hintStyle: PP.body(11, color: PP.muted),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    ),
  ]);
}

// ── Winner Card ───────────────────────────────────────────────────────────────
class _WinnerCard extends StatelessWidget {
  final Map<String, dynamic> r1, r2;
  final String name1, name2, skinType;
  final List<String> allergies, conditions;
  final bool isDark;
  const _WinnerCard({required this.r1, required this.r2, required this.name1, required this.name2,
      required this.skinType, required this.allergies, required this.conditions, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final score1  = ((r1['overall_score'] ?? 50) as num).toInt();
    final score2  = ((r2['overall_score'] ?? 50) as num).toInt();
    final alerts1 = ((r1['allergy_result']?['total_alerts'] ?? 0) as num).toInt();
    final alerts2 = ((r2['allergy_result']?['total_alerts'] ?? 0) as num).toInt();
    final band1   = (r1['risk']?['risk_band'] ?? r1['allergy_result']?['overall_verdict'] ?? 'Safe').toString();
    final band2   = (r2['risk']?['risk_band'] ?? r2['allergy_result']?['overall_verdict'] ?? 'Safe').toString();
    final safe1   = ((r1['allergy_result']?['total_safe'] ?? 0) as num).toInt();
    final safe2   = ((r2['allergy_result']?['total_safe'] ?? 0) as num).toInt();

    // Count how many of user's allergens appear in each product
    final flagged1 = _countUserAllergens(r1);
    final flagged2 = _countUserAllergens(r2);

    // Decision logic: user allergen hits > total alerts > score > band
    bool isAWins;
    if (flagged1 != flagged2) {
      isAWins = flagged1 < flagged2;
    } else if (alerts1 != alerts2) {
      isAWins = alerts1 < alerts2;
    } else if (score1 != score2) {
      isAWins = score1 > score2;
    } else {
      final safeSet = {'Safe', 'Low Risk'};
      isAWins = safeSet.contains(band1) && !safeSet.contains(band2) ? true : false;
    }

    final isTie   = flagged1 == flagged2 && alerts1 == alerts2 && score1 == score2;
    final winName = isTie ? 'Tie' : (isAWins ? name1 : name2);
    final winScore= isAWins ? score1 : score2;
    final loseScore= isAWins ? score2 : score1;
    final winColor= isTie ? PP.gold : (isAWins ? PP.safe : const Color(0xFF0277BD));
    final wAlerts = isAWins ? alerts1 : alerts2;
    final lAlerts = isAWins ? alerts2 : alerts1;
    final wSafe   = isAWins ? safe1 : safe2;
    final wFlagged= isAWins ? flagged1 : flagged2;
    final lFlagged= isAWins ? flagged2 : flagged1;

    final reasons = <String>[];
    if (!isTie) {
      if (wFlagged < lFlagged && allergies.isNotEmpty) {
        reasons.add('Fewer of your personal allergens detected ($wFlagged vs $lFlagged).');
      }
      if (winScore > loseScore) reasons.add('Higher safety score ($winScore vs $loseScore / 100).');
      if (wAlerts < lAlerts) reasons.add('Fewer flagged concerns ($wAlerts vs $lAlerts).');
      else if (wAlerts == 0) reasons.add('No concerning ingredients detected.');
      if (wSafe > 0) reasons.add('$wSafe confirmed safe ingredient${wSafe != 1 ? 's' : ''}.');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isTie
              ? [PP.gold, PP.gold.withOpacity(0.7)]
              : [winColor, winColor.withOpacity(0.75)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: PP.r20,
        boxShadow: PP.glow(winColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isTie ? Icons.handshake_outlined : Icons.emoji_events_rounded,
              color: Colors.white, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isTie ? 'Both are equally safe for you' : '$winName is Better for You',
                style: PP.heading(18, color: Colors.white, weight: FontWeight.w700)),
            Text(isTie ? 'Score: $score1 vs $score2'
                : 'Score $winScore vs $loseScore / 100',
                style: PP.body(12, color: Colors.white70)),
          ])),
        ]),
        if (reasons.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: PP.r12,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Why?', style: PP.heading(13, color: Colors.white, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...reasons.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('✓  ', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  Expanded(child: Text(r, style: PP.body(12, color: Colors.white.withOpacity(0.92)))),
                ]),
              )),
            ]),
          ),
        ],
        if (!isTie && skinType.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: PP.r8,
            ),
            child: Row(children: [
              Icon(Icons.person_pin_outlined, color: Colors.white70, size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(
                'Recommendation for $skinType skin',
                style: PP.label(11, color: Colors.white70, weight: FontWeight.w600),
              )),
            ]),
          ),
        ],
      ]),
    );
  }

  int _countUserAllergens(Map<String, dynamic> result) {
    if (allergies.isEmpty) return 0;
    final alerts = (result['allergy_result']?['allergy_alerts'] as List?) ?? [];
    int count = 0;
    for (final alert in alerts) {
      final name = (alert['ingredient'] ?? alert['common_name'] ?? '').toString().toLowerCase();
      for (final a in allergies) {
        if (name.contains(a.toLowerCase()) || a.toLowerCase().contains(name)) {
          count++;
          break;
        }
      }
    }
    return count;
  }
}

// ── Profile Insights ──────────────────────────────────────────────────────────
class _ProfileInsights extends StatelessWidget {
  final Map<String, dynamic> r1, r2;
  final String name1, name2, skinType;
  final List<String> allergies, conditions;
  final bool isDark;
  const _ProfileInsights({required this.r1, required this.r2, required this.name1, required this.name2,
      required this.skinType, required this.allergies, required this.conditions, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final insights = <_Insight>[];

    // Check allergen hits per product
    if (allergies.isNotEmpty) {
      final h1 = _allergenHits(r1);
      final h2 = _allergenHits(r2);
      if (h1.isNotEmpty) {
        insights.add(_Insight(
          icon: Icons.warning_amber_rounded, color: PP.danger,
          title: 'Allergen Alert — $name1',
          body: 'Contains ingredients matching your allergies: ${h1.join(', ')}.',
        ));
      }
      if (h2.isNotEmpty) {
        insights.add(_Insight(
          icon: Icons.warning_amber_rounded, color: PP.danger,
          title: 'Allergen Alert — $name2',
          body: 'Contains ingredients matching your allergies: ${h2.join(', ')}.',
        ));
      }
      if (h1.isEmpty && h2.isEmpty) {
        insights.add(_Insight(
          icon: Icons.check_circle_outline, color: PP.safe,
          title: 'Allergen Safe',
          body: 'Neither product contains your flagged allergens.',
        ));
      }
    }

    // Skin type specific tip
    if (skinType.isNotEmpty) {
      final tip = _skinTip(skinType, r1, r2, name1, name2);
      if (tip != null) insights.add(tip);
    }

    if (insights.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1617) : PP.surface,
        borderRadius: PP.r16,
        border: Border.all(color: PP.rose.withOpacity(0.2)),
        boxShadow: PP.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(gradient: PP.roseGrad, borderRadius: PP.r8),
            child: const Icon(Icons.person_search_outlined, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 10),
          Text('For Your Profile', style: PP.heading(14, color: PP.rose)),
        ]),
        const SizedBox(height: 14),
        ...insights.map((i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: i.color.withOpacity(isDark ? 0.2 : 0.1),
                borderRadius: PP.r8,
              ),
              child: Icon(i.icon, color: i.color, size: 14),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title, style: PP.heading(12, color: i.color)),
              const SizedBox(height: 2),
              Text(i.body, style: PP.body(12, color: isDark ? Colors.white60 : PP.muted)),
            ])),
          ]),
        )),
      ]),
    );
  }

  List<String> _allergenHits(Map<String, dynamic> result) {
    final alerts = (result['allergy_result']?['allergy_alerts'] as List?) ?? [];
    final hits   = <String>[];
    for (final alert in alerts) {
      final name = (alert['ingredient'] ?? alert['common_name'] ?? '').toString();
      for (final a in allergies) {
        if (name.toLowerCase().contains(a.toLowerCase()) || a.toLowerCase().contains(name.toLowerCase())) {
          hits.add(name);
          break;
        }
      }
    }
    return hits;
  }

  _Insight? _skinTip(String skin, Map<String, dynamic> r1, Map<String, dynamic> r2, String n1, String n2) {
    final s1 = ((r1['overall_score'] ?? 50) as num).toInt();
    final s2 = ((r2['overall_score'] ?? 50) as num).toInt();
    final better = s1 >= s2 ? n1 : n2;
    switch (skin.toLowerCase()) {
      case 'oily':
        return _Insight(icon: Icons.water_drop_outlined, color: PP.warn,
          title: 'Oily Skin Tip',
          body: 'Look for "non-comedogenic" and "oil-free" labels. $better scores better overall for oily skin types.');
      case 'dry':
        return _Insight(icon: Icons.opacity, color: const Color(0xFF0277BD),
          title: 'Dry Skin Tip',
          body: 'Prioritise products with ceramides, hyaluronic acid, and glycerin. $better may suit your dry skin better.');
      case 'sensitive':
        return _Insight(icon: Icons.favorite_border, color: PP.rose,
          title: 'Sensitive Skin Tip',
          body: 'Avoid fragrance and alcohol-based formulas. $better has a higher safety score for sensitive skin.');
      case 'combination':
        return _Insight(icon: Icons.balance, color: PP.gold,
          title: 'Combination Skin Tip',
          body: 'Choose balanced, lightweight formulas. $better is the safer choice based on your profile.');
      default: return null;
    }
  }
}

class _Insight {
  final IconData icon;
  final Color color;
  final String title, body;
  const _Insight({required this.icon, required this.color, required this.title, required this.body});
}

// ── Detail Card ───────────────────────────────────────────────────────────────
class _DetailCard extends StatefulWidget {
  final String label;
  final Map<String, dynamic> result;
  final Color accent;
  final List<String> userAllergies;
  final bool isDark;
  const _DetailCard({required this.label, required this.result, required this.accent, required this.userAllergies, required this.isDark});
  @override
  State<_DetailCard> createState() => _DetailCardState();
}

class _DetailCardState extends State<_DetailCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final score   = ((widget.result['overall_score'] ?? 50) as num).toInt();
    final alerts  = (widget.result['allergy_result']?['allergy_alerts'] as List?) ?? [];
    final safe    = ((widget.result['allergy_result']?['total_safe'] ?? 0) as num).toInt();
    final band    = (widget.result['risk']?['risk_band'] ?? widget.result['allergy_result']?['overall_verdict'] ?? 'Safe').toString();
    final bandColor = band.contains('High') ? PP.danger : band.contains('Moderate') ? PP.warn : PP.safe;

    // Count allergen hits for user
    int userHits = 0;
    for (final alert in alerts) {
      final name = (alert['ingredient'] ?? alert['common_name'] ?? '').toString().toLowerCase();
      for (final a in widget.userAllergies) {
        if (name.contains(a.toLowerCase())) { userHits++; break; }
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1E1418) : Colors.white,
        borderRadius: PP.r16,
        border: Border.all(color: widget.accent.withOpacity(0.25)),
        boxShadow: PP.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.accent, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(child: Text(widget.label,
              style: PP.heading(13, color: widget.accent),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 12),
        Center(child: SizedBox(width: 68, height: 68,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(child: CircularProgressIndicator(value: 1, strokeWidth: 6, color: widget.accent.withOpacity(0.12))),
            SizedBox.expand(child: CircularProgressIndicator(
                value: score / 100, strokeWidth: 6, color: widget.accent, strokeCap: StrokeCap.round)),
            Text('$score', style: PP.heading(20, color: widget.isDark ? Colors.white : PP.ink, weight: FontWeight.w700)),
          ]),
        )),
        const SizedBox(height: 6),
        Center(child: Text('Safety Score', style: PP.label(10, color: PP.muted))),
        const SizedBox(height: 10),
        Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bandColor.withOpacity(widget.isDark ? 0.2 : 0.1),
            borderRadius: PP.pill,
            border: Border.all(color: bandColor.withOpacity(0.4)),
          ),
          child: Text(band, style: PP.label(10, color: bandColor, weight: FontWeight.w700)),
        )),
        const SizedBox(height: 10),
        _StatRow(Icons.check_circle_outline, '$safe safe', PP.safe, widget.isDark),
        const SizedBox(height: 4),
        _StatRow(Icons.warning_amber_rounded,
            '${alerts.length} concern${alerts.length != 1 ? 's' : ''}',
            alerts.isEmpty ? PP.safe : PP.danger, widget.isDark),
        if (userHits > 0) ...[
          const SizedBox(height: 4),
          _StatRow(Icons.person_off_outlined,
              '$userHits your allergen${userHits != 1 ? 's' : ''}',
              PP.danger, widget.isDark),
        ],
        if (alerts.isNotEmpty) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(children: [
              Expanded(child: Text('View concerns', style: PP.body(11, color: PP.rose, weight: FontWeight.w600))),
              Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: PP.rose, size: 16),
            ]),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            ...alerts.take(5).map((a) {
              final name = (a['common_name'] ?? a['ingredient'] ?? '').toString();
              final isUserAllergen = widget.userAllergies.any((ua) =>
                  name.toLowerCase().contains(ua.toLowerCase()));
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isUserAllergen ? PP.danger : PP.dangerTint).withOpacity(widget.isDark ? 0.15 : 1),
                    borderRadius: PP.r8,
                    border: Border.all(color: (isUserAllergen ? PP.danger : PP.danger).withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    if (isUserAllergen) ...[
                      const Icon(Icons.person_off_outlined, color: PP.danger, size: 12),
                      const SizedBox(width: 4),
                    ],
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: PP.heading(11, color: PP.danger)),
                      if ((a['plain_explanation'] ?? '').toString().isNotEmpty)
                        Text(a['plain_explanation'].toString(),
                            style: PP.body(10, color: widget.isDark ? Colors.white70 : PP.muted),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                    ])),
                  ]),
                ),
              );
            }),
            if (alerts.length > 5)
              Text('+${alerts.length - 5} more', style: PP.label(10, color: PP.muted)),
          ],
        ],
      ]),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  const _StatRow(this.icon, this.label, this.color, this.isDark);
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 13, color: color),
    const SizedBox(width: 5),
    Text(label, style: PP.label(11, color: color)),
  ]);
}

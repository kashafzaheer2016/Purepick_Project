import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../design/pp.dart';

// ═══════════════════════════════════════════════════════════
// SKIN RESULT SCREEN — Premium Animated UI
// ═══════════════════════════════════════════════════════════
class SkinResultScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  const SkinResultScreen({super.key, required this.result});
  @override
  State<SkinResultScreen> createState() => _SkinResultScreenState();
}

class _SkinResultScreenState extends State<SkinResultScreen>
    with TickerProviderStateMixin {
  late AnimationController _heroCtrl;
  late AnimationController _cardsCtrl;
  late AnimationController _scoreCtrl;

  late Animation<double> _heroScale;
  late Animation<double> _heroFade;
  late Animation<double> _scoreFill;
  late List<Animation<Offset>> _cardSlides;
  late List<Animation<double>> _cardFades;

  @override
  void initState() {
    super.initState();

    _heroCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scoreCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _cardsCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

    _heroScale = Tween<double>(begin: 0.85, end: 1).animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutBack));
    _heroFade  = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut));
    _scoreFill = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _scoreCtrl, curve: Curves.easeOut));

    // Stagger 5 cards
    _cardSlides = List.generate(5, (i) => Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(
      CurvedAnimation(parent: _cardsCtrl, curve: Interval(i * 0.12, 0.6 + i * 0.08, curve: Curves.easeOutCubic)),
    ));
    _cardFades = List.generate(5, (i) => Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _cardsCtrl, curve: Interval(i * 0.12, 0.7 + i * 0.06, curve: Curves.easeOut)),
    ));

    // Sequence animations
    _heroCtrl.forward().then((_) {
      _scoreCtrl.forward();
      Future.delayed(const Duration(milliseconds: 300), () => _cardsCtrl.forward());
    });
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _cardsCtrl.dispose();
    _scoreCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final skinType      = widget.result['skin_type'] as String? ?? 'Unknown';
    final skinDisorder  = widget.result['skin_disorder'] as String?;
    final typeConf      = ((widget.result['skin_type_confidence'] ?? 0) as num).toDouble();
    final dispConf      = ((widget.result['skin_disorder_confidence'] ?? 0) as num).toDouble();
    final recs          = Map<String, String>.from(widget.result['recommendations'] as Map? ?? {});
    final conditions    = (widget.result['skin_conditions'] as List? ?? []);
    final aiNotes       = widget.result['ai_notes'] as String? ?? '';
    final condRecs      = Map<String, dynamic>.from(widget.result['condition_recommendations'] as Map? ?? {});
    final analysisSource = widget.result['analysis_source'] as String? ?? '';

    final meta = _SkinMeta.of(skinType);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Gradient AppBar ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: meta.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: AnimatedBuilder(
                animation: Listenable.merge([_heroScale, _heroFade, _scoreFill]),
                builder: (_, __) => FadeTransition(
                  opacity: _heroFade,
                  child: ScaleTransition(
                    scale: _heroScale,
                    child: _HeroHeader(
                      skinType: skinType,
                      meta: meta,
                      confidence: typeConf,
                      scoreFill: _scoreFill.value,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // AI Notes card
                if (aiNotes.isNotEmpty)
                  _staggered(0, _AiNotesCard(notes: aiNotes, analysisSource: analysisSource)),

                // Detected conditions chips
                if (conditions.isNotEmpty)
                  _staggered(0, _ConditionsChips(conditions: conditions, meta: meta)),

                // Primary disorder card
                if (skinDisorder != null && skinDisorder.isNotEmpty)
                  _staggered(0, _DisorderCard(disorder: skinDisorder, confidence: dispConf, isDark: isDark)),

                const SizedBox(height: 8),

                // Condition-specific treatment cards
                if (condRecs.isNotEmpty) ...[
                  _staggered(1, Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Row(children: [
                      Container(width: 4, height: 22, decoration: BoxDecoration(color: Colors.deepPurple, borderRadius: BorderRadius.circular(4))),
                      const SizedBox(width: 10),
                      Text('Targeted Treatments', style: PP.heading(18, color: theme.colorScheme.onSurface)),
                    ]),
                  )),
                  ...condRecs.entries.toList().asMap().entries.map((entry) {
                    final condName = entry.value.key;
                    final condAdvice = Map<String, String>.from(entry.value.value as Map? ?? {});
                    return _staggered(1, _ConditionTreatmentCard(conditionName: condName, advice: condAdvice, isDark: isDark));
                  }),
                ],

                const SizedBox(height: 8),

                // Routine section header
                _staggered(1, Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 16),
                  child: Row(children: [
                    Container(width: 4, height: 22, decoration: BoxDecoration(color: meta.primary, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(width: 10),
                    Text('Your Skincare Routine', style: PP.heading(18, color: theme.colorScheme.onSurface)),
                  ]),
                )),

                // Routine cards
                ...recs.entries.toList().asMap().entries.map((entry) {
                  final idx  = entry.key + 2;
                  final step = entry.value.key;
                  final text = entry.value.value;
                  return _staggered(idx, _RoutineCard(step: step, advice: text, meta: meta, isDark: isDark));
                }),

                const SizedBox(height: 28),

                // Disclaimer
                _staggered(4, _DisclaimerCard()),

                const SizedBox(height: 24),

                // Action buttons
                _staggered(4, Column(children: [
                  _PrimaryButton(
                    label: 'Analyse Again',
                    icon: Icons.face_retouching_natural,
                    color: meta.primary,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: LuxButton(
                      label: 'Back to Home',
                      outlined: true,
                      onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                    ),
                  ),
                ])),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staggered(int idx, Widget child) {
    final i = idx.clamp(0, 4);
    return AnimatedBuilder(
      animation: _cardsCtrl,
      builder: (_, __) => FadeTransition(
        opacity: _cardFades[i],
        child: SlideTransition(position: _cardSlides[i], child: child),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════
// HERO HEADER — animated confidence ring + skin type
// ═══════════════════════════════════════════════════════════
class _HeroHeader extends StatelessWidget {
  final String skinType;
  final _SkinMeta meta;
  final double confidence;
  final double scoreFill;   // 0–1 animated

  const _HeroHeader({required this.skinType, required this.meta, required this.confidence, required this.scoreFill});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [meta.primary, meta.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            // Animated ring
            SizedBox(
              width: 120, height: 120,
              child: Stack(alignment: Alignment.center, children: [
                // BG ring
                SizedBox.expand(child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 8,
                  color: Colors.white12,
                )),
                // Filled ring
                SizedBox.expand(child: CircularProgressIndicator(
                  value: scoreFill * (confidence / 100),
                  strokeWidth: 8,
                  color: Colors.white,
                  strokeCap: StrokeCap.round,
                )),
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                    '${(scoreFill * confidence).toInt()}%',
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  Text('confidence', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10)),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(meta.icon, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text(skinType, 
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('Skin Type Detected', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════
// AI NOTES CARD — Gemini personalised observation
// ═══════════════════════════════════════════════════════════
class _AiNotesCard extends StatelessWidget {
  final String notes;
  final String analysisSource;
  const _AiNotesCard({required this.notes, required this.analysisSource});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1025) : const Color(0xFFF3EEFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurple.withOpacity(isDark ? 0.4 : 0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.12), shape: BoxShape.circle),
          child: const Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('AI Skin Observation', style: GoogleFonts.poppins(color: Colors.deepPurple, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const SizedBox(width: 8),
            if (analysisSource.contains('gemini'))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('Gemini Vision', style: GoogleFonts.poppins(fontSize: 9, color: Colors.deepPurple, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 6),
          Text(notes, style: GoogleFonts.poppins(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87, height: 1.5)),
        ])),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CONDITIONS CHIPS — all detected conditions
// ═══════════════════════════════════════════════════════════
class _ConditionsChips extends StatelessWidget {
  final List conditions;
  final _SkinMeta meta;
  const _ConditionsChips({required this.conditions, required this.meta});
  @override
  Widget build(BuildContext context) {
    if (conditions.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Detected Conditions', style: PP.label(11, color: PP.muted, weight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: conditions.map((c) {
            String name = '';
            if (c is Map) name = c['name'] ?? '';
            else name = c.toString();
            if (name.isEmpty) return const SizedBox.shrink();

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: meta.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: meta.primary.withOpacity(0.3)),
              ),
              child: Text(name, style: GoogleFonts.poppins(fontSize: 12, color: meta.primary, fontWeight: FontWeight.w500)),
            );
          }).toList(),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CONDITION TREATMENT CARD — targeted advice per condition
// ═══════════════════════════════════════════════════════════
class _ConditionTreatmentCard extends StatefulWidget {
  final String conditionName;
  final Map<String, String> advice;
  final bool isDark;
  const _ConditionTreatmentCard({required this.conditionName, required this.advice, required this.isDark});
  @override
  State<_ConditionTreatmentCard> createState() => _ConditionTreatmentCardState();
}
class _ConditionTreatmentCardState extends State<_ConditionTreatmentCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1A1025) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _expanded ? Colors.deepPurple.withOpacity(0.4) : Colors.deepPurple.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: Colors.deepPurple.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.medical_services_outlined, color: Colors.deepPurple, size: 18)),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.conditionName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: widget.isDark ? Colors.white : const Color(0xFF1A1F2E)))),
              AnimatedRotation(turns: _expanded ? 0.5 : 0, duration: const Duration(milliseconds: 250),
                child: Icon(Icons.expand_more_rounded, color: Colors.grey[400])),
            ]),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.advice.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.key, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.deepPurple, letterSpacing: 0.3)),
                    const SizedBox(height: 2),
                    Text(e.value, style: GoogleFonts.poppins(fontSize: 12, color: widget.isDark ? Colors.white60 : Colors.black54, height: 1.5)),
                  ]),
                )).toList(),
              ),
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 280),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// DISORDER CARD
// ═══════════════════════════════════════════════════════════
class _DisorderCard extends StatelessWidget {
  final String disorder;
  final double confidence;
  final bool isDark;
  const _DisorderCard({required this.disorder, required this.confidence, required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF1A1208) : const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFFFB74D).withOpacity(isDark ? 0.3 : 0.5)),
      boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFF6F00).withOpacity(0.1), shape: BoxShape.circle),
        child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6F00), size: 24),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Primary Condition', style: GoogleFonts.poppins(color: const Color(0xFFFF6F00), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(disorder, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : const Color(0xFF1A1F2E))),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: confidence / 100,
            minHeight: 4,
            backgroundColor: Colors.orange.withOpacity(0.15),
            valueColor: const AlwaysStoppedAnimation(Color(0xFFFF6F00)),
          ),
        ),
        const SizedBox(height: 3),
        Text('${confidence.toStringAsFixed(1)}% confidence', style: GoogleFonts.poppins(fontSize: 10, color: Colors.orange[isDark ? 300 : 700])),
      ])),
    ]),
  );
}


// ═══════════════════════════════════════════════════════════
// ROUTINE CARD
// ═══════════════════════════════════════════════════════════
class _RoutineCard extends StatefulWidget {
  final String step;
  final String advice;
  final _SkinMeta meta;
  final bool isDark;
  const _RoutineCard({required this.step, required this.advice, required this.meta, required this.isDark});
  @override
  State<_RoutineCard> createState() => _RoutineCardState();
}

class _RoutineCardState extends State<_RoutineCard> {
  bool _expanded = false;

  static const _stepIcons = {
    'Cleansing':       Icons.water_drop_outlined,
    'Exfoliation':     Icons.auto_fix_high,
    'Moisturizing':    Icons.opacity,
    'Lifestyle':       Icons.favorite_border,
    'Sun Protection':  Icons.wb_sunny_outlined,
  };
  static const _stepColors = {
    'Cleansing':       Color(0xFF29B6F6),
    'Exfoliation':     Color(0xFFAB47BC),
    'Moisturizing':    Color(0xFF66BB6A),
    'Lifestyle':       Color(0xFFEF5350),
    'Sun Protection':  Color(0xFFF9A825),
  };

  @override
  Widget build(BuildContext context) {
    final icon  = _stepIcons[widget.step]  ?? Icons.check_circle_outline;
    final color = _stepColors[widget.step] ?? widget.meta.primary;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1A1215) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _expanded ? color.withOpacity(0.4) : (widget.isDark ? Colors.white10 : Colors.transparent)),
          boxShadow: [
            BoxShadow(
              color: _expanded ? color.withOpacity(0.12) : Colors.grey.withOpacity(widget.isDark ? 0.02 : 0.06),
              blurRadius: _expanded ? 20 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.step, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15, color: widget.isDark ? Colors.white : const Color(0xFF1A1F2E)))),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 280),
              child: Icon(Icons.expand_more_rounded, color: Colors.grey[widget.isDark ? 300 : 400]),
            ),
          ]),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12, left: 2),
              child: Text(widget.advice, style: GoogleFonts.poppins(fontSize: 13, color: widget.isDark ? Colors.white54 : Colors.black54, height: 1.6)),
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 280),
          ),
        ]),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════
// DISCLAIMER CARD
// ═══════════════════════════════════════════════════════════
class _DisclaimerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1A2E) : Colors.blue[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.withOpacity(isDark ? 0.3 : 0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, color: isDark ? Colors.blue[300] : Colors.blue, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(
          'This analysis is powered by AI and is for informational purposes only. AI accuracy varies — always consult a certified dermatologist for a clinical diagnosis.',
          style: GoogleFonts.poppins(fontSize: 11, color: isDark ? Colors.blue[300] : Colors.blue[700], height: 1.5),
        )),
      ]),
    );
  }
}


// ═══════════════════════════════════════════════════════════
// ACTION BUTTONS
// ═══════════════════════════════════════════════════════════
class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity, height: 56,
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 6,
        shadowColor: color.withOpacity(0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: Icon(icon, size: 22),
      label: Text(label, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
      onPressed: onTap,
    ),
  );
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity, height: 52,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.grey[300]!),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onTap,
      child: Text(label, style: GoogleFonts.poppins(fontSize: 15, color: Colors.black54, fontWeight: FontWeight.w500)),
    ),
  );
}


// ═══════════════════════════════════════════════════════════
// SKIN META — color + icon per skin type
// ═══════════════════════════════════════════════════════════
class _SkinMeta {
  final Color primary;
  final Color secondary;
  final IconData icon;
  const _SkinMeta({required this.primary, required this.secondary, required this.icon});

  static _SkinMeta of(String type) {
    switch (type.toLowerCase()) {
      case 'oily':
      case 'oily skin':
        return const _SkinMeta(primary: Color(0xFF2E7D32), secondary: Color(0xFF66BB6A), icon: Icons.water_drop);
      case 'dry':
      case 'dry skin':
        return const _SkinMeta(primary: Color(0xFFBF360C), secondary: Color(0xFFFF7043), icon: Icons.thermostat_outlined);
      case 'sensitive':
      case 'sensitive skin':
        return const _SkinMeta(primary: Color(0xFF6A1B9A), secondary: Color(0xFFAB47BC), icon: Icons.spa_outlined);
      case 'combination':
      case 'combination skin':
        return const _SkinMeta(primary: Color(0xFF0277BD), secondary: Color(0xFF29B6F6), icon: Icons.join_full_outlined);
      case 'normal':
      case 'normal skin':
        return const _SkinMeta(primary: Color(0xFF00695C), secondary: Color(0xFF26A69A), icon: Icons.check_circle_outline);
      default:
        return const _SkinMeta(primary: Color(0xFF558B2F), secondary: Color(0xFF9DC183), icon: Icons.face_retouching_natural);
    }
  }
}

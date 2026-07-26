import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/pp.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../app_router.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen>
    with TickerProviderStateMixin {
  int _step = 0;
  bool _loading = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  // Step 1 — basics
  final _ageCtrl = TextEditingController(text: '22');
  String _gender = 'Female';
  String _skinType = 'Combination';

  // Step 2 — allergies
  final _allergyCtrl = TextEditingController();
  List<String> _allergies = [];

  // Step 3 — conditions
  List<String> _conditions = [];

  static const _genders   = ['Female', 'Male', 'Other'];
  static const _skinTypes = ['Normal', 'Dry', 'Oily', 'Combination', 'Sensitive'];
  static const _commonAllergies = [
    'Fragrance', 'Parabens', 'Sulfates', 'Alcohol',
    'Gluten', 'Nuts', 'Dairy', 'Soy',
  ];
  static const _commonConditions = [
    'Acne', 'Eczema', 'Rosacea', 'Psoriasis',
    'Dermatitis', 'Hyperpigmentation', 'Sensitive Skin', 'None',
  ];

  // Step metadata
  static const _stepIcons   = [Icons.person_outline, Icons.warning_amber_outlined, Icons.healing_outlined];
  static const _stepTitles  = ['About You', 'Allergies', 'Skin Conditions'];
  static const _stepSubs    = [
    'Tell us about yourself so we can personalise your experience.',
    'Select anything your skin reacts to — we\'ll flag these in every scan.',
    'Select any skin concerns you have. We\'ll tailor recommendations for you.',
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _loadExisting();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _ageCtrl.dispose();
    _allergyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getInt('user_id');
      if (uid == null) return;
      final data = await ApiService.getProfile(uid);
      final loadedAllergies  = List<String>.from(data['allergies'] ?? []);
      final loadedConditions = List<String>.from(data['skin_conditions'] ?? []);
      final savedSkin   = (data['skin_type'] ?? 'Normal').toString();
      final savedGender = (data['gender'] ?? 'Female').toString();
      final savedAge    = data['age'];
      setState(() {
        _allergies  = loadedAllergies;
        _conditions = loadedConditions;
        if (savedAge != null) _ageCtrl.text = savedAge.toString();
        for (var s in _skinTypes) { if (s.toLowerCase() == savedSkin.toLowerCase()) { _skinType = s; break; } }
        for (var g in _genders)   { if (g.toLowerCase() == savedGender.toLowerCase()) { _gender = g; break; } }
      });
    } catch (_) {}
  }

  void _nextStep() {
    if (_step < 2) {
      _fadeCtrl.forward(from: 0);
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _prevStep() {
    if (_step > 0) {
      _fadeCtrl.forward(from: 0);
      setState(() => _step--);
    }
  }

  Future<void> _finish() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getInt('user_id');
      if (uid == null) throw Exception('Session lost.');
      final legacyAllergies = [..._allergies, 'Skin:$_skinType', 'Gender:$_gender'].join(',');
      await ApiService.updateProfile(
        uid, legacyAllergies,
        skinType: _skinType,
        gender: _gender,
        skinConditions: _conditions.join(','),
        age: int.tryParse(_ageCtrl.text.trim()),
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRouter.main, (r) => false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: PP.body(13, color: Colors.white)),
          backgroundColor: PP.danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: PP.r12),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0809) : PP.bg;

    return Scaffold(
      backgroundColor: bg,
      body: Column(children: [
        _Header(step: _step, isDark: isDark),
        Expanded(
          child: FadeTransition(
            opacity: _fade,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 28),
                _StepIndicator(step: _step, isDark: isDark),
                const SizedBox(height: 28),
                _SectionHeader(
                  icon: _stepIcons[_step],
                  title: _stepTitles[_step],
                  subtitle: _stepSubs[_step],
                  isDark: isDark,
                ),
                const SizedBox(height: 24),
                _buildStepContent(isDark),
                if (_step == 2) ...[
                  const SizedBox(height: 24),
                  _SummaryCard(
                    age: _ageCtrl.text, gender: _gender, skinType: _skinType,
                    allergies: _allergies, conditions: _conditions, isDark: isDark,
                  ),
                ],
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ),
        _NavBar(
          step: _step,
          loading: _loading,
          onBack: _step > 0 ? _prevStep : null,
          onNext: _nextStep,
          isDark: isDark,
        ),
      ]),
    );
  }

  Widget _buildStepContent(bool isDark) {
    switch (_step) {
      case 0: return _Step1(
        ageCtrl: _ageCtrl, gender: _gender, skinType: _skinType,
        genders: _genders, skinTypes: _skinTypes, isDark: isDark,
        onGender: (g) => setState(() => _gender = g),
        onSkinType: (s) => setState(() => _skinType = s),
      );
      case 1: return _Step2(
        selected: _allergies, common: _commonAllergies,
        ctrl: _allergyCtrl, isDark: isDark,
        onToggle: (a) => setState(() => _allergies.contains(a) ? _allergies.remove(a) : _allergies.add(a)),
        onAdd: (a) { if (a.isNotEmpty && !_allergies.contains(a)) setState(() { _allergies.add(a); _allergyCtrl.clear(); }); },
        onRemove: (a) => setState(() => _allergies.remove(a)),
      );
      case 2: return _Step3(
        selected: _conditions, common: _commonConditions, isDark: isDark,
        onToggle: (c) => setState(() => _conditions.contains(c) ? _conditions.remove(c) : _conditions.add(c)),
      );
      default: return const SizedBox.shrink();
    }
  }
}

// ── Header ────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final int step;
  final bool isDark;
  const _Header({required this.step, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFB07A8A), Color(0xFF8A5A6A), Color(0xFF6A3A50)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: PP.pill,
                ),
                child: Text('Step ${step + 1} of 3',
                    style: PP.label(12, color: Colors.white, weight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: PP.r8,
                ),
                child: Icon(Icons.spa_outlined, color: Colors.white, size: 18),
              ),
            ]),
            const SizedBox(height: 20),
            Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
              ),
              child: Icon(_icons[step], color: Colors.white, size: 32),
            ),
            const SizedBox(height: 14),
            Text('Create Your Profile',
                style: PP.display(22, color: Colors.white, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Personalised skincare starts here',
                style: PP.body(13, color: Colors.white70)),
            // Progress bar
            const SizedBox(height: 18),
            Row(children: List.generate(3, (i) => Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                decoration: BoxDecoration(
                  color: i <= step ? Colors.white : Colors.white.withOpacity(0.3),
                  borderRadius: PP.pill,
                ),
              ),
            ))),
          ]),
        ),
      ),
    );
  }

  static const _icons = [Icons.person_outline, Icons.warning_amber_outlined, Icons.healing_outlined];
}

// ── Step Indicator ────────────────────────────────────────────────────────────
class _StepIndicator extends StatelessWidget {
  final int step;
  final bool isDark;
  const _StepIndicator({required this.step, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(children: List.generate(3, (i) {
      final done   = i < step;
      final active = i == step;
      return Expanded(child: Row(children: [
        Expanded(child: Column(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: active ? PP.roseGrad : null,
              color: done ? PP.rose.withOpacity(0.2)
                  : (isDark ? const Color(0xFF261418) : PP.border),
              border: active ? null : Border.all(
                color: done ? PP.rose.withOpacity(0.5) : (isDark ? Colors.white12 : PP.border),
              ),
            ),
            child: Center(
              child: done
                  ? const Icon(Icons.check, color: PP.rose, size: 16)
                  : Text('${i + 1}', style: PP.heading(13,
                      color: active ? Colors.white : (isDark ? Colors.white38 : PP.muted))),
            ),
          ),
          const SizedBox(height: 4),
          Text(['About', 'Allergies', 'Conditions'][i],
              style: PP.label(9,
                  color: active ? PP.rose : (isDark ? Colors.white38 : PP.muted),
                  weight: active ? FontWeight.w700 : FontWeight.w500)),
        ])),
        if (i < 2) Container(
          height: 1.5, width: 24,
          color: i < step ? PP.rose.withOpacity(0.4) : (isDark ? Colors.white12 : PP.border),
        ),
      ]));
    }));
  }
}

// ── Section Header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool isDark;
  const _SectionHeader({required this.icon, required this.title, required this.subtitle, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: PP.roseTint,
          borderRadius: PP.r12,
          border: Border.all(color: PP.rose.withOpacity(0.2)),
        ),
        child: Icon(icon, color: PP.rose, size: 20),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: PP.heading(18, color: isDark ? Colors.white : PP.ink)),
        const SizedBox(height: 4),
        Text(subtitle, style: PP.body(13, color: isDark ? Colors.white60 : PP.muted)),
      ])),
    ]);
  }
}

// ── Step 1: About You ─────────────────────────────────────────────────────────
class _Step1 extends StatelessWidget {
  final TextEditingController ageCtrl;
  final String gender, skinType;
  final List<String> genders, skinTypes;
  final bool isDark;
  final ValueChanged<String> onGender, onSkinType;

  const _Step1({
    required this.ageCtrl, required this.gender, required this.skinType,
    required this.genders, required this.skinTypes, required this.isDark,
    required this.onGender, required this.onSkinType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _FieldLabel('Age', Icons.cake_outlined, isDark),
      const SizedBox(height: 10),
      TextField(
        controller: ageCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: PP.body(15, color: isDark ? Colors.white : PP.ink),
        decoration: PP.input('Your age', icon: Icons.cake_outlined).copyWith(
          fillColor: isDark ? const Color(0xFF1A1617) : PP.roseTint,
          hintText: 'e.g. 24',
        ),
      ),
      const SizedBox(height: 24),
      _FieldLabel('Gender', Icons.people_outline, isDark),
      const SizedBox(height: 10),
      Row(children: genders.map((g) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: g != genders.last ? 10 : 0),
          child: _Chip(
            label: g,
            selected: gender == g,
            onTap: () => onGender(g),
            isDark: isDark,
            icon: g == 'Female' ? Icons.female : g == 'Male' ? Icons.male : Icons.person,
          ),
        ),
      )).toList()),
      const SizedBox(height: 24),
      _FieldLabel('Skin Type *', Icons.water_drop_outlined, isDark),
      const SizedBox(height: 4),
      Text('Helps us flag ingredients suited or harmful for your skin type.',
          style: PP.body(12, color: isDark ? Colors.white38 : PP.muted)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10,
        children: skinTypes.map((s) => _Chip(
          label: s,
          selected: skinType == s,
          onTap: () => onSkinType(s),
          isDark: isDark,
        )).toList(),
      ),
    ]);
  }
}

// ── Step 2: Allergies ─────────────────────────────────────────────────────────
class _Step2 extends StatelessWidget {
  final List<String> selected, common;
  final TextEditingController ctrl;
  final bool isDark;
  final ValueChanged<String> onToggle, onAdd, onRemove;

  const _Step2({
    required this.selected, required this.common, required this.ctrl,
    required this.isDark, required this.onToggle, required this.onAdd, required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Search / add
      TextField(
        controller: ctrl,
        style: PP.body(14, color: isDark ? Colors.white : PP.ink),
        onSubmitted: onAdd,
        decoration: PP.input('Search or add custom allergy', icon: Icons.search).copyWith(
          fillColor: isDark ? const Color(0xFF1A1617) : PP.roseTint,
          suffixIcon: GestureDetector(
            onTap: () => onAdd(ctrl.text.trim()),
            child: Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(gradient: PP.roseGrad, borderRadius: PP.r8),
              child: Text('Add', style: PP.heading(12, color: Colors.white)),
            ),
          ),
        ),
      ),
      if (selected.isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1617) : PP.roseTint,
            borderRadius: PP.r12,
            border: Border.all(color: PP.rose.withOpacity(0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded, color: PP.rose, size: 14),
              const SizedBox(width: 6),
              Text('Your allergies (${selected.length})',
                  style: PP.label(12, color: PP.rose, weight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8,
              children: selected.map((a) => Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                decoration: BoxDecoration(gradient: PP.roseGrad, borderRadius: PP.pill),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(a, style: PP.label(12, color: Colors.white, weight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => onRemove(a),
                    child: Icon(Icons.close, color: Colors.white70, size: 14),
                  ),
                ]),
              )).toList(),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      Text('Common allergens', style: PP.label(12, color: PP.muted)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10,
        children: common.map((a) => _Chip(
          label: a,
          selected: selected.contains(a),
          onTap: () => onToggle(a),
          isDark: isDark,
        )).toList(),
      ),
    ]);
  }
}

// ── Step 3: Skin Conditions ───────────────────────────────────────────────────
class _Step3 extends StatelessWidget {
  final List<String> selected, common;
  final bool isDark;
  final ValueChanged<String> onToggle;

  const _Step3({required this.selected, required this.common, required this.isDark, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10,
      children: common.map((c) => _Chip(
        label: c,
        selected: selected.contains(c),
        onTap: () => onToggle(c),
        isDark: isDark,
        icon: _condIcon(c),
      )).toList(),
    );
  }

  IconData? _condIcon(String c) {
    switch (c) {
      case 'Acne': return Icons.grain;
      case 'Eczema': return Icons.texture;
      case 'Rosacea': return Icons.face_retouching_natural;
      case 'Hyperpigmentation': return Icons.brightness_5_outlined;
      case 'None': return Icons.check_circle_outline;
      default: return null;
    }
  }
}

// ── Summary Card ──────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final String age, gender, skinType;
  final List<String> allergies, conditions;
  final bool isDark;
  const _SummaryCard({
    required this.age, required this.gender, required this.skinType,
    required this.allergies, required this.conditions, required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
            child: const Icon(Icons.person, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 10),
          Text('Profile Summary', style: PP.heading(14, color: PP.rose)),
        ]),
        const SizedBox(height: 14),
        _Row('Age', '$age years old', Icons.cake_outlined, isDark),
        _Row('Gender', gender, Icons.people_outline, isDark),
        _Row('Skin Type', skinType, Icons.water_drop_outlined, isDark),
        _Row('Allergies', allergies.isEmpty ? 'None' : allergies.join(', '), Icons.warning_amber_outlined, isDark),
        _Row('Conditions', conditions.isEmpty ? 'None' : conditions.join(', '), Icons.healing_outlined, isDark),
      ]),
    );
  }

  Widget _Row(String label, String value, IconData icon, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: PP.rose),
      const SizedBox(width: 8),
      Text('$label: ', style: PP.label(12, color: PP.rose, weight: FontWeight.w700)),
      Expanded(child: Text(value, style: PP.body(12, color: isDark ? Colors.white70 : PP.ink))),
    ]),
  );
}

// ── Nav Bar ───────────────────────────────────────────────────────────────────
class _NavBar extends StatelessWidget {
  final int step;
  final bool loading;
  final VoidCallback? onBack, onNext;
  final bool isDark;
  const _NavBar({required this.step, required this.loading, required this.onBack, required this.onNext, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0809) : PP.bg,
        border: Border(top: BorderSide(color: isDark ? Colors.white10 : PP.border)),
      ),
      child: Row(children: [
        if (onBack != null) ...[
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1617) : PP.roseTint,
                borderRadius: PP.r12,
                border: Border.all(color: isDark ? Colors.white12 : PP.border),
              ),
              child: Icon(Icons.arrow_back_ios_new, size: 16,
                  color: isDark ? Colors.white70 : PP.ink),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(child: LuxButton(
          label: loading ? 'Saving...' : (step == 2 ? 'Complete Profile' : 'Continue'),
          icon: loading ? null : (step == 2 ? Icons.check_rounded : Icons.arrow_forward_rounded),
          onPressed: loading ? null : onNext,
          isLoading: loading,
        )),
      ]),
    );
  }
}

// ── Selectable Chip ───────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final bool selected, isDark;
  final VoidCallback onTap;
  final IconData? icon;
  const _Chip({required this.label, required this.selected, required this.isDark, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? PP.roseGrad : null,
          color: selected ? null : (isDark ? const Color(0xFF1A1617) : Colors.white),
          borderRadius: PP.r12,
          border: Border.all(
            color: selected ? Colors.transparent : (isDark ? Colors.white12 : PP.border),
            width: 1,
          ),
          boxShadow: selected ? PP.buttonShadow : PP.softShadow,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: selected ? Colors.white : (isDark ? Colors.white54 : PP.muted)),
            const SizedBox(width: 6),
          ],
          Text(label, style: PP.heading(13,
            color: selected ? Colors.white : (isDark ? Colors.white70 : PP.ink),
            weight: selected ? FontWeight.w600 : FontWeight.w500,
          )),
        ]),
      ),
    );
  }
}

// ── Field Label ───────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  const _FieldLabel(this.label, this.icon, this.isDark);
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: PP.rose),
    const SizedBox(width: 8),
    Text(label, style: PP.heading(15, color: isDark ? Colors.white : PP.ink)),
  ]);
}

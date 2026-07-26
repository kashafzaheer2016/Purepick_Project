import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import '../services/task_poller.dart';
import 'settings_screen.dart';
import 'scan_screen.dart';
import 'barcode_scanner_screen.dart';
import 'ai_tips_screen.dart';
import 'history_screen.dart';
import 'saved_screen.dart';
import 'ai_chat_screen.dart';
import 'skin_analysis_screen.dart';
import 'privacy_screen.dart';
import 'skin_diary_screen.dart';
import 'ingredient_compare_screen.dart';
import 'wellness_dashboard_screen.dart';
import '../widgets/skincast_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  String _name = '';
  String _gender = 'Other';
  String _selectedAvatar = '';   // empty = auto from name/gender
  Map<String, dynamic>? _stats;
  List<dynamic> _tips = [];
  bool _loading = true;
  bool _loadingTips = true;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _loadSavedAvatar();
    _load();
  }

  @override
  void dispose() { _fadeCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;
    if (mounted) {
      setState(() {
        _name = prefs.getString('user_name') ?? '';
        _gender = prefs.getString('user_gender') ?? 'Other';
      });
    }
    
    try {
      final stats = await ApiService.getHomeStats(userId);
      if (mounted) setState(() => _stats = stats);
      
      final profileData = await ApiService.getProfile(userId);
      if (mounted) {
        setState(() {
          _gender = profileData['gender'] ?? 'Other';
        });
        // Sync local storage
        await prefs.setString('user_gender', _gender);
        if (profileData['skin_type'] != null) {
          await prefs.setString('user_skin_type', profileData['skin_type']);
        }
      }

      final tipsRes = await ApiService.getAiTips(userId);
      final taskId = tipsRes['task_id'];
      if (taskId != null) {
        final result = await TaskPoller.poll(taskId);
        if (mounted) {
          final tips = result['tips'] as List<dynamic>? ?? [];
          setState(() {
            _tips = tips;
            // Detect if this is a seasonal/weather tip
            if (tips.any((t) => (t['category'] ?? '').toString().contains('Weather'))) {
              debugPrint("Seasonal insights active for user $userId");
            }
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() { _loading = false; _loadingTips = false; });
        _fadeCtrl.forward();
      }
    }
  }

  Future<void> _loadSavedAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('selected_avatar') ?? '';
    if (mounted) setState(() => _selectedAvatar = saved);
  }

  String get _avatarUrl {
    if (_selectedAvatar.isNotEmpty) return _selectedAvatar;
    final seed = _name.isEmpty ? 'User' : _name;
    final gender = _gender.toLowerCase();
    if (gender == 'male') return 'https://api.dicebear.com/7.x/avataaars/png?seed=$seed&gender=male';
    if (gender == 'female') return 'https://api.dicebear.com/7.x/avataaars/png?seed=$seed&gender=female';
    return 'https://api.dicebear.com/7.x/avataaars/png?seed=$seed';
  }

  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AvatarPickerSheet(
        currentUrl: _avatarUrl,
        onSelected: (url) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('selected_avatar', url);
          if (mounted) setState(() => _selectedAvatar = url);
        },
      ),
    );
  }

  void _go(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) => _load());

  Widget _buildStreakValue() {
    final streak = _stats?['streak'];
    if (streak is Map) {
      return Text('${streak['current'] ?? 0}',
          style: PP.heading(20, color: Colors.white, weight: FontWeight.w700));
    }
    return Text('${streak ?? 0}',
        style: PP.heading(20, color: Colors.white, weight: FontWeight.w700));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final first = _name.split(' ').first;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        color: PP.rose,
        onRefresh: () async { setState(() { _loading = true; _loadingTips = true; }); await _load(); },
        child: CustomScrollView(
          slivers: [
            // ── Animated Header ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark 
                      ? [const Color(0xFF261A1F), const Color(0xFF1A1015)]
                      : [const Color(0xFF5C3040), const Color(0xFFB07A8A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? Colors.black : PP.rose).withOpacity(0.2), 
                      blurRadius: 30, 
                      offset: const Offset(0, 10)
                    ),
                  ],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: _showAvatarPicker,
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 48, height: 48,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white38, width: 2),
                                      ),
                                      child: ClipOval(
                                        child: Image.network(
                                          _avatarUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (ctx, _, __) => Container(
                                            color: PP.rose,
                                            child: const Icon(Icons.person, color: Colors.white, size: 24),
                                          ),
                                          loadingBuilder: (ctx, child, progress) => progress == null
                                              ? child
                                              : Container(
                                                  color: isDark ? Colors.white10 : PP.roseTint,
                                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
                                                ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0, bottom: 0,
                                      child: Container(
                                        width: 16, height: 16,
                                        decoration: BoxDecoration(
                                          color: PP.rose,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 1.5),
                                        ),
                                        child: const Icon(Icons.edit, size: 9, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Welcome back,', style: PP.body(12, color: Colors.white60)),
                                  Text(first.isEmpty ? 'Beauty Expert' : first,
                                      style: PP.display(22, color: Colors.white, weight: FontWeight.w700)),
                                ],
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => _go(const SettingsScreen()),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: PP.r12,
                                border: Border.all(color: Colors.white10),
                              ),
                              child: const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: PP.r20,
                                border: Border.all(color: Colors.white.withOpacity(0.12)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.local_fire_department_rounded, color: Colors.orangeAccent, size: 22),
                                  const SizedBox(height: 12),
                                  Text('Daily Streak', style: PP.label(10, color: Colors.white54)),
                                  _buildStreakValue(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _StatCard(
                            label: 'Safety Score',
                            value: _stats?['avg_safety'] ?? '—',
                            icon: Icons.verified_user_rounded,
                            iconColor: const Color(0xFF9DC183),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  // ── [NEW] SkinCast™ Advisor ──────────────────────────────
                  const SkinCastWidget(),
                  const SizedBox(height: 32),

                  // ── AI Insights Carousel ──────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Daily Skin Insights', style: PP.heading(18, color: theme.colorScheme.onSurface)),
                      if (_tips.isNotEmpty)
                        Icon(Icons.auto_awesome, color: PP.rose, size: 18),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loadingTips)
                    _ShimmerPlaceholder(height: 140)
                  else if (_tips.isEmpty)
                    _InfoCard(
                      title: 'Start Scanning',
                      body: 'Scan your first product to unlock personalized AI beauty tips.',
                      icon: Icons.lightbulb_outline_rounded,
                    )
                  else
                    SizedBox(
                      height: 170,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _tips.length,
                        itemBuilder: (ctx, i) => _InsightCard(tip: _tips[i]),
                      ),
                    ),

                  const SizedBox(height: 32),

                  // ── Action Grid ──────────────────────────────────────────
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _FeatureCard(
                        title: 'Scan Label',
                        sub: 'AI Ingredient Analysis',
                        icon: Icons.document_scanner_rounded,
                        color: const Color(0xFFF5EEF0),
                        iconColor: PP.rose,
                        onTap: () => _go(const ScannerScreen()),
                      )),
                      const SizedBox(width: 14),
                      Expanded(child: _FeatureCard(
                        title: 'Barcode',
                        sub: 'Instant Product Lookup',
                        icon: Icons.barcode_reader,
                        color: const Color(0xFFF9F3EA),
                        iconColor: PP.gold,
                        onTap: () => _go(const BarcodeScannerScreen()),
                      )),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _SkinBanner(onTap: () => _go(const SkinAnalysisScreen())),
                  
                  if (_stats?['recent_skin'] != null) ...[
                    const SizedBox(height: 24),
                    _RecentSkinCard(data: _stats!['recent_skin']),
                  ],

                  const SizedBox(height: 24),

                  // ── New Tools Row ─────────────────────────────────────────
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _FeatureCard(
                      title: 'Compare',
                      sub: 'Side-by-side analysis',
                      icon: Icons.compare_arrows_rounded,
                      color: const Color(0xFFEDF5EF),
                      iconColor: PP.safe,
                      onTap: () => _go(const IngredientCompareScreen()),
                    )),
                    const SizedBox(width: 14),
                    Expanded(child: _FeatureCard(
                      title: 'Skin Diary',
                      sub: 'Track your progress',
                      icon: Icons.calendar_month_outlined,
                      color: const Color(0xFFF3EEFF),
                      iconColor: Colors.deepPurple,
                      onTap: () => _go(const SkinDiaryScreen()),
                    )),
                    const SizedBox(width: 14),
                    Expanded(child: _FeatureCard(
                      title: 'Wellness',
                      sub: 'Your score & streak',
                      icon: Icons.bar_chart_rounded,
                      color: PP.goldTint,
                      iconColor: PP.gold,
                      onTap: () => _go(const WellnessDashboardScreen()),
                    )),
                  ]),

                  const SizedBox(height: 32),

                  // ── Recent Activity ───────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Recent Activity', style: PP.heading(18, color: theme.colorScheme.onSurface)),
                      GestureDetector(
                        onTap: () => _go(const HistoryScreen()),
                        child: Text('See History', style: PP.body(13, color: PP.rose, weight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_loading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ))
                  else if (_stats == null || (_stats?['recent_scans'] as List? ?? []).isEmpty)
                    _EmptyScans()
                  else
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: Column(
                        children: (_stats!['recent_scans'] as List).map<Widget>((scan) {
                          return _RecentScanCard(scan: scan, score: (scan['score'] ?? 0).toDouble());
                        }).toList(),
                      ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Luxury Stat Card ────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color iconColor;
  const _StatCard({required this.label, required this.value, required this.icon, required this.iconColor});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: PP.r20,
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 12),
          Text(label, style: PP.label(10, color: Colors.white54)),
          Text(value, style: PP.heading(20, color: Colors.white, weight: FontWeight.w700)),
        ],
      ),
    ),
  );
}

// ── Horizontal Insight Card ──────────────────────────────────────────────────
class _InsightCard extends StatefulWidget {
  final Map tip;
  const _InsightCard({required this.tip});
  @override
  State<_InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends State<_InsightCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _hover = true),
        onTapUp: (_) => setState(() => _hover = false),
        onTapCancel: () => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 260,
          margin: const EdgeInsets.only(right: 14, bottom: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1418) : Colors.white,
            borderRadius: PP.r20,
            boxShadow: _hover ? PP.glow(PP.rose) : PP.softShadow,
            border: Border.all(
              color: _hover ? PP.rose.withOpacity(0.5) : (isDark ? const Color(0xFF2E1E24) : PP.border),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? PP.rose.withOpacity(0.2) : PP.rose.withOpacity(0.1),
                      borderRadius: PP.pill,
                    ),
                    child: Text(
                      widget.tip['category'] ?? 'Tip',
                      style: PP.label(9, color: PP.rose, weight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.auto_awesome, size: 13, color: _hover ? PP.gold : (isDark ? Colors.white24 : Colors.grey)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.tip['title'] ?? '',
                style: PP.heading(13, color: Theme.of(context).colorScheme.onSurface),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              Text(
                widget.tip['body'] ?? '',
                style: PP.body(11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75)),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Feature Action Card ──────────────────────────────────────────────────────
class _FeatureCard extends StatefulWidget {
  final String title, sub;
  final IconData icon;
  final Color color, iconColor;
  final VoidCallback onTap;
  const _FeatureCard({required this.title, required this.sub, required this.icon, required this.color, required this.iconColor, required this.onTap});
  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _hover = true),
        onTapUp: (_) => setState(() => _hover = false),
        onTapCancel: () => setState(() => _hover = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1617) : Colors.white,
            borderRadius: PP.r20,
            boxShadow: _hover ? PP.glow(widget.iconColor) : PP.softShadow,
            border: Border.all(color: _hover ? widget.iconColor.withOpacity(0.5) : (isDark ? Colors.white10 : PP.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _hover ? widget.iconColor.withOpacity(0.2) : (isDark ? widget.iconColor.withOpacity(0.15) : widget.color),
                  borderRadius: PP.r10,
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 20),
              ),
              const SizedBox(height: 10),
              Text(widget.title,
                  style: PP.heading(13, color: Theme.of(context).colorScheme.onSurface, weight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(widget.sub, style: PP.body(10), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title, body;
  final IconData icon;
  const _InfoCard({required this.title, required this.body, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: PP.card(),
    child: Row(
      children: [
        Icon(icon, color: PP.rose, size: 30),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: PP.heading(15, color: Theme.of(context).colorScheme.onSurface)),
            Text(body, style: PP.body(12)),
          ],
        )),
      ],
    ),
  );
}

class _ShimmerPlaceholder extends StatelessWidget {
  final double height;
  const _ShimmerPlaceholder({required this.height});

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.03),
      borderRadius: PP.r20,
    ),
    child: Center(child: Icon(Icons.auto_awesome, color: PP.rose.withOpacity(0.2), size: 40)),
  );
}

// ── Scan CTA Card ─────────────────────────────────────────────────────────────
class _ScanCTA extends StatefulWidget {
  final IconData icon;
  final String label, sub;
  final Gradient gradient;
  final List<BoxShadow> shadows;
  final VoidCallback onTap;
  const _ScanCTA({required this.icon, required this.label, required this.sub,
      required this.gradient, required this.shadows, required this.onTap});
  @override
  State<_ScanCTA> createState() => _ScanCTAState();
}

class _ScanCTAState extends State<_ScanCTA> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: 90,
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: PP.r20,
            boxShadow: widget.shadows,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(widget.icon, color: Colors.white, size: 26),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.label, style: PP.heading(14, color: Colors.white, weight: FontWeight.w700)),
                Text(widget.sub, style: PP.body(11, color: Colors.white70)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Quick Action ──────────────────────────────────────────────────────────────
class _QuickAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color bg, iconColor;
  final VoidCallback onTap;
  _QuickAction(this.label, this.icon, this.bg, this.iconColor, this.onTap);
  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: Container(
          decoration: PP.card(color: PP.surface),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: widget.bg, borderRadius: PP.r12),
                child: Icon(widget.icon, color: widget.iconColor, size: 20),
              ),
              const SizedBox(height: 8),
              Text(widget.label, style: PP.label(11, color: PP.ink, weight: FontWeight.w600), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Skin Analysis Banner ──────────────────────────────────────────────────────
class _SkinBanner extends StatefulWidget {
  final VoidCallback onTap;
  const _SkinBanner({required this.onTap});
  @override
  State<_SkinBanner> createState() => _SkinBannerState();
}

class _SkinBannerState extends State<_SkinBanner> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: 108,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4A2535), Color(0xFF7A4055), Color(0xFFB07A8A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: PP.r20,
            boxShadow: PP.buttonShadow,
          ),
          child: ClipRRect(
            borderRadius: PP.r20,
            child: Stack(children: [
              // Shimmer overlay
              AnimatedBuilder(
                animation: _shimmer,
                builder: (_, __) => Positioned(
                  left: (_shimmer.value - 0.5) * 400,
                  top: 0, bottom: 0,
                  width: 120,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.white.withOpacity(0.06), Colors.transparent],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
              ),
              // Decorative circles
              Positioned(right: -16, top: -16,
                child: Container(width: 100, height: 100,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.07)))),
              Positioned(right: 50, bottom: -24,
                child: Container(width: 64, height: 64,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: PP.gold.withOpacity(0.15)))),
              // Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.15),
                      border: Border.all(color: PP.gold.withOpacity(0.4), width: 1.2),
                    ),
                    child: const Icon(Icons.face_retouching_natural, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: [
                        Text('Skin Analysis', style: PP.heading(16, color: Colors.white, weight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: PP.gold.withOpacity(0.3),
                            borderRadius: PP.pill,
                            border: Border.all(color: PP.gold.withOpacity(0.5)),
                          ),
                          child: Text('AI', style: PP.label(9, color: Colors.white, weight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text('Detect skin type, conditions & get expert care recommendations',
                          style: PP.body(11, color: Colors.white70), maxLines: 2),
                    ],
                  )),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 16),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Recent Skin Card ─────────────────────────────────────────────────────────
class _RecentSkinCard extends StatelessWidget {
  final Map data;
  const _RecentSkinCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: PP.card(color: isDark ? const Color(0xFF1A1215) : PP.roseTint),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.face_retouching_natural, color: PP.rose, size: 20),
              const SizedBox(width: 10),
              Text('Latest Skin Health', style: PP.heading(15, color: theme.colorScheme.onSurface)),
              const Spacer(),
              Text(data['date'] ?? '', style: PP.label(11)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _SkinMetric(label: 'Type', value: data['type'] ?? 'Normal'),
              Container(width: 1, height: 30, color: PP.border, margin: const EdgeInsets.symmetric(horizontal: 16)),
              _SkinMetric(label: 'Primary Concern', value: (data['disorder']?.toString().isEmpty ?? true) ? 'None' : data['disorder']),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkinMetric extends StatelessWidget {
  final String label, value;
  const _SkinMetric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PP.label(10, color: PP.muted)),
        const SizedBox(height: 2),
        Text(value, style: PP.heading(14, color: Theme.of(context).colorScheme.onSurface), 
            overflow: TextOverflow.ellipsis, maxLines: 1),
      ],
    ),
  );
}

// ── Recent Scan Card ──────────────────────────────────────────────────────────
class _RecentScanCard extends StatelessWidget {
  final Map scan;
  final double score;
  const _RecentScanCard({required this.scan, required this.score});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final band   = (scan['risk_level'] ?? scan['band'] ?? '').toString().toLowerCase();
    final color  = band.contains('high') ? PP.danger : band.contains('moderate') ? PP.warn : PP.safe;
    final tint   = isDark
        ? color.withOpacity(0.18)
        : (band.contains('high') ? PP.dangerTint : band.contains('moderate') ? PP.warnTint : PP.safeTint);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: PP.card(dark: isDark),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(color: tint, borderRadius: PP.r12),
          child: Icon(Icons.inventory_2_outlined, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(scan['product_name'] ?? 'Unknown Product',
                style: PP.heading(14, color: theme.colorScheme.onSurface),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(scan['date'] ?? '', style: PP.label(11)),
          ],
        )),
        SafetyBadge(level: scan['risk_level'] ?? scan['band'] ?? '', score: score),
      ]),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────
class _EmptyScans extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: PP.card(dark: isDark),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: isDark ? PP.rose.withOpacity(0.15) : PP.roseTint,
            borderRadius: PP.r16,
          ),
          child: Icon(Icons.spa_outlined, color: PP.roseLt, size: 30),
        ),
        const SizedBox(height: 14),
        Text('No scans yet', style: PP.heading(15, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 6),
        Text('Scan your first product to start your\npersonalised safety journey',
            style: PP.body(13), textAlign: TextAlign.center),
      ]),
    );
  }
}

// ── Avatar Picker Bottom Sheet ──────────────────────────────────────────────

class _AvatarPickerSheet extends StatelessWidget {
  final String currentUrl;
  final ValueChanged<String> onSelected;
  const _AvatarPickerSheet({required this.currentUrl, required this.onSelected});

  static const List<Map<String, String>> _avatars = [
    {'label': 'Adventurer',   'url': 'https://api.dicebear.com/7.x/adventurer/png?seed=PurePick1'},
    {'label': 'Cutie',        'url': 'https://api.dicebear.com/7.x/adventurer/png?seed=PurePick2'},
    {'label': 'Blossom',      'url': 'https://api.dicebear.com/7.x/adventurer/png?seed=Rose'},
    {'label': 'Sunny',        'url': 'https://api.dicebear.com/7.x/adventurer/png?seed=Sunny'},
    {'label': 'Classic M',    'url': 'https://api.dicebear.com/7.x/avataaars/png?seed=Alex'},
    {'label': 'Classic F',    'url': 'https://api.dicebear.com/7.x/avataaars/png?seed=Sophie'},
    {'label': 'Pixel',        'url': 'https://api.dicebear.com/7.x/pixel-art/png?seed=PurePick'},
    {'label': 'Pixel Girl',   'url': 'https://api.dicebear.com/7.x/pixel-art/png?seed=Lily'},
    {'label': 'Fun Bear',     'url': 'https://api.dicebear.com/7.x/fun-emoji/png?seed=Bear'},
    {'label': 'Fun Cat',      'url': 'https://api.dicebear.com/7.x/fun-emoji/png?seed=Cat'},
    {'label': 'Lorelei',      'url': 'https://api.dicebear.com/7.x/lorelei/png?seed=PurePick'},
    {'label': 'Lorelei 2',    'url': 'https://api.dicebear.com/7.x/lorelei/png?seed=Glow'},
    {'label': 'Notionists',   'url': 'https://api.dicebear.com/7.x/notionists/png?seed=Pink'},
    {'label': 'Notionists 2', 'url': 'https://api.dicebear.com/7.x/notionists/png?seed=Rose'},
    {'label': 'Micah',        'url': 'https://api.dicebear.com/7.x/micah/png?seed=PurePick'},
    {'label': 'Micah 2',      'url': 'https://api.dicebear.com/7.x/micah/png?seed=Beauty'},
  ];

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final screen  = MediaQuery.of(context);
    final maxH    = screen.size.height * 0.75;   // never taller than 75% of screen
    final hPad    = screen.size.width < 360 ? 16.0 : 24.0;
    // Avatar size: 4 per row, dynamic based on screen width
    final avatarSize = ((screen.size.width - hPad * 2 - 12 * 3) / 4).clamp(52.0, 72.0);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1015) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle + header (fixed, never scrolls) ──────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Choose Your Avatar',
                        style: PP.heading(18, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text('Tap any cartoon to set your profile picture',
                        style: PP.body(12), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              // ── Scrollable grid ─────────────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(hPad, 0, hPad, screen.padding.bottom + 16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 14,
                    alignment: WrapAlignment.center,
                    children: List.generate(_avatars.length, (i) {
                      final av = _avatars[i];
                      final isSelected = currentUrl == av['url'];
                      return GestureDetector(
                        onTap: () {
                          onSelected(av['url']!);
                          Navigator.pop(context);
                        },
                        child: SizedBox(
                          width: avatarSize,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: avatarSize,
                                height: avatarSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? PP.rose : (isDark ? Colors.white12 : PP.border),
                                    width: isSelected ? 3 : 1.5,
                                  ),
                                  boxShadow: isSelected ? PP.glow(PP.rose) : [],
                                ),
                                child: ClipOval(
                                  child: Image.network(
                                    av['url']!,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (_, child, prog) => prog == null
                                        ? child
                                        : Container(
                                            color: isDark ? const Color(0xFF261A1F) : PP.roseTint,
                                            child: Center(
                                              child: SizedBox(
                                                width: avatarSize * 0.3,
                                                height: avatarSize * 0.3,
                                                child: const CircularProgressIndicator(strokeWidth: 1.5),
                                              ),
                                            ),
                                          ),
                                    errorBuilder: (_, __, ___) => Container(
                                      color: PP.roseTint,
                                      child: Icon(Icons.face, color: PP.rose, size: avatarSize * 0.45),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                av['label']!,
                                style: PP.label(10),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import '../services/dashboard_service.dart';
import '../widgets/skin_diary_box.dart';

/// Skin Diary — tracks skin analysis history and daily logs.
class SkinDiaryScreen extends StatefulWidget {
  const SkinDiaryScreen({super.key});
  @override
  State<SkinDiaryScreen> createState() => _SkinDiaryScreenState();
}

class _SkinDiaryScreenState extends State<SkinDiaryScreen> {
  List<dynamic> _history = [];
  Map<String, dynamic>? _todayLog;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getInt('user_id') ?? 0;
      
      debugPrint("DEBUG: SkinDiary loading for UID $uid");
      
      // Load history
      final history = await ApiService.getSkinHistory(uid);
      
      // Attempt to load dashboard data (today's log)
      Map<String, dynamic>? log;
      try {
        final dash = await DashboardService.getDashboard(0, 0);
        log = dash.todayLog;
      } catch (e) {
        debugPrint("DEBUG: Dashboard fetch failed, continuing with empty log: $e");
      }
      
      if (mounted) {
        setState(() {
          _history = history;
          _todayLog = log;
          _loading = false;
        });
        debugPrint("DEBUG: SkinDiary loaded. History count: ${_history.length}");
      }
    } catch (e) {
      debugPrint("DEBUG: SkinDiary critical load error: $e");
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: LuxAppBar(title: 'Skin Diary'),
      body: _error != null
          ? _buildError(theme)
          : RefreshIndicator(
              color: PP.rose,
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Daily Logging Tool ────────────────────────────────
                    Text('Daily Log', style: PP.heading(18, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 12),
                    
                    if (_loading)
                      _buildToolSkeleton()
                    else
                      SkinDiaryBox(
                        initialData: _todayLog,
                        onSaved: () {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Text('Skin status logged!'),
                            backgroundColor: PP.safe,
                            behavior: SnackBarBehavior.floating,
                          ));
                          _load();
                        },
                      ),
                    
                    const SizedBox(height: 32),

                    // ── Historical Analysis ──────────────────────────────
                    Text('Skin History', style: PP.heading(18, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 16),
                    
                    if (_loading)
                      const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: PP.rose)))
                    else if (_history.isEmpty)
                      _buildEmptyState(isDark)
                    else
                      ..._history.map((entry) => _DiaryEntry(entry: entry as Map<String, dynamic>, isDark: isDark)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildToolSkeleton() => Container(
    height: 300,
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.grey.withOpacity(0.05),
      borderRadius: PP.r20,
      border: Border.all(color: Colors.grey.withOpacity(0.1)),
    ),
    child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: PP.rose)),
  );

  Widget _buildError(ThemeData theme) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.error_outline, color: PP.danger, size: 48),
      const SizedBox(height: 12),
      Text('Could not load diary history', style: PP.heading(15, color: theme.colorScheme.onSurface)),
      const SizedBox(height: 8),
      TextButton(onPressed: _load, child: Text('Retry', style: PP.label(14, color: PP.rose))),
    ]),
  );

  Widget _buildEmptyState(bool isDark) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF261418) : PP.roseTint,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.face_retouching_natural, color: PP.roseLt, size: 38),
        ),
        const SizedBox(height: 20),
        Text('No diary entries yet', style: PP.heading(18, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 8),
        Text(
          'Complete your first skin analysis to start tracking your skin journey over time.',
          style: PP.body(13, color: PP.muted),
          textAlign: TextAlign.center,
        ),
      ]),
    ),
  );
}

class _DiaryEntry extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool isDark;
  const _DiaryEntry({required this.entry, required this.isDark});

  Color _typeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'oily':        return const Color(0xFF2E7D32);
      case 'dry':         return const Color(0xFFBF360C);
      case 'sensitive':   return const Color(0xFF6A1B9A);
      case 'combination': return const Color(0xFF0277BD);
      case 'normal':      return const Color(0xFF00695C);
      default:            return PP.rose;
    }
  }

  @override
  Widget build(BuildContext context) {
    final skinType = entry['skin_type'] as String? ?? 'Unknown';
    final disorder = entry['skin_disorder'] as String? ?? '';
    final conf = ((entry['skin_type_confidence'] ?? 0) as num).toDouble();
    final date = entry['date'] as String? ?? '';
    final color = _typeColor(skinType);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161213) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Center(child: Text(
            skinType.substring(0, 1),
            style: GoogleFonts.poppins(color: color, fontSize: 22, fontWeight: FontWeight.bold),
          )),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(skinType, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : const Color(0xFF1A1F2E))),
          if (disorder.isNotEmpty)
            Text(disorder, style: GoogleFonts.poppins(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (conf / 100).clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 2),
          Text('${conf.toStringAsFixed(0)}% confidence', style: GoogleFonts.poppins(fontSize: 10, color: PP.muted)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(date, style: PP.label(11, color: PP.muted)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('Analysis', style: PP.label(10, color: color, weight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}

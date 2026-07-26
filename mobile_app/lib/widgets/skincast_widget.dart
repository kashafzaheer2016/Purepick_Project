import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/skincast_service.dart';

class SkinCastWidget extends StatefulWidget {
  const SkinCastWidget({super.key});

  @override
  State<SkinCastWidget> createState() => _SkinCastWidgetState();
}

class _SkinCastWidgetState extends State<SkinCastWidget> {
  SkinCastResult? _result;
  SkinCastData? _rawData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final skinType = prefs.getString('user_skin_type') ?? 'Normal';
    
    final data = await SkinCastService.fetchData();
    final res = SkinCastService.getRecommendation(data, skinType);
    
    if (mounted) {
      setState(() {
        _rawData = data;
        _result = res;
        _loading = false;
      });
    }
  }

  IconData _getIcon(String name) {
    switch (name) {
      case "moon":      return Icons.dark_mode_rounded;
      case "alert":     return Icons.warning_amber_rounded;
      case "sun":       return Icons.wb_sunny_rounded;
      case "flame":     return Icons.local_fire_department_rounded;
      case "snowflake": return Icons.ac_unit_rounded;
      case "check":     return Icons.check_circle_outline_rounded;
      default:          return Icons.wb_cloudy_rounded;
    }
  }

  void _showRoutineDetails() {
    if (_result == null || _rawData == null) return;
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.75),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D0B0C) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: isDark ? const Color(0xFF3D2A30) : PP.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // fixed handle
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: Container(width: 40, height: 4,
                          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: PP.pill))),
                      const SizedBox(height: 20),
                      Row(children: [
                        Icon(_getIcon(_result!.iconName), color: PP.rose, size: 22),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Your Custom Routine',
                            style: PP.heading(18, color: Theme.of(ctx).colorScheme.onSurface),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                      const SizedBox(height: 4),
                      Text('Optimized for ${_rawData!.city} weather.',
                          style: PP.body(13), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                // scrollable steps
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, mq.padding.bottom + 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _RoutineStep(icon: Icons.water_drop_outlined, label: 'CLEANSE',
                            desc: 'Use a pH-balanced gentle cleanser.'),
                        _RoutineStep(icon: Icons.science_outlined, label: 'TREAT',
                            desc: _result!.message),
                        _RoutineStep(icon: Icons.shield_moon_outlined, label: 'PROTECT',
                            desc: _result!.title.contains('UV')
                                ? 'Apply broad-spectrum SPF 50+ immediately.'
                                : 'Seal with a lightweight moisturizer.'),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: LuxButton(label: 'Got it', onPressed: () => Navigator.pop(ctx)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildSkeleton();
    if (_result == null || _rawData == null) return const SizedBox.shrink();

    // Defensive check for theme colors
    final colors = _result!.themeColors;
    final primary = colors.isNotEmpty ? Color(colors[0]) : PP.rose;
    final secondary = colors.length > 1 ? Color(colors[1]) : (colors.isNotEmpty ? Color(colors[0]) : PP.roseLt);

    final screenW = MediaQuery.of(context).size.width;
    final cardPad = screenW < 360 ? 16.0 : 20.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      padding: EdgeInsets.all(cardPad),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: PP.r28,
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: PP.r28,
        child: Stack(
          children: [
            // decorative background icon — Positioned inside clipped Stack, won't cause overflow
            Positioned(
              right: -20, top: -20,
              child: Opacity(
                opacity: 0.1,
                child: Icon(_getIcon(_result!.iconName), size: 110, color: Colors.white),
              ),
            ),
            // main content — Column with mainAxisSize.min so it never overflows
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Location + temp row ───────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded, size: 11, color: Colors.white),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _rawData!.city.toUpperCase(),
                                style: PP.label(9, color: Colors.white, weight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_rawData!.temp.round()}°',
                      style: PP.display(22, color: Colors.white, weight: FontWeight.w800),
                    ),
                  ],
                ),
                SizedBox(height: screenW < 360 ? 14 : 18),
                // ── Icon + title + message ────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(screenW < 360 ? 9 : 11),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: PP.r12,
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Icon(_getIcon(_result!.iconName), color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _result!.title,
                            style: PP.heading(15, color: Colors.white, weight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _result!.message,
                            style: PP.body(12, color: Colors.white.withOpacity(0.9)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: screenW < 360 ? 14 : 18),
                // ── View Routine button ───────────────────────────────────
                GestureDetector(
                  onTap: _showRoutineDetails,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('VIEW ROUTINE',
                            style: PP.label(11, color: Colors.white, weight: FontWeight.w800)),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 11),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: PP.r28,
      ),
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: PP.rose),
      ),
    );
  }
}

class _RoutineStep extends StatelessWidget {
  final IconData icon;
  final String label, desc;
  const _RoutineStep({required this.icon, required this.label, required this.desc});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(children: [
      Icon(icon, size: 20, color: PP.muted),
      const SizedBox(width: 16),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: PP.label(10, weight: FontWeight.w800, color: PP.rose)),
          Text(desc, style: PP.body(13, color: Theme.of(context).colorScheme.onSurface)),
        ],
      )),
    ]),
  );
}

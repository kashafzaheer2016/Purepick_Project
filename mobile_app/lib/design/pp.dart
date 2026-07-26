import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// PurePick Luxury Beauty Design System
/// 
/// Color palette: Blush & Champagne with Rose Gold accents
/// Inspired by high-end beauty brands (La Mer, Charlotte Tilbury, Dior Beauty)
class PP {
  PP._();

  // ── Core Palette ─────────────────────────────────────────────────────────

  /// Champagne white — primary background
  static const Color bg          = Color(0xFFFAF8F5);
  /// Warm off-white — card background
  static const Color surface     = Color(0xFFFFFCF9);
  /// Deep blush rose — primary brand
  static const Color rose        = Color(0xFFB07A8A);
  /// Lighter blush — secondary / hover states
  static const Color roseLt      = Color(0xFFD4A5B0);
  /// Rose tint — backgrounds, chips
  static const Color roseTint    = Color(0xFFF5EEF0);
  /// Champagne gold — accents, highlights
  static const Color gold        = Color(0xFFC9A96E);
  /// Light gold tint
  static const Color goldTint    = Color(0xFFF9F3EA);
  /// Deep mocha — primary text
  static const Color ink         = Color(0xFF2D1F26);
  /// Warm grey — secondary text
  static const Color muted       = Color(0xFF8A7580);
  /// Very light grey — dividers, borders
  static const Color border      = Color(0xFFEEE8EC);
  /// Safe green (safety indicator)
  static const Color safe        = Color(0xFF5A8A6A);
  static const Color safeTint    = Color(0xFFEDF5EF);
  /// Amber (moderate)
  static const Color warn        = Color(0xFFC4883A);
  static const Color warnTint    = Color(0xFFFAF3E8);
  /// Soft red (danger)
  static const Color danger      = Color(0xFFB04A4A);
  static const Color dangerTint  = Color(0xFFF7ECEC);

  // ── Luxury Dark Palette ────────────────────────────────────────────────────
  static const Color obsidian  = Color(0xFF0D0B0C);
  static const Color deepRose  = Color(0xFF261418);
  static const Color cardDark  = Color(0xFF161213);
  static const Color goldGlow  = Color(0xFFFFD700);

  // ── Luxury Shadows & Glows ──────────────────────────────────────────────────
  static List<BoxShadow> glow(Color color) => [
    BoxShadow(color: color.withOpacity(0.3), blurRadius: 20, spreadRadius: 2),
    BoxShadow(color: color.withOpacity(0.1), blurRadius: 40, spreadRadius: 10),
  ];

  static BoxDecoration glass({bool dark = false}) => BoxDecoration(
    color: dark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.7),
    borderRadius: r20,
    border: Border.all(color: dark ? Colors.white10 : Colors.white.withOpacity(0.2)),
  );

  // ── Gradients ────────────────────────────────────────────────────────────

  static const LinearGradient roseGrad = LinearGradient(
    colors: [Color(0xFFB07A8A), Color(0xFF8A5A6A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient roseGradLight = LinearGradient(
    colors: [Color(0xFFE8D5DA), Color(0xFFD4B8C0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGrad = LinearGradient(
    colors: [Color(0xFFD4AF70), Color(0xFFC4903A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bgGrad = LinearGradient(
    colors: [Color(0xFFFAF8F5), Color(0xFFF5EEF0)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Shadows ───────────────────────────────────────────────────────────────

  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFFB07A8A).withOpacity(0.08),
      blurRadius: 20,
      offset: const Offset(0, 6),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get buttonShadow => [
    BoxShadow(
      color: const Color(0xFFB07A8A).withOpacity(0.35),
      blurRadius: 18,
      offset: const Offset(0, 7),
      spreadRadius: -2,
    ),
  ];

  static List<BoxShadow> get goldButtonShadow => [
    BoxShadow(
      color: const Color(0xFFC9A96E).withOpacity(0.40),
      blurRadius: 18,
      offset: const Offset(0, 7),
      spreadRadius: -2,
    ),
  ];

  // ── Typography ────────────────────────────────────────────────────────────

  static TextStyle display(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.cormorantGaramond(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w600,
        color: color ?? ink,
        letterSpacing: -0.3,
      );

  static TextStyle heading(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.dmSans(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w600,
        color: color ?? ink,
        letterSpacing: -0.2,
      );

  static TextStyle body(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.dmSans(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        color: color ?? muted,
        height: 1.5,
      );

  static TextStyle label(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.dmSans(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w500,
        color: color ?? muted,
        letterSpacing: 0.4,
      );

  static TextStyle mono(double size, {Color? color}) =>
      GoogleFonts.dmMono(
        fontSize: size,
        color: color ?? muted,
        letterSpacing: 0.2,
      );

  // ── Border Radius ─────────────────────────────────────────────────────────

  static BorderRadius get r8  => BorderRadius.circular(8);
  static BorderRadius get r10 => BorderRadius.circular(10);
  static BorderRadius get r12 => BorderRadius.circular(12);
  static BorderRadius get r16 => BorderRadius.circular(16);
  static BorderRadius get r20 => BorderRadius.circular(20);
  static BorderRadius get r28 => BorderRadius.circular(28);
  static BorderRadius get pill => BorderRadius.circular(100);

  // ── Decoration Helpers ────────────────────────────────────────────────────

  static BoxDecoration card({
    Color? color,
    BorderRadius? radius,
    List<BoxShadow>? shadows,
    Gradient? gradient,
    Color? borderColor,
    bool dark = false,
  }) =>
      BoxDecoration(
        color: gradient == null
            ? (color ?? (dark ? const Color(0xFF1E1418) : surface))
            : null,
        gradient: gradient,
        borderRadius: radius ?? r16,
        boxShadow: shadows ?? cardShadow,
        border: borderColor != null
            ? Border.all(color: borderColor, width: 1)
            : Border.all(
                color: dark ? const Color(0xFF2E1E24) : border,
                width: 0.8,
              ),
      );

  static BoxDecoration pill_({
    Color? color,
    List<BoxShadow>? shadows,
    Gradient? gradient,
  }) =>
      BoxDecoration(
        color: gradient == null ? (color ?? surface) : null,
        gradient: gradient,
        borderRadius: pill,
        boxShadow: shadows,
      );

  // ── Input Decoration ──────────────────────────────────────────────────────

  static InputDecoration input(String label, {IconData? icon, String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: body(14, color: muted),
        hintStyle: body(14, color: muted.withOpacity(0.6)),
        prefixIcon: icon != null
            ? Icon(icon, color: roseLt, size: 20)
            : null,
        filled: true,
        fillColor: roseTint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: r12,
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: r12,
          borderSide: BorderSide(color: rose, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: r12,
          borderSide: BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: r12,
          borderSide: BorderSide(color: danger, width: 1.5),
        ),
      );

  // ── Theme Data ────────────────────────────────────────────────────────────

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.light(
          primary: rose,
          secondary: gold,
          surface: surface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: ink,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          foregroundColor: ink,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          titleTextStyle: heading(17, color: ink),
          iconTheme: IconThemeData(color: ink),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: surface,
          shape: RoundedRectangleBorder(borderRadius: r16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: rose,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: pill),
            textStyle: heading(15, color: Colors.white),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: roseTint,
          border: OutlineInputBorder(
            borderRadius: r12,
            borderSide: BorderSide(color: border),
          ),
        ),
        dividerTheme: DividerThemeData(color: border, thickness: 0.8),
        textTheme: GoogleFonts.dmSansTextTheme().copyWith(
          displayLarge: display(32),
          headlineMedium: heading(24),
          titleMedium: heading(16),
          bodyMedium: body(14),
          labelMedium: label(12),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0809),
        colorScheme: ColorScheme.dark(
          primary: roseLt,
          secondary: gold,
          surface: const Color(0xFF161213),
          onPrimary: Colors.white,
          onSurface: const Color(0xFFE0D8DB),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF0A0809),
          foregroundColor: const Color(0xFFE0D8DB),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          titleTextStyle: heading(17, color: const Color(0xFFE0D8DB)),
          iconTheme: const IconThemeData(color: Color(0xFFE0D8DB)),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF161213),
          shape: RoundedRectangleBorder(borderRadius: r20),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1617),
          border: OutlineInputBorder(
            borderRadius: r12,
            borderSide: const BorderSide(color: Color(0xFF2D1F26)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: r12,
            borderSide: const BorderSide(color: Color(0xFF2D1F26)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: r12,
            borderSide: BorderSide(color: rose, width: 1.5),
          ),
        ),
        textTheme: GoogleFonts.dmSansTextTheme().copyWith(
          displayLarge: display(32, color: const Color(0xFFE0D8DB)),
          headlineMedium: heading(24, color: const Color(0xFFE0D8DB)),
          titleMedium: heading(16, color: const Color(0xFFE0D8DB)),
          bodyMedium: body(14, color: const Color(0xFFB0A5AB)),
          labelMedium: label(12, color: const Color(0xFFB0A5AB)),
        ),
      );
}

// ── Luxury Button ─────────────────────────────────────────────────────────────

/// Primary luxury button with rose gradient + press animation
class LuxButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool outlined;
  final bool gold;
  final IconData? icon;
  final double height;

  const LuxButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.outlined = false,
    this.gold = false,
    this.icon,
    this.height = 54,
  });

  @override
  State<LuxButton> createState() => _LuxButtonState();
}

class _LuxButtonState extends State<LuxButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = widget.gold ? PP.goldGrad : PP.roseGrad;
    final shadows  = widget.gold ? PP.goldButtonShadow : PP.buttonShadow;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onPressed?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: widget.height,
          decoration: widget.outlined
              ? BoxDecoration(
                  borderRadius: PP.pill,
                  border: Border.all(color: PP.rose, width: 1.5),
                  color: Colors.transparent,
                )
              : BoxDecoration(
                  gradient: widget.isLoading || widget.onPressed == null
                      ? null
                      : gradient,
                  color: widget.isLoading || widget.onPressed == null
                      ? PP.muted.withOpacity(0.3)
                      : null,
                  borderRadius: PP.pill,
                  boxShadow:
                      widget.isLoading || widget.onPressed == null ? [] : shadows,
                ),
          child: Center(
            child: widget.isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.outlined ? PP.rose : Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: 18,
                          color: widget.outlined ? PP.rose : Colors.white,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.label,
                        style: PP.heading(15,
                            color: widget.outlined ? PP.rose : Colors.white,
                            weight: FontWeight.w600),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Luxury Text Field ─────────────────────────────────────────────────────────

class LuxField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? hint;

  const LuxField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.hint,
  });

  @override
  State<LuxField> createState() => _LuxFieldState();
}

class _LuxFieldState extends State<LuxField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: widget.controller,
      obscureText: widget.obscure && !_show,
      keyboardType: widget.keyboardType,
      style: PP.body(15, color: theme.colorScheme.onSurface),
      decoration: PP.input(widget.label, icon: widget.icon, hint: widget.hint)
          .copyWith(
        fillColor: theme.inputDecorationTheme.fillColor,
        enabledBorder: theme.inputDecorationTheme.border,
        suffixIcon: widget.obscure
            ? IconButton(
                icon: Icon(
                  _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: PP.muted,
                  size: 20,
                ),
                onPressed: () => setState(() => _show = !_show),
              )
            : null,
      ),
    );
  }
}

// ── Luxury App Bar ────────────────────────────────────────────────────────────

class LuxAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;

  const LuxAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBack = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppBar(
      backgroundColor: theme.scaffoldBackgroundColor,
      elevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      leading: showBack
          ? GestureDetector(
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
            )
          : null,
      title: Text(title, style: PP.heading(17, color: theme.colorScheme.onSurface)),
      actions: actions,
    );
  }
}

// ── Force Light Mode wrapper ──────────────────────────────────────────────────
/// Wraps any screen in PP.lightTheme regardless of the app's current theme.
/// Use this on profile/settings view screens that should always appear light.
class ForceLightMode extends StatelessWidget {
  final Widget child;
  const ForceLightMode({super.key, required this.child});
  @override
  Widget build(BuildContext context) =>
      Theme(data: PP.lightTheme, child: child);
}

// ── Safety Badge ──────────────────────────────────────────────────────────────

class SafetyBadge extends StatelessWidget {
  final String level;
  final double? score;

  const SafetyBadge({super.key, required this.level, this.score});

  Color get _color {
    final l = level.toLowerCase();
    if (l.contains('high')) return PP.danger;
    if (l.contains('moderate')) return PP.warn;
    return PP.safe;
  }

  Color get _tint {
    final l = level.toLowerCase();
    if (l.contains('high')) return PP.dangerTint;
    if (l.contains('moderate')) return PP.warnTint;
    return PP.safeTint;
  }

  String get _label {
    final l = level.toLowerCase();
    if (l.contains('high')) return 'High Risk';
    if (l.contains('moderate')) return 'Moderate';
    return 'Safe';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? _color.withOpacity(0.18) : _tint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: PP.pill,
        border: Border.all(color: _color.withOpacity(isDark ? 0.4 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(_label,
              style: PP.label(12, color: _color, weight: FontWeight.w600)),
          if (score != null) ...[
            const SizedBox(width: 6),
            Text('${score!.toInt()}',
                style: PP.mono(12, color: _color)),
          ],
        ],
      ),
    );
  }
}

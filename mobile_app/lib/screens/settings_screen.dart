import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../theme_provider.dart';
import '../services/api_service.dart';
import 'welcome_screen.dart';
import 'privacy_screen.dart';
import 'profile_setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _name = '';
  String _username = '';
  bool _notifications = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _name     = prefs.getString('user_name') ?? '';
      _username = prefs.getString('username') ?? '';
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1418) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: PP.r20),
          title: Text('Sign Out', style: PP.heading(18, color: Theme.of(ctx).colorScheme.onSurface)),
          content: Text('Are you sure you want to sign out?',
              style: PP.body(14, color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.7))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: PP.body(14, color: PP.muted)),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(ctx, true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? PP.danger.withOpacity(0.2) : PP.dangerTint,
                  borderRadius: PP.pill,
                  border: Border.all(color: PP.danger.withOpacity(0.3)),
                ),
                child: Text('Sign Out', style: PP.heading(14, color: PP.danger)),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()), (_) => false);
  }

  Future<void> _deleteAccount() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Step 1: warn dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1418) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: PP.r20),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: PP.dangerTint, shape: BoxShape.circle),
          child: const Icon(Icons.delete_forever_outlined, color: PP.danger, size: 28),
        ),
        title: Text('Delete Account?', style: PP.heading(18, color: PP.danger)),
        content: Text(
          'This will permanently delete your account, scan history, saved products, and all your data.\n\nThis cannot be undone.',
          style: PP.body(14, color: isDark ? Colors.white70 : PP.muted),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: PP.body(14, color: PP.muted)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.pop(ctx, true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: PP.danger, borderRadius: PP.pill,
              ),
              child: Text('Yes, Delete', style: PP.heading(14, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Step 2: type DELETE to confirm
    final typeCtrl = TextEditingController();
    final typed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1418) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: PP.r20),
        title: Text('Confirm Deletion', style: PP.heading(17, color: isDark ? Colors.white : PP.ink)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Type DELETE to confirm:', style: PP.body(13, color: isDark ? Colors.white60 : PP.muted)),
          const SizedBox(height: 12),
          TextField(
            controller: typeCtrl,
            autofocus: true,
            style: PP.heading(15, color: PP.danger),
            decoration: PP.input('Type DELETE', icon: Icons.keyboard_outlined).copyWith(
              fillColor: isDark ? const Color(0xFF1A1617) : PP.dangerTint,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: PP.body(14, color: PP.muted))),
          GestureDetector(
            onTap: () => Navigator.pop(ctx, typeCtrl.text.trim() == 'DELETE'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: PP.danger, borderRadius: PP.pill),
              child: Text('Delete', style: PP.heading(14, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
    if (typed != true || !mounted) {
      if (typed == false && typeCtrl.text.trim().isNotEmpty && typeCtrl.text.trim() != 'DELETE') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('You must type DELETE exactly to confirm.', style: PP.body(13, color: Colors.white)),
          backgroundColor: PP.danger, behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: PP.r12),
        ));
      }
      return;
    }

    // Step 3: delete
    try {
      await ApiService.deleteAccount();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()), (_) => false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e', style: PP.body(13, color: Colors.white)),
        backgroundColor: PP.danger, behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: PP.r12),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final isDark    = theme.brightness == Brightness.dark;
    final bg        = isDark ? const Color(0xFF0D0B0C) : PP.bg;
    final textColor = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg, elevation: 0, centerTitle: true,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF261418) : PP.roseTint,
              borderRadius: PP.r8,
              border: Border.all(color: isDark ? const Color(0xFF3D2A30) : PP.border),
            ),
            child: Icon(Icons.arrow_back_ios_new, size: 16, color: textColor),
          ),
        ),
        title: Text('Settings', style: PP.heading(17, color: textColor)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // ── Profile card ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: PP.roseGrad,
              borderRadius: PP.r20,
              boxShadow: PP.buttonShadow,
            ),
            child: Row(children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                ),
                child: const Icon(Icons.person_outline, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_name.isEmpty ? 'Guest User' : _name,
                    style: PP.heading(17, color: Colors.white, weight: FontWeight.w700)),
                if (_username.isNotEmpty)
                  Text('@$_username', style: PP.body(13, color: Colors.white70)),
              ])),
            ]),
          ),
          const SizedBox(height: 24),

          // ── Preferences ──────────────────────────────────────────────
          _SectionLabel('Preferences', isDark: isDark),
          const SizedBox(height: 10),
          _SettingsCard(isDark: isDark, children: [
            ValueListenableBuilder<bool>(
              valueListenable: ThemeProvider.instance,
              builder: (_, dark, __) => _ToggleTile(
                icon: Icons.dark_mode_outlined,
                iconBg: isDark ? const Color(0xFF3D2A52) : const Color(0xFFEDE7F6),
                iconColor: const Color(0xFF7C5CBF),
                label: 'Dark Mode', value: dark, isDark: isDark,
                onChanged: (v) => ThemeProvider.instance.setDark(v),
              ),
            ),
            Divider(color: isDark ? Colors.white10 : PP.border, height: 1),
            _ToggleTile(
              icon: Icons.notifications_outlined,
              iconBg: isDark ? PP.gold.withOpacity(0.15) : PP.goldTint,
              iconColor: PP.gold,
              label: 'Push Notifications', value: _notifications, isDark: isDark,
              onChanged: (v) => setState(() => _notifications = v),
            ),
          ]),

          const SizedBox(height: 20),

          // ── Account ───────────────────────────────────────────────────
          _SectionLabel('Account', isDark: isDark),
          const SizedBox(height: 10),
          _SettingsCard(isDark: isDark, children: [
            _NavTile(
              icon: Icons.person_pin_outlined,
              iconBg: isDark ? PP.rose.withOpacity(0.15) : PP.roseTint,
              iconColor: PP.rose,
              label: 'Edit Health Profile', isDark: isDark,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfileSetupScreen())),
            ),
            Divider(color: isDark ? Colors.white10 : PP.border, height: 1),
            _NavTile(
              icon: Icons.shield_outlined,
              iconBg: isDark ? PP.safe.withOpacity(0.15) : PP.safeTint,
              iconColor: PP.safe,
              label: 'Privacy Policy', isDark: isDark,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PrivacyScreen())),
            ),
          ]),

          const SizedBox(height: 20),

          // ── App info ──────────────────────────────────────────────────
          _SectionLabel('App Info', isDark: isDark),
          const SizedBox(height: 10),
          _SettingsCard(isDark: isDark, children: [
            _InfoTile(
              icon: Icons.info_outline,
              iconBg: isDark ? const Color(0xFF0D2744) : const Color(0xFFE3F2FD),
              iconColor: const Color(0xFF1565C0),
              label: 'Version', value: '1.1.0', isDark: isDark,
            ),
            Divider(color: isDark ? Colors.white10 : PP.border, height: 1),
            _InfoTile(
              icon: Icons.spa_outlined,
              iconBg: isDark ? PP.rose.withOpacity(0.15) : PP.roseTint,
              iconColor: PP.rose,
              label: 'PurePick AI', value: 'Intelligence Edition', isDark: isDark,
            ),
          ]),

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: LuxButton(
              label: 'Sign Out',
              outlined: true,
              icon: Icons.logout_outlined,
              onPressed: _logout,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _deleteAccount,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: isDark ? PP.danger.withOpacity(0.1) : PP.dangerTint,
                  borderRadius: PP.pill,
                  border: Border.all(color: PP.danger.withOpacity(0.4)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.delete_forever_outlined, color: PP.danger, size: 18),
                  const SizedBox(width: 8),
                  Text('Delete Account', style: PP.heading(15, color: PP.danger)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionLabel(this.text, {required this.isDark});
  @override
  Widget build(BuildContext context) =>
      Text(text, style: PP.label(11, color: isDark ? Colors.white38 : PP.muted, weight: FontWeight.w600));
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final bool isDark;
  const _SettingsCard({required this.children, required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
    decoration: PP.card(dark: isDark),
    child: Column(children: children),
  );
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String label;
  final bool value, isDark;
  final ValueChanged<bool> onChanged;
  const _ToggleTile({required this.icon, required this.iconBg, required this.iconColor,
      required this.label, required this.value, required this.isDark, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Container(width: 38, height: 38,
          decoration: BoxDecoration(color: iconBg, borderRadius: PP.r10),
          child: Icon(icon, color: iconColor, size: 18)),
      const SizedBox(width: 14),
      Expanded(child: Text(label,
          style: PP.heading(14, color: Theme.of(context).colorScheme.onSurface))),
      Switch.adaptive(value: value, onChanged: onChanged, activeColor: PP.rose),
    ]),
  );
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _NavTile({required this.icon, required this.iconBg, required this.iconColor,
      required this.label, required this.isDark, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(width: 38, height: 38,
            decoration: BoxDecoration(color: iconBg, borderRadius: PP.r10),
            child: Icon(icon, color: iconColor, size: 18)),
        const SizedBox(width: 14),
        Expanded(child: Text(label,
            style: PP.heading(14, color: Theme.of(context).colorScheme.onSurface))),
        Icon(Icons.chevron_right,
            color: isDark ? Colors.white38 : PP.muted, size: 20),
      ]),
    ),
  );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String label, value;
  final bool isDark;
  const _InfoTile({required this.icon, required this.iconBg, required this.iconColor,
      required this.label, required this.value, required this.isDark});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Container(width: 38, height: 38,
          decoration: BoxDecoration(color: iconBg, borderRadius: PP.r10),
          child: Icon(icon, color: iconColor, size: 18)),
      const SizedBox(width: 14),
      Expanded(child: Text(label,
          style: PP.heading(14, color: Theme.of(context).colorScheme.onSurface))),
      Text(value, style: PP.label(13, color: isDark ? Colors.white38 : PP.muted)),
    ]),
  );
}

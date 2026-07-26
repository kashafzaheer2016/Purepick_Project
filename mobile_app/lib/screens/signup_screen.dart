import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import '../app_router.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameCtrl    = TextEditingController();
  final _userCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading    = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _userCtrl.dispose(); _emailCtrl.dispose();
    _passCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    final name     = _nameCtrl.text.trim();
    final username = _userCtrl.text.trim();
    final email    = _emailCtrl.text.trim();
    final pass     = _passCtrl.text;
    final confirm  = _confirmCtrl.text;

    if (name.isEmpty || username.isEmpty || email.isEmpty || pass.isEmpty) {
      _snack('Please fill in all fields', error: true); return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _snack('Please enter a valid email address', error: true); return;
    }
    if (pass != confirm) {
      _snack('Passwords do not match', error: true); return;
    }
    final pwdError = _validatePassword(pass);
    if (pwdError != null) {
      _snack(pwdError, error: true); return;
    }

    setState(() => _isLoading = true);
    try {
      await ApiService.register(name, username, email, pass);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRouter.profileSetup, (route) => false);
    } catch (e) {
      _snack(e.toString().replaceAll('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Returns an error message or null if valid.
  String? _validatePassword(String pass) {
    if (pass.length < 8) {
      return 'Password must be at least 8 characters long.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(pass)) {
      return 'Password must contain at least one letter (a–z or A–Z).';
    }
    if (!RegExp(r'[0-9]').hasMatch(pass)) {
      return 'Password must contain at least one number (0–9). Special characters are optional.';
    }
    return null;
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: PP.body(13, color: Colors.white)),
      backgroundColor: error ? PP.danger : PP.safe,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: PP.r12),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PP.bg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Container(
              height: 200,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6B3A4A), Color(0xFFB07A8A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.spa_outlined, color: Colors.white, size: 36),
                    const SizedBox(height: 10),
                    Text('Create Account',
                        style: PP.display(26, color: Colors.white, weight: FontWeight.w700)),
                    Text('Join the PurePick community',
                        style: PP.body(14, color: Colors.white70)),
                  ],
                ),
              ),
            ),

            // ── Form ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
              child: Column(
                children: [
                  LuxField(
                    controller: _nameCtrl,
                    label: 'Full Name',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 14),
                  LuxField(
                    controller: _userCtrl,
                    label: 'Username',
                    icon: Icons.alternate_email,
                  ),
                  const SizedBox(height: 14),
                  LuxField(
                    controller: _emailCtrl,
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Used for password recovery and notifications',
                      style: PP.label(11, color: PP.muted),
                    ),
                  ),
                  const SizedBox(height: 14),
                  LuxField(
                    controller: _passCtrl,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    obscure: true,
                  ),
                  const SizedBox(height: 14),
                  LuxField(
                    controller: _confirmCtrl,
                    label: 'Confirm Password',
                    icon: Icons.lock_outline,
                    obscure: true,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: LuxButton(
                      label: 'Create Account',
                      onPressed: _signup,
                      isLoading: _isLoading,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Already have an account? ', style: PP.body(14)),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text('Sign In',
                          style: PP.body(14, color: PP.rose, weight: FontWeight.w600)),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import '../app_router.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
  bool _googleLoading = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '475901765248-ceko722evo5ar2ug44rdup7m3n8or8ko.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  @override
  void dispose() { _userCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty) {
      _snack('Please enter your username and password', error: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ApiService.login(_userCtrl.text.trim(), _passCtrl.text.trim());
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRouter.main, (route) => false);
    } catch (e) {
      _snack(e.toString().replaceAll('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _googleLogin() async {
    setState(() => _googleLoading = true);
    try {
      final user = await _googleSignIn.signIn();
      if (user == null) { setState(() => _googleLoading = false); return; }
      final auth = await user.authentication;
      final token = auth.idToken;
      if (token == null) throw Exception('Google token unavailable. Check serverClientId configuration.');
      final data = await ApiService.loginWithGoogle(token);
      if (!mounted) return;
      // New users go to profile setup, returning users go to main
      final isNew = data['is_new_user'] == true;
      Navigator.pushNamedAndRemoveUntil(
        context,
        isNew ? AppRouter.profileSetup : AppRouter.main,
        (route) => false,
      );
    } catch (e) {
      String msg = 'Google Sign-In failed: $e';
      if (e.toString().contains('ApiException: 10')) {
        msg = 'Google Auth Error (10): Ensure SHA-1 is added in Google Console. Use username/password for now.';
      }
      _snack(msg, error: true);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
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
            // Header
            Container(
              height: 220,
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
                    const Icon(Icons.spa_outlined, color: Colors.white, size: 40),
                    const SizedBox(height: 10),
                    Text('Welcome Back', style: PP.display(28, color: Colors.white, weight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('Sign in to your PurePick account', style: PP.body(14, color: Colors.white70)),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LuxField(controller: _userCtrl, label: 'Username', icon: Icons.person_outline),
                  const SizedBox(height: 16),
                  LuxField(controller: _passCtrl, label: 'Password', icon: Icons.lock_outline, obscure: true),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                      child: Text('Forgot Password?', style: PP.body(13, color: PP.rose, weight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    child: LuxButton(label: 'Sign In', onPressed: _login, isLoading: _isLoading),
                  ),

                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: Divider(color: PP.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text('or continue with', style: PP.label(12)),
                    ),
                    Expanded(child: Divider(color: PP.border)),
                  ]),
                  const SizedBox(height: 20),

                  // Google button
                  GestureDetector(
                    onTap: _googleLoading ? null : _googleLogin,
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        color: PP.surface,
                        borderRadius: PP.pill,
                        border: Border.all(color: PP.border, width: 1.2),
                        boxShadow: PP.softShadow,
                      ),
                      child: Center(
                        child: _googleLoading
                            ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: PP.rose, strokeWidth: 2))
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                Image.network(
                                  'https://www.google.com/favicon.ico',
                                  width: 20, height: 20,
                                  errorBuilder: (_, __, ___) => Icon(Icons.login, color: PP.rose, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Text('Continue with Google', style: PP.heading(14, color: PP.ink)),
                              ]),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text("Don't have an account? ", style: PP.body(14)),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                      child: Text('Sign Up', style: PP.body(14, color: PP.rose, weight: FontWeight.w600)),
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

import 'package:flutter/material.dart';
import '../design/pp.dart';
import '../services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? prefillToken;
  const ForgotPasswordScreen({super.key, this.prefillToken});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _idCtrl      = TextEditingController();
  final _tokenCtrl   = TextEditingController();
  final _newCtrl     = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading   = false;
  bool _tokenSent = false;
  String? _error;
  String _sentTo  = '';

  @override
  void initState() {
    super.initState();
    if (widget.prefillToken != null) {
      _tokenCtrl.text = widget.prefillToken!;
      _tokenSent = true;
    }
  }

  @override
  void dispose() {
    _idCtrl.dispose(); _tokenCtrl.dispose();
    _newCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name   = parts[0];
    final domain = parts[1];
    final masked = name.length <= 2
        ? '${name[0]}***'
        : '${name[0]}${name[1]}***';
    return '$masked@$domain';
  }

  Future<void> _request() async {
    if (_idCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your username or email'); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.requestPasswordReset(_idCtrl.text.trim());
      final input = _idCtrl.text.trim();
      final display = input.contains('@')
          ? _maskEmail(input)
          : 'the email linked to @$input';
      setState(() { _tokenSent = true; _loading = false; _sentTo = display; });
    } catch (e) {
      final msg = e.toString();
      String errMsg;
      if (msg.contains('TimeoutException') || msg.contains('timeout') || msg.contains('SocketException')) {
        errMsg = 'Server is waking up — please try again in a few seconds.';
      } else {
        errMsg = 'Could not send reset email. Please check your username or email and try again.';
      }
      setState(() { _loading = false; _error = errMsg; });
    }
  }

  String? _validatePassword(String pass) {
    if (pass.length < 8) return 'Password must be at least 8 characters long.';
    if (!RegExp(r'[A-Za-z]').hasMatch(pass)) return 'Password must contain at least one letter (a–z or A–Z).';
    if (!RegExp(r'[0-9]').hasMatch(pass)) return 'Password must contain at least one number (0–9). Special characters are optional.';
    return null;
  }

  Future<void> _confirm() async {
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match'); return;
    }
    final pwdError = _validatePassword(_newCtrl.text);
    if (pwdError != null) {
      setState(() => _error = pwdError); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.confirmPasswordReset(_tokenCtrl.text.trim(), _newCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Password reset successfully! Please sign in.', style: PP.body(13, color: Colors.white)),
        backgroundColor: PP.safe,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: PP.r12),
        margin: const EdgeInsets.all(16),
      ));
      Navigator.pop(context);
    } catch (_) {
      setState(() { _loading = false; _error = 'Invalid or expired token. Request a new one.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PP.bg,
      appBar: AppBar(
        backgroundColor: PP.bg, elevation: 0, centerTitle: true,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: PP.roseTint, borderRadius: PP.r8, border: Border.all(color: PP.border)),
            child: Icon(Icons.arrow_back_ios_new, size: 16, color: PP.ink)),
        ),
        title: Text('Reset Password', style: PP.heading(17, color: PP.ink)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Step indicator
          Row(children: [
            _Step('1', done: _tokenSent, active: true),
            Expanded(child: Container(height: 1.5,
                color: _tokenSent ? PP.rose : PP.border)),
            _Step('2', done: false, active: _tokenSent),
          ]),
          const SizedBox(height: 28),

          if (!_tokenSent) ...[
            Text('Enter your username or email and we\'ll send a reset token.',
                style: PP.body(14, color: PP.ink)),
            const SizedBox(height: 20),
            LuxField(controller: _idCtrl, label: 'Username or Email',
                icon: Icons.alternate_email, keyboardType: TextInputType.emailAddress),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: PP.safeTint, borderRadius: PP.r12,
                  border: Border.all(color: PP.safe.withOpacity(0.3))),
              child: Row(children: [
                Icon(Icons.mark_email_read_outlined, color: PP.safe, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reset code sent!', style: PP.heading(13, color: PP.safe)),
                    const SizedBox(height: 2),
                    Text('Check your inbox at $_sentTo and enter the code below.',
                        style: PP.body(12, color: PP.safe)),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 16),
            LuxField(controller: _tokenCtrl, label: 'Reset Token', icon: Icons.key_outlined),
            const SizedBox(height: 14),
            LuxField(controller: _newCtrl, label: 'New Password', icon: Icons.lock_outline, obscure: true),
            const SizedBox(height: 14),
            LuxField(controller: _confirmCtrl, label: 'Confirm Password', icon: Icons.lock_outline, obscure: true),
          ],

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: PP.dangerTint, borderRadius: PP.r12,
                  border: Border.all(color: PP.danger.withOpacity(0.3))),
              child: Row(children: [
                Icon(Icons.error_outline, color: PP.danger, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: PP.body(13, color: PP.danger))),
              ]),
            ),
          ],

          const SizedBox(height: 28),
          SizedBox(width: double.infinity,
            child: LuxButton(
              label: _tokenSent ? 'Reset Password' : 'Send Reset Token',
              onPressed: _tokenSent ? _confirm : _request,
              isLoading: _loading,
            ),
          ),

          if (_tokenSent) ...[
            const SizedBox(height: 16),
            Center(child: GestureDetector(
              onTap: () => setState(() { _tokenSent = false; _error = null; }),
              child: Text("Didn't receive a token? Try again",
                  style: PP.body(13, color: PP.muted, weight: FontWeight.w500)),
            )),
          ],
        ]),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final bool active, done;
  const _Step(this.number, {required this.active, required this.done});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        gradient: active ? PP.roseGrad : null,
        color: active ? null : PP.border,
        shape: BoxShape.circle,
      ),
      child: Center(child: done
          ? const Icon(Icons.check, color: Colors.white, size: 16)
          : Text(number, style: PP.heading(14, color: active ? Colors.white : PP.muted))),
    );
  }
}

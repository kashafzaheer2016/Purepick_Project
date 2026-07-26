import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // INITIALIZED WITH YOUR CLIENT ID
  // UPDATED: Use the WEB CLIENT ID for serverClientId to get the idToken.
  // Do NOT use the Android Client ID here.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // Android Client ID (type 1)
    clientId: '246071274413-62pbvb1no6cpopp3r70olhg07pitcjun.apps.googleusercontent.com',
    // Web Client ID (type 3)
    serverClientId: '246071274413-f4vi28rg12rg8sheakec85u7pmgc7dmr.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // FIXING THE ERROR: Call the new method in ApiService
      final response = await ApiService.loginWithGoogle(googleAuth.idToken);

      final prefs = await SharedPreferences.getInstance();
      
      // Robust ID storage
      final userId = response['user_id'];
      if (userId is int) {
        await prefs.setInt('user_id', userId);
      } else if (userId is String) {
        await prefs.setInt('user_id', int.tryParse(userId) ?? 0);
      }
      await prefs.setString('user_name', googleUser.displayName ?? "User");

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Google Error: $error")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 80),
            const Icon(Icons.verified_user, size: 80, color: Colors.green),
            const SizedBox(height: 24),
            const Text(
              "Welcome Back",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            // USERNAME FIELD
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: "Username",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 24),

            // SIGN IN BUTTON
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        setState(() => _isLoading = true);
                        try {
                          final response = await ApiService.login(
                            _usernameController.text.trim(),
                            _passwordController.text.trim(),
                          );

                          if (!mounted) return;

                          final prefs = await SharedPreferences.getInstance();
                          // Safely handle user_id as int or String
                          final userId = response['user_id'];
                          if (userId is int) {
                            await prefs.setInt('user_id', userId);
                          } else if (userId is String) {
                            await prefs.setInt(
                              'user_id',
                              int.tryParse(userId) ?? 0,
                            );
                          }

                          await prefs.setString(
                            'user_name',
                            response['name'] ?? "User",
                          );

                          // SUCCESS: Go to Home
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const HomeScreen(),
                            ),
                          );
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.red,
                                content: Text(e.toString().replaceAll('Exception: ', '')),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text(
                  "SIGN IN",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Text("OR"),
            const SizedBox(height: 16),

            // GOOGLE SIGN IN BUTTON
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.login, color: Colors.red),
                label: const Text(
                  "Sign in with Google",
                  style: TextStyle(color: Colors.black),
                ),
                onPressed: _handleGoogleSignIn,
              ),
            ),

            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SignupScreen()),
              ),
              child: const Text("Don't have an account? Sign Up"),
            ),
          ],
        ),
      ),
    );
  }
}

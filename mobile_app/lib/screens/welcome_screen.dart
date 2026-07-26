import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import 'login_screen.dart';
import '../app_router.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _checkLogin();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  Future<void> _checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt('user_id') != null) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/main');
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6B3A4A), Color(0xFF8A5060), Color(0xFFB07A8A)],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
  
                      // Logo mark
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.15),
                          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                        ),
                        child: const Icon(Icons.spa_outlined, color: Colors.white, size: 44),
                      ),
                      const SizedBox(height: 28),
  
                      // Brand name
                      Text(
                        'PurePick',
                        style: PP.display(42, color: Colors.white, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Ingredient Intelligence',
                        style: PP.body(15, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
  
                      const Spacer(flex: 1),
  
                      // Features
                      ...[
                        _Feature(Icons.auto_awesome_outlined, 'AI-Powered Analysis',
                            'Instantly decode every ingredient in your beauty products'),
                        const SizedBox(height: 20),
                        _Feature(Icons.shield_outlined, 'Personalised Safety',
                            'Alerts tailored to your unique skin profile and allergies'),
                        const SizedBox(height: 20),
                        _Feature(Icons.face_retouching_natural, 'Skin Intelligence',
                            'AI skin type and condition detection with expert recommendations'),
                      ],
  
                      const Spacer(flex: 2),
  
                      // CTA
                      SizedBox(
                        width: double.infinity,
                        child: LuxButton(
                          label: 'Begin Your Journey',
                          gold: true,
                          height: 58,
                          onPressed: () => Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (_, a, __) => const LoginScreen(),
                              transitionDuration: const Duration(milliseconds: 400),
                              transitionsBuilder: (_, a, __, child) => FadeTransition(
                                opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Feature(this.icon, this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: PP.heading(14, color: Colors.white, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: PP.body(13, color: Colors.white70)),
            ],
          ),
        ),
      ],
    );
  }
}

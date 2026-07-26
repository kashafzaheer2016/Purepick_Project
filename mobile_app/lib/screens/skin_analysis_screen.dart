import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import '../services/task_poller.dart';
import 'skin_result_screen.dart';

class SkinAnalysisScreen extends StatefulWidget {
  const SkinAnalysisScreen({super.key});
  @override
  State<SkinAnalysisScreen> createState() => _SkinAnalysisScreenState();
}

class _SkinAnalysisScreenState extends State<SkinAnalysisScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isBusy = false;
  bool _useFront = true;
  String _analysisStatus = 'Analysing your skin…';

  late AnimationController _pulseCtrl;
  late AnimationController _scanCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _pulseAnim;
  late Animation<double> _scanAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _scanCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _scanAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _scanCtrl, curve: Curves.linear));
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));

    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseCtrl.dispose();
    _scanCtrl.dispose();
    _fadeCtrl.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      cam.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    CameraDescription selected = cameras.first;
    for (final c in cameras) {
      if (_useFront && c.lensDirection == CameraLensDirection.front) {
        selected = c;
        break;
      }
      if (!_useFront && c.lensDirection == CameraLensDirection.back) {
        selected = c;
        break;
      }
    }
    final ctrl = CameraController(selected, ResolutionPreset.high, enableAudio: false);
    try {
      await ctrl.initialize();
      await ctrl.setFocusMode(FocusMode.auto);
      if (mounted) {
        await _cameraController?.dispose();
        setState(() => _cameraController = ctrl);
        _fadeCtrl.forward();
      } else {
        ctrl.dispose();
      }
    } catch (e) {
      debugPrint('Camera error: $e');
      ctrl.dispose();
    }
  }

  Future<void> _captureAndAnalyze() async {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized || _isBusy) return;

    setState(() {
      _isBusy = true;
      _analysisStatus = 'Uploading selfie...';
    });

    try {
      final img = await cam.takePicture();
      await cam.pausePreview();
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;

      // Step 1: Enqueue task
      setState(() => _analysisStatus = 'Queuing analysis...');
      final enqueueResponse = await ApiService.analyzeFace(img.path, userId);
      final taskId = enqueueResponse['task_id'] as String?;
      if (taskId == null) throw Exception('No task ID returned.');

      // Step 2: Poll with live status
      final result = await TaskPoller.poll(
        taskId,
        onProgress: (status) {
          if (!mounted) return;
          setState(() {
            _analysisStatus = switch (status) {
              'PENDING' => 'Waiting in queue...',
              'STARTED' => 'AI is working its magic',
              'RETRY'   => 'Retrying...',
              _         => 'Analysing your skin…',
            };
          });
        },
      );

      if (!mounted) return;
      await Navigator.push(context, _premiumRoute(SkinResultScreen(result: result)));
      if (mounted) {
        _cameraController?.resumePreview();
        _fadeCtrl.reset();
        _fadeCtrl.forward();
      }
    } on TaskFailedException catch (e) {
      if (mounted) {
        _showErr(e.message);
        _cameraController?.resumePreview();
      }
    } on SkinAnalysisApiException catch (e) {
      if (mounted) {
        _showErr(e.message);
        _cameraController?.resumePreview();
      }
    } catch (e) {
      if (mounted) {
        _showErr('Analysis failed. Try again.');
        _cameraController?.resumePreview();
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  PageRoute _premiumRoute(Widget page) => PageRouteBuilder(
        pageBuilder: (_, a, __) => page,
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, a, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.07), end: Offset.zero)
                .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
            child: child,
          ),
        ),
      );

  void _showErr(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(
            child: Text(msg,
                style: GoogleFonts.poppins(color: Colors.white))),
      ]),
      backgroundColor: const Color(0xFFE53935),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ready = _cameraController?.value.isInitialized == true;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
                color: Colors.black38, shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Skin Analysis',
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                  color: Colors.black38, shape: BoxShape.circle),
              child: const Icon(Icons.flip_camera_ios_outlined,
                  color: Colors.white, size: 20),
            ),
            onPressed: () async {
              setState(() => _useFront = !_useFront);
              _fadeCtrl.reset();
              await _initCamera();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(children: [
        if (!ready)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF0D1117), Color(0xFF1A1F2E)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter),
            ),
          )
        else
          FadeTransition(
              opacity: _fadeAnim,
              child: SizedBox.expand(child: CameraPreview(_cameraController!))),

        // Vignette
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
            ),
          ),
        ),

        // Face oval guide
        Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulseAnim, _scanAnim]),
            builder: (_, __) => Transform.scale(
              scale: _isBusy ? 1.0 : _pulseAnim.value,
              child: SizedBox(
                width: 230,
                height: 290,
                child: CustomPaint(
                  painter: _OvalScannerPainter(
                    scanProgress: _isBusy ? 0 : _scanAnim.value,
                    isBusy: _isBusy,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Hint
        Positioned(
          top: MediaQuery.of(context).padding.top + 80,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedOpacity(
              opacity: _isBusy ? 0 : 1,
              duration: const Duration(milliseconds: 400),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text('Position your face inside the oval',
                    style: GoogleFonts.poppins(
                        color: Colors.white70, fontSize: 13)),
              ),
            ),
          ),
        ),

        // Tips
        Positioned(
          bottom: 160,
          left: 16,
          right: 16,
          child: AnimatedOpacity(
            opacity: _isBusy ? 0 : 1,
            duration: const Duration(milliseconds: 400),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                _TipBadge(icon: Icons.wb_sunny_outlined, label: 'Good light'),
                _TipBadge(icon: Icons.remove_red_eye_outlined, label: 'Eyes open'),
                _TipBadge(icon: Icons.face_outlined, label: 'Clean face'),
              ],
            ),
          ),
        ),

        // Capture / loading
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 50),
            child:
                _isBusy ? _buildLoadingIndicator() : _buildCaptureButton(),
          ),
        ),
      ]),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _captureAndAnalyze,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) => Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: PP.rose
                    .withOpacity(0.5 * _pulseAnim.value),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: PP.roseGrad,
            ),
            child: const Icon(Icons.face_retouching_natural,
                color: Colors.white, size: 36),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 84,
          height: 84,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
                color: PP.rose, strokeWidth: 3),
            const Icon(Icons.face_retouching_natural,
                color: Colors.white, size: 34),
          ]),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _analysisStatus,
              key: ValueKey(_analysisStatus),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('AI is working its magic',
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}

// ── Oval scanner painter (unchanged from original) ────────────────────────────
class _OvalScannerPainter extends CustomPainter {
  final double scanProgress;
  final bool isBusy;
  _OvalScannerPainter({required this.scanProgress, required this.isBusy});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final ovalPath = Path()..addOval(rect);

    canvas.drawOval(
        rect,
        Paint()
          ..color = PP.rose.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    canvas.drawOval(
        rect,
        Paint()
          ..color = PP.rose
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    _drawCornerArcs(canvas, rect);

    if (!isBusy) {
      final scanY = rect.top + rect.height * scanProgress;
      canvas.save();
      canvas.clipPath(ovalPath);
      canvas.drawRect(
          Rect.fromLTWH(0, scanY - 20, size.width, 40),
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.transparent,
                PP.rose.withOpacity(0.7),
                Colors.transparent
              ],
              stops: const [0, 0.5, 1],
            ).createShader(Rect.fromLTWH(0, scanY - 20, size.width, 40)));
      canvas.restore();
    }
  }

  void _drawCornerArcs(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const arcLen = 0.4;
    final corners = <List<dynamic>>[
      [rect.topLeft, math.pi],
      [rect.topRight, math.pi * 1.5],
      [rect.bottomRight, 0.0],
      [rect.bottomLeft, math.pi * 0.5],
    ];
    for (final c in corners) {
      canvas.drawArc(
          Rect.fromCenter(
              center: c[0] as Offset, width: 36, height: 36),
          c[1] as double,
          arcLen,
          false,
          paint);
    }
  }

  @override
  bool shouldRepaint(_OvalScannerPainter old) =>
      old.scanProgress != scanProgress || old.isBusy != isBusy;
}

class _TipBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TipBadge({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: PP.rose, size: 14),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.poppins(
                  color: Colors.white70, fontSize: 11)),
        ]),
      );
}

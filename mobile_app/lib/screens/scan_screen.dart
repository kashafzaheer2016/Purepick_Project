import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import '../services/task_poller.dart';
import 'result_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isBusy = false;
  bool _isFlashOn = false;
  String _statusMessage = 'Analyzing Ingredients...';

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras[0], ResolutionPreset.high, enableAudio: false);
    try {
      await _controller!.initialize();
      await _controller!.setFocusMode(FocusMode.auto);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }
  }

  // ── Core: analyse any image path (camera capture or gallery pick) ────────────

  Future<void> _analyzeFromPath(String imagePath) async {
    setState(() => _isBusy = true);
    try {
      final prefs  = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;

      // Step 1: Upload + enqueue OCR task
      setState(() => _statusMessage = 'Uploading label...');
      final enqueueResponse = await ApiService.analyzeLabelImage(imagePath, userId);
      final taskId = enqueueResponse['task_id'] as String?;

      if (taskId == null) {
        throw Exception('Server did not return a task ID.');
      }

      // Step 2: Poll until complete
      setState(() => _statusMessage = 'Running OCR...');
      final result = await TaskPoller.poll(
        taskId,
        onProgress: (status) {
          if (!mounted) return;
          setState(() {
            _statusMessage = switch (status) {
              'PENDING' => 'Waiting in queue...',
              'STARTED' => 'Analyzing ingredients...',
              'RETRY'   => 'Retrying...',
              _         => 'Processing...',
            };
          });
        },
      );

      if (!mounted) return;

      // Step 3: Parse result
      final totalScore      = (result['overall_score'] ?? 0).toDouble();
      final riskBand        = result['risk']?['risk_band'] ?? 'Safe';
      final aiInsight       = result['ai_insight'] ?? '';
      final personalWarnings = result['personal_warnings'] ?? '';
      final scanId          = result['scan_id'] as int?;

      final alerts     = result['allergy_result']?['allergy_alerts'] as List<dynamic>? ?? [];
      final dangerItems = alerts.map<Map<String, dynamic>>((item) => {
        'name':        item['ingredient'] ?? item['common_name'] ?? 'Unknown',
        'reason':      item['matched_concern'] ?? item['plain_explanation'] ?? '',
        'hazard_level': item['severity'] ?? 'Warning',
        'score':        item['score'],
      }).toList();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            score:            totalScore.clamp(0, 100).toDouble(),
            riskLevel:        riskBand.toString(),
            dangerItems:      dangerItems,
            aiInsight:        aiInsight,
            personalWarnings: personalWarnings,
            scanId:           scanId,
          ),
        ),
      );

    } on TaskFailedException catch (e) {
      if (mounted) {
        _controller?.resumePreview();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red[700]),
        );
      }
    } catch (e) {
      if (mounted) {
        _controller?.resumePreview();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ── Camera capture ───────────────────────────────────────────────────────────

  Future<void> _captureAndAnalyze() async {
    if (_controller == null || !_controller!.value.isInitialized || _isBusy) return;
    setState(() => _statusMessage = 'Capturing image...');

    try {
      final image = await _controller!.takePicture();
      await _controller!.pausePreview();
      if (!mounted) return;
      await _analyzeFromPath(image.path);
    } catch (e) {
      if (mounted) {
        _controller?.resumePreview();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture error: $e')),
        );
        setState(() => _isBusy = false);
      }
    }
  }

  // ── Gallery picker ───────────────────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    if (_isBusy) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (picked == null) return;   // user cancelled
      if (!mounted) return;

      setState(() => _statusMessage = 'Preparing image...');
      // Pause camera preview to save resources while processing gallery image
      await _controller?.pausePreview();
      await _analyzeFromPath(picked.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open gallery: $e')),
        );
        setState(() => _isBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Scan Label', style: PP.heading(18, color: Colors.white)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SizedBox.expand(child: CameraPreview(_controller!)),

          // Vignette
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
              ),
            ),
          ),

          // Scan target guide box
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    border: Border.all(color: PP.rose, width: 2.5),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: PP.rose.withOpacity(0.2), blurRadius: 20, spreadRadius: 2),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text('Position ingredient list inside the box',
                      style: PP.body(12, color: Colors.white70)),
                ),
              ],
            ),
          ),

          // Flash toggle
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                    child: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 22),
                  ),
                  onPressed: () {
                    setState(() => _isFlashOn = !_isFlashOn);
                    _controller!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
                  },
                ),
              ),
            ),
          ),

          // ── Bottom controls: Gallery | Capture button ──────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 52),
              child: _isBusy
                  ? const SizedBox.shrink()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Gallery picker button
                        GestureDetector(
                          onTap: _pickFromGallery,
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white38, width: 1.5),
                            ),
                            child: const Icon(Icons.photo_library_outlined,
                                color: Colors.white, size: 26),
                          ),
                        ),
                        const SizedBox(width: 40),
                        // Capture button
                        GestureDetector(
                          onTap: _captureAndAnalyze,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              boxShadow: [
                                BoxShadow(
                                    color: PP.rose.withOpacity(0.3),
                                    blurRadius: 20,
                                    spreadRadius: 5),
                              ],
                            ),
                            child: Container(
                              margin: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: PP.roseGrad,
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 32),
                            ),
                          ),
                        ),
                        // Placeholder to balance the row
                        const SizedBox(width: 94),
                      ],
                    ),
            ),
          ),

          // Gallery label
          if (!_isBusy)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 6),
                  Text('Gallery', style: PP.label(10, color: Colors.white60)),
                  const SizedBox(width: 130),   // aligned under gallery button
                ],
              ),
            ),

          // Loading overlay
          if (_isBusy)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 80, height: 80,
                      child: CircularProgressIndicator(color: PP.rose, strokeWidth: 3),
                    ),
                    const SizedBox(height: 32),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _statusMessage,
                        key: ValueKey(_statusMessage),
                        style: PP.heading(18, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('AI is identifying ingredients...',
                        style: PP.body(13, color: Colors.white60)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

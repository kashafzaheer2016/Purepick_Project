import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/task_poller.dart';
import 'result_screen.dart';

/// Intermediate loading screen shown while OCR + analysis runs.
/// Enqueues the task, then polls until complete, then navigates to ResultScreen.
class AnalysisScreen extends StatefulWidget {
  final String imagePath;
  const AnalysisScreen({super.key, required this.imagePath});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  bool _isError = false;
  String _errorMessage = 'Analysis failed. Please try again.';
  String _statusMessage = 'Uploading image...';

  @override
  void initState() {
    super.initState();
    _startAiAnalysis();
  }

  Future<void> _startAiAnalysis() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;

      // Step 1: Enqueue — immediate 202 response
      _setStatus('Uploading label...');
      final enqueueResponse =
          await ApiService.analyzeLabelImage(widget.imagePath, userId);
      final taskId = enqueueResponse['task_id'] as String?;

      if (taskId == null) throw Exception('Server did not return a task ID.');

      // Step 2: Poll with live status updates
      _setStatus('Running OCR...');
      final results = await TaskPoller.poll(
        taskId,
        onProgress: (status) {
          _setStatus(switch (status) {
            'PENDING' => 'Waiting in queue...',
            'STARTED' => 'Analyzing ingredients...',
            'RETRY'   => 'Retrying...',
            _         => 'Processing...',
          });
        },
      );

      if (!mounted) return;

      // Step 3: Parse result
      final riskData = results['risk'] ?? {};
      final allergyData = results['allergy_result'] ?? {};
      final totalScore = (results['overall_score'] ?? 0).toDouble();
      final riskLevel = (riskData['risk_band'] ?? 'Safe').toString();
      final verdict = (allergyData['overall_verdict'] ?? '').toString();

      final List alerts = allergyData['allergy_alerts'] ?? [];
      final personalWarnings = alerts.isNotEmpty
          ? alerts.map((e) => '• ${e['plain_explanation'] ?? e['matched_concern'] ?? 'Allergy warning'}').join('\n\n')
          : '✅ This product appears safe based on your profile.';

      final List breakdown = results['ingredient_breakdown'] ?? [];
      final flaggedOnly = breakdown.where((e) => e['flagged'] == true).map<Map<String, dynamic>>((e) => {
        'name': (e['common_name'] ?? e['raw_ingredient'] ?? 'Unknown').toString(),
        'severity': (e['severity'] ?? 'MODERATE').toString(),
        'reason': (e['explanation'] ?? '').toString(),
      }).toList();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            score: totalScore.clamp(0, 100).toDouble(),
            riskLevel: riskLevel,
            dangerItems: flaggedOnly,
            aiInsight: verdict.isNotEmpty ? verdict : (results['ai_insight'] ?? '').toString(),
            personalWarnings: personalWarnings,
            productName: (results['product_name'] ?? 'Analyzed Product').toString(),
            scanId: results['scan_id'] as int?,
          ),
        ),
      );
    } on TaskFailedException catch (e) {
      if (mounted) setState(() { _isError = true; _errorMessage = e.message; });
    } catch (e) {
      debugPrint('Analysis Error: $e');
      if (mounted) setState(() => _isError = true);
    }
  }

  void _setStatus(String msg) {
    if (mounted) setState(() => _statusMessage = msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isError) ...[
                const CircularProgressIndicator(
                    color: Color(0xFF00C897), strokeWidth: 5),
                const SizedBox(height: 30),
                Text(
                  'Analyzing Product...',
                  style: GoogleFonts.poppins(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _statusMessage,
                    key: ValueKey(_statusMessage),
                    textAlign: TextAlign.center,
                    style:
                        GoogleFonts.poppins(color: Colors.grey, fontSize: 13),
                  ),
                ),
              ] else ...[
                const Icon(Icons.cloud_off, color: Colors.red, size: 60),
                const SizedBox(height: 20),
                Text('Analysis Failed',
                    style:
                        GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 12),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C897)),
                  child: const Text('Go Back',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

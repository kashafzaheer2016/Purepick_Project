import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import '../services/task_poller.dart';

class AiTipsScreen extends StatefulWidget {
  const AiTipsScreen({super.key});
  @override
  State<AiTipsScreen> createState() => _AiTipsScreenState();
}

class _AiTipsScreenState extends State<AiTipsScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() { super.initState(); _future = _load(); }

  Future<List<dynamic>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getInt('user_id');
    if (uid == null) return [];
    final res = await ApiService.getAiTips(uid);
    final taskId = res is Map ? res['task_id'] as String? : null;
    if (taskId == null) return [];
    final result = await TaskPoller.poll(taskId);
    return (result['tips'] as List<dynamic>?) ?? [];
  }

  Color _sevColor(String? sev) {
    switch (sev?.toLowerCase()) {
      case 'high':   return PP.danger;
      case 'medium': return PP.warn;
      default:       return PP.safe;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: LuxAppBar(title: 'Personalised Tips'),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: PP.rose, strokeWidth: 2),
              const SizedBox(height: 16),
              Text('Analysing your profile...', style: PP.body(14, color: theme.colorScheme.onSurface)),
            ]));
          if (!snap.hasData || snap.data!.isEmpty)
            return Center(child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF261A1F) : PP.roseTint, 
                    borderRadius: PP.r20,
                  ),
                  child: Icon(Icons.auto_awesome_outlined, color: PP.roseLt, size: 34)),
                const SizedBox(height: 16),
                Text('No tips yet', style: PP.heading(16, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 6),
                Text('Complete more scans to get personalised beauty tips', style: PP.body(13), textAlign: TextAlign.center),
              ]),
            ));
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            itemCount: snap.data!.length,
            itemBuilder: (_, i) {
              final tip = snap.data![i];
              final color = _sevColor(tip['severity']?.toString());
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: PP.card(),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 5,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(tip['title'] ?? 'Tip',
                                  style: PP.heading(14, color: theme.colorScheme.onSurface))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: PP.pill,
                                ),
                                child: Text(tip['category'] ?? '',
                                    style: PP.label(10, color: color, weight: FontWeight.w600)),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Text(tip['body'] ?? '', style: PP.body(13, color: theme.colorScheme.onSurface).copyWith(height: 1.5)),
                            if (tip['related_ingredient'] != null && tip['related_ingredient'] != 'null') ...[
                              const SizedBox(height: 10),
                              Row(children: [
                                Icon(Icons.science_outlined, size: 13, color: PP.muted),
                                const SizedBox(width: 5),
                                Text('Watch: ${tip['related_ingredient']}',
                                    style: PP.label(11, color: PP.muted)),
                              ]),
                            ],
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

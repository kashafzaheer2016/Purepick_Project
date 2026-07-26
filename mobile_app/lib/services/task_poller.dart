import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// Polls /api/task/<task_id>/ until the task completes or times out.
///
/// Usage:
///   final result = await TaskPoller.poll(taskId);
///
/// Polling interval: 1.5s
/// Timeout: 120s (matches Celery TASK_TIME_LIMIT)
class TaskPoller {
  static const Duration _interval = Duration(seconds: 2);
  static const Duration _timeout = Duration(seconds: 300); // 5 min — covers cold-start model load

  /// Poll until SUCCESS or FAILURE.
  /// Calls [onProgress] with status string on each tick.
  /// Returns the result map on success.
  /// Throws [TaskFailedException] on failure or timeout.
  static Future<Map<String, dynamic>> poll(
    String taskId, {
    void Function(String status)? onProgress,
  }) async {
    final deadline = DateTime.now().add(_timeout);

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(_interval);

      final response = await _fetchStatus(taskId);
      final status = response['status'] as String? ?? 'UNKNOWN';

      onProgress?.call(status);

      switch (status) {
        case 'SUCCESS':
          final result = response['result'];
          if (result == null) throw TaskFailedException('Task succeeded but returned no result.');
          return Map<String, dynamic>.from(result as Map);

        case 'FAILURE':
          throw TaskFailedException(
            response['error'] as String? ?? 'Task failed.',
          );

        case 'PENDING':
        case 'STARTED':
        case 'RETRY':
          continue; // keep polling

        default:
          continue;
      }
    }

    throw TaskFailedException('Analysis timed out. The server may be busy — please try again.');
  }

  static Future<Map<String, dynamic>> _fetchStatus(String taskId) async {
    try {
      final headers = await ApiService.authHeaders();
      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/task/$taskId/'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      // Non-200 — treat as still pending
      return {'status': 'PENDING'};
    } catch (_) {
      return {'status': 'PENDING'};
    }
  }
}

class TaskFailedException implements Exception {
  final String message;
  const TaskFailedException(this.message);
  @override
  String toString() => message;
}

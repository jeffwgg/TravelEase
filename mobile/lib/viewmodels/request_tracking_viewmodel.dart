import 'package:flutter/material.dart';
import '../models/repositories/assistance_repository.dart';
import '../services/live_location_service.dart';

class RequestTrackingViewModel extends ChangeNotifier {
  final AssistanceRepository _repository = AssistanceRepository();

  List<Map<String, dynamic>> requests = [];
  bool isLoading = false;
  String? errorMessage;
  bool _isDisposed = false;

  // Accessibility reports state (FR-M5-28)
  List<Map<String, dynamic>> accessibilityReports = [];
  bool isLoadingReports = false;
  String? reportsErrorMessage;

  // Tracks which requests need resolution confirmation (status just changed to resolved)
  Set<String> pendingResolution = <String>{};

  Future<void> loadRequests() async {
    isLoading = true;
    errorMessage = null;
    _notify();

    try {
      final result = await _repository.getAssistanceRequests();
      // Detect any newly resolved requests that haven't been confirmed
      final activeTrackingId = LiveLocationService.instance.activeSessionId;
      for (final r in result) {
        final status = r['status'] as String? ?? '';
        final outcome = r['resolution_outcome'];
        final id = r['id']?.toString() ?? '';
        if (status == 'resolved' && outcome == null && id.isNotEmpty) {
          pendingResolution.add(id);
        }
        // If staff marked the active request as resolved, closed or cancelled, stop GPS stream
        if (activeTrackingId != null && id == activeTrackingId) {
          if (status == 'resolved' || status == 'closed' || status == 'cancelled') {
            LiveLocationService.instance.stop();
          }
        }
      }
      requests = result;
      isLoading = false;
      _notify();
    } catch (e) {
      isLoading = false;
      errorMessage = 'Failed to load requests: $e';
      _notify();
    }
  }

  Future<void> loadAccessibilityReports() async {
    isLoadingReports = true;
    reportsErrorMessage = null;
    _notify();

    try {
      final result = await _repository.getUserAccessibilityReports();
      accessibilityReports = result;
      isLoadingReports = false;
      _notify();
    } catch (e) {
      isLoadingReports = false;
      reportsErrorMessage = 'Failed to load reports: $e';
      _notify();
    }
  }

  Future<void> loadAll() async {
    await Future.wait([
      loadRequests(),
      loadAccessibilityReports(),
    ]);
  }

  // FR-M5-29: Cancel a request
  Future<bool> cancelRequest(String requestId) async {
    final success = await _repository.cancelRequest(requestId);
    if (success) {
      if (LiveLocationService.instance.activeSessionId == requestId) {
        await LiveLocationService.instance.stop();
      }
      await loadRequests();
    }
    return success;
  }

  /// User-initiated resolve for in-person requests.
  Future<bool> resolveRequest(String requestId) async {
    final success = await _repository.resolveRequest(requestId);
    if (success) {
      if (LiveLocationService.instance.activeSessionId == requestId) {
        await LiveLocationService.instance.stop();
      }
      await loadRequests();
    }
    return success;
  }

  // FR-M5-16 / FR-M5-26: Submit resolution outcome + rating
  Future<bool> submitResolutionFeedback({
    required String requestId,
    required String outcome,
    required int rating,
    String? comment,
  }) async {
    final success = await _repository.submitResolutionFeedback(
      requestId: requestId,
      outcome: outcome,
      rating: rating,
      comment: comment,
    );
    if (success) {
      pendingResolution.remove(requestId);
      if (outcome == 'fully_resolved' &&
          LiveLocationService.instance.activeSessionId == requestId) {
        await LiveLocationService.instance.stop();
      }
      await loadRequests();
    }
    return success;
  }

  // Whether a cancel button should appear for this status
  bool isCancellable(String status) {
    final s = status.toLowerCase();
    return s == 'pending' || s == 'assigned' || s == 'in_progress';
  }

  String getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'assigned':
        return 'Assigned';
      case 'in_progress':
        return 'In Progress';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'assigned':
        return const Color(0xFF6366F1);
      case 'in_progress':
        return const Color(0xFFF59E0B);
      case 'resolved':
        return const Color(0xFF10B981);
      case 'closed':
        return const Color(0xFF94A3B8);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  String getBarrierStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'reported':
        return 'Reported';
      case 'investigating':
      case 'in_progress':
        return 'Investigating';
      case 'resolved':
        return 'Resolved';
      default:
        return status;
    }
  }

  Color getBarrierStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'reported':
        return const Color(0xFF3B82F6);
      case 'investigating':
      case 'in_progress':
        return const Color(0xFFF59E0B);
      case 'resolved':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  String getIssueTypeLabel(String issueType) {
    switch (issueType.toLowerCase()) {
      case 'visual':
        return 'No Visual Announcement';
      case 'queue':
        return 'Sound-Only Queue';
      case 'sign':
        return 'No Sign Language';
      case 'alert':
        return 'Missing Visual Alert';
      case 'access':
        return 'Inaccessible Area';
      case 'other':
        return 'Other Issue';
      default:
        return issueType;
    }
  }

  bool isActive(String status) {
    final s = status.toLowerCase();
    return s == 'pending' || s == 'assigned' || s == 'in_progress';
  }

  String getTimeAgo(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final date = DateTime.parse(createdAt);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      if (diff.inHours < 24) return '${diff.inHours} hrs ago';
      if (diff.inDays == 1) return 'Yesterday';
      return '${diff.inDays} days ago';
    } catch (_) {
      return '';
    }
  }

  int getTimelineStep(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 0;
      case 'assigned':
        return 1;
      case 'in_progress':
        return 2;
      case 'resolved':
      case 'closed':
        return 3;
      default:
        return 0;
    }
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

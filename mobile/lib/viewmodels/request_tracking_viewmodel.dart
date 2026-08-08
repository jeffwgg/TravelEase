import 'package:flutter/material.dart';
import '../models/repositories/assistance_repository.dart';

class RequestTrackingViewModel extends ChangeNotifier {
  final AssistanceRepository _repository = AssistanceRepository();

  List<Map<String, dynamic>> requests = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> loadRequests() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.getAssistanceRequests();
      requests = result;
      isLoading = false;
      notifyListeners();
    } catch (e) {
      isLoading = false;
      errorMessage = 'Failed to load requests: $e';
      notifyListeners();
    }
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
      default:
        return status;
    }
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF59E0B); // secondary/amber
      case 'assigned':
        return const Color(0xFF6366F1); // accent/indigo
      case 'in_progress':
        return const Color(0xFFF59E0B); // secondary/amber
      case 'resolved':
        return const Color(0xFF10B981); // success/green
      case 'closed':
        return const Color(0xFF94A3B8); // textMuted
      default:
        return const Color(0xFF94A3B8);
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
        return 3;
      case 'closed':
        return 3;
      default:
        return 0;
    }
  }
}

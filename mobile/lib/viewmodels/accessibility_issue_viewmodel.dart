import 'dart:math';
import 'package:flutter/material.dart';
import '../models/repositories/assistance_repository.dart';

class AccessibilityIssueViewModel extends ChangeNotifier {
  final AssistanceRepository _repository = AssistanceRepository();

  // Form state
  String? issueType;
  int severity = 1;
  final TextEditingController locationController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  // Submission state
  bool isSubmitting = false;
  String? errorMessage;
  bool isSubmitted = false;

  void setIssueType(String? value) {
    issueType = value;
    notifyListeners();
  }

  void setSeverity(int value) {
    severity = value;
    notifyListeners();
  }

  String get severityLabel {
    switch (severity) {
      case 0:
        return 'minor';
      case 2:
        return 'severe';
      default:
        return 'moderate';
    }
  }

  String _generateReportCode() {
    final random = Random();
    final code = 1000 + random.nextInt(9000);
    return 'RPT-$code';
  }

  Future<bool> submitReport({required String venueName}) async {
    if (issueType == null) {
      errorMessage = 'Please select an issue type';
      notifyListeners();
      return false;
    }

    if (descriptionController.text.trim().isEmpty) {
      errorMessage = 'Please describe the issue';
      notifyListeners();
      return false;
    }

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.reportAccessibilityIssue(
        reportCode: _generateReportCode(),
        issueType: issueType!,
        venueName: venueName,
        locationZone: locationController.text.isNotEmpty
            ? locationController.text
            : venueName,
        description: descriptionController.text,
        severity: severityLabel,
      );

      isSubmitting = false;

      if (result != null) {
        isSubmitted = true;
        notifyListeners();
        return true;
      } else {
        errorMessage = 'Failed to submit report. Please try again.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      isSubmitting = false;
      errorMessage = 'Network error: $e';
      notifyListeners();
      return false;
    }
  }

  void reset() {
    issueType = null;
    severity = 1;
    locationController.clear();
    descriptionController.clear();
    errorMessage = null;
    isSubmitted = false;
    notifyListeners();
  }

  @override
  void dispose() {
    locationController.dispose();
    descriptionController.dispose();
    super.dispose();
  }
}

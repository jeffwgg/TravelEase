import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/accessibility_alert_service.dart';
import '../../models/repositories/feature_usage_repository.dart';
import '../../viewmodels/sos_viewmodel.dart';

class SosActiveView extends StatefulWidget {
  const SosActiveView({super.key});

  @override
  State<SosActiveView> createState() => _SosActiveViewState();
}

class _SosActiveViewState extends State<SosActiveView> {
  late final SosViewModel _viewModel;
  final _alertService = AccessibilityAlertService();

  @override
  void initState() {
    super.initState();
    FeatureUsageTracker.instance.completed(TrackedFeature.sos);
    unawaited(_alertService.vibrateForSos());
    _viewModel = SosViewModel()..activateSos();
  }

  @override
  void dispose() {
    unawaited(_alertService.stopSosVibration());
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 52),
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.emergency.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emergency_rounded,
                  color: AppColors.emergency,
                  size: 52,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'SOS ACTIVE',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.emergency,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Emergency alert activated',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              _EmergencyContactStatus(viewModel: _viewModel),
              const SizedBox(height: 12),
              _LocationStatus(viewModel: _viewModel),
              const SizedBox(height: 12),
              _InstitutionStatus(viewModel: _viewModel),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _endSos,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('End SOS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emergency,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Emergency status updates are shown above.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _endSos() async {
    await _alertService.stopSosVibration();
    if (mounted) context.go('/home');
  }
}

class _InstitutionStatus extends StatelessWidget {
  const _InstitutionStatus({required this.viewModel});

  final SosViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final status = viewModel.institutionStatus;
    final (label, color, icon) = switch (status) {
      SosInstitutionStatus.requestSent => (
        'Request sent',
        AppColors.success,
        Icons.support_agent_rounded,
      ),
      SosInstitutionStatus.noAffiliatedInstitution => (
        'No affiliated institution nearby',
        AppColors.secondaryDark,
        Icons.location_off_outlined,
      ),
      SosInstitutionStatus.locationUnavailable => (
        'Location unavailable',
        AppColors.secondaryDark,
        Icons.location_disabled_outlined,
      ),
      SosInstitutionStatus.failed => (
        'Request failed',
        AppColors.emergency,
        Icons.error_outline_rounded,
      ),
      SosInstitutionStatus.pending => (
        'Pending',
        AppColors.secondaryDark,
        Icons.support_agent_rounded,
      ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Institution Assistance: $label',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (status == SosInstitutionStatus.pending)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyContactStatus extends StatelessWidget {
  const _EmergencyContactStatus({required this.viewModel});

  final SosViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final status = viewModel.emergencyContactStatus;
    final (label, color, icon) = switch (status) {
      SosEmergencyContactStatus.notified => (
        'Notified',
        AppColors.success,
        Icons.mark_email_read_outlined,
      ),
      SosEmergencyContactStatus.failed => (
        'Failed',
        AppColors.emergency,
        Icons.error_outline_rounded,
      ),
      SosEmergencyContactStatus.notConfigured => (
        'Not configured',
        AppColors.secondaryDark,
        Icons.person_off_outlined,
      ),
      SosEmergencyContactStatus.pending => (
        'Pending',
        AppColors.secondaryDark,
        Icons.contact_emergency_outlined,
      ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Emergency Contact: $label',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (status == SosEmergencyContactStatus.pending)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocationStatus extends StatelessWidget {
  const _LocationStatus({required this.viewModel});

  final SosViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final status = viewModel.locationStatus;
    final isRetrieved = status == SosLocationStatus.retrieved;
    final isUnavailable = status == SosLocationStatus.unavailable;
    final statusLabel = isRetrieved
        ? 'Retrieved'
        : isUnavailable
        ? 'Unavailable'
        : 'Pending';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: (isRetrieved ? AppColors.success : AppColors.secondary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isRetrieved
                    ? Icons.location_on_rounded
                    : Icons.location_off_outlined,
                color: isRetrieved
                    ? AppColors.success
                    : AppColors.secondaryDark,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location: $statusLabel',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (isRetrieved) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Latitude: ${viewModel.latitude!.toStringAsFixed(6)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Longitude: ${viewModel.longitude!.toStringAsFixed(6)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ] else if (isUnavailable &&
                      viewModel.locationMessage != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      viewModel.locationMessage!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

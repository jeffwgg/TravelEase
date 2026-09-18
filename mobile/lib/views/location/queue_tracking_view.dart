import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/entities/queue_tracking.dart';
import '../../services/app_tour_controller.dart';
import '../../services/venue_session_service.dart';
import '../../viewmodels/queue_tracking_viewmodel.dart';
import '../../widgets/app_tour_coachmark.dart';
import '../../widgets/app_message_banner.dart';

class QueueTrackingView extends StatefulWidget {
  const QueueTrackingView({super.key});

  @override
  State<QueueTrackingView> createState() => _QueueTrackingViewState();
}

class _QueueTrackingViewState extends State<QueueTrackingView>
    with WidgetsBindingObserver {
  final TextEditingController _numberController = TextEditingController();
  final _tourTargetKey = GlobalKey();
  final _lineTourKey = GlobalKey();
  final _numberTourKey = GlobalKey();
  final _trackTourKey = GlobalKey();
  int _tourStep = 0;
  final _viewModel = QueueTrackingViewModel();
  int _appliedNumberPrefillRevision = 0;
  List<QueueLineInfo> get _lines => _viewModel.lines;
  QueueTrackingData? get _tracking => _viewModel.tracking;
  String? get _selectedLineId => _viewModel.selectedLineId;

  /// Validation and queue-number lookup errors. These must not hide the
  /// tracking form or a previously loaded queue status.
  String? get _error => _viewModel.error;

  /// A transport/load error. When prior data exists, it is displayed as a
  /// banner while retaining that data; only an initial failure uses the
  /// dedicated retry page.
  String? get _loadError => _viewModel.loadError;
  bool get _loadingLines => _viewModel.loadingLines;
  bool get _trackingNumber => _viewModel.trackingNumber;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel.addListener(_syncNumberController);
    _viewModel.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.removeListener(_syncNumberController);
    _numberController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Realtime events raised while the app was suspended are only picked up
    // when it resumes, so refresh the tracked number on return.
    if (state == AppLifecycleState.resumed) {
      _viewModel.refreshForAppResume();
    }
  }

  void _syncNumberController() {
    final revision = _viewModel.numberPrefillRevision;
    final number = _viewModel.numberToPrefill;
    if (number == null || revision == _appliedNumberPrefillRevision) return;
    _appliedNumberPrefillRevision = revision;
    _numberController.text = number;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final session = VenueSessionService.instance.session;
        final hasTrackingForm =
            session != null &&
            !_loadingLines &&
            _lines.isNotEmpty &&
            _loadError == null;
        final serviceUnavailable =
            session != null &&
            !_loadingLines &&
            _lines.isEmpty &&
            _loadError == null;
        final initialLoadFailure =
            session != null &&
            !_loadingLines &&
            _lines.isEmpty &&
            _tracking == null &&
            _loadError != null;
        return Stack(
          fit: StackFit.expand,
          children: [
            Scaffold(
              appBar: AppBar(
                title: const Text('Queue Number Tracking'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              body: KeyedSubtree(
                key: _tourTargetKey,
                child: initialLoadFailure
                    ? _buildInitialLoadFailure()
                    : RefreshIndicator(
                        onRefresh: _tracking == null
                            ? _viewModel.loadLines
                            : _viewModel.refreshTracking,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_loadingLines)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (session == null)
                              const AppMessageBanner(
                                message: 'Identify your current institution on the Home page before tracking a queue number.',
                                type: AppMessageType.information,
                              )
                            else if (serviceUnavailable)
                              AppMessageBanner(
                                message:
                                    '${session.institutionName} is not currently providing a queue tracking service.',
                                type: AppMessageType.information,
                              )
                            else ...[
                              if (_loadError != null) ...[
                                AppMessageBanner(
                                  message: _loadError!,
                                  type: AppMessageType.error,
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (_error != null) ...[
                                AppMessageBanner(
                                  message: _error!,
                                  type: AppMessageType.error,
                                ),
                                const SizedBox(height: 12),
                              ],
                              _buildTrackingForm(context),
                            ],
                            if (!_loadingLines &&
                                session != null &&
                                !serviceUnavailable &&
                                !initialLoadFailure) ...[
                              const SizedBox(height: 20),
                              if (_tracking == null)
                                _buildEmptyState()
                              else ...[
                                _buildStatusCard(_tracking!),
                                const SizedBox(height: 24),
                                Text(
                                  'Queue Line Information',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 12),
                                _buildLineInformation(_tracking!.line),
                              ],
                            ],
                          ],
                        ),
                      ),
              ),
            ),
            Positioned.fill(
              child: AppTourCoachmark(
                feature: AppTourFeature.queueTracking,
                targetKey: hasTrackingForm
                    ? switch (_tourStep) {
                        0 => _lineTourKey,
                        1 => _numberTourKey,
                        _ => _trackTourKey,
                      }
                    : _tourTargetKey,
                title: switch (_tourStep) {
                  0 => 'Choose a queue line',
                  1 => 'Enter your number',
                  _ => 'Track your queue',
                },
                message: switch (_tourStep) {
                  0 =>
                    hasTrackingForm
                        ? 'Choose a line, or search across all available lines.'
                        : 'First identify a venue on Home to load its queue lines.',
                  1 => 'Enter the number shown on your queue ticket.',
                  _ => 'Tap here to see live position and waiting time.',
                },
                onNext: _advanceTour,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInitialLoadFailure() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                color: AppColors.emergency,
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'Queue tracking is temporarily unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Text(
                _loadError ?? 'Unable to load queue lines. Please try again.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _viewModel.loadLines,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildTrackingForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Identify Your Queue Number',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter the number shown on your queue ticket.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              key: _lineTourKey,
              initialValue: _selectedLineId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Queue Line (Optional)',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Search all queue lines'),
                ),
                ..._lines.map(
                  (line) => DropdownMenuItem<String?>(
                    value: line.id,
                    child: Text(
                      '${line.name} — ${line.serviceArea}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: _loadingLines ? null : _viewModel.selectLine,
            ),
            const SizedBox(height: 12),
            TextField(
              key: _numberTourKey,
              controller: _numberController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Queue Number',
                hintText: 'A-047 or A047',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
              onSubmitted: (_) =>
                  _viewModel.trackNumber(_numberController.text),
            ),
            const SizedBox(height: 14),
            SizedBox(
              key: _trackTourKey,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _trackingNumber
                    ? null
                    : () => _viewModel.trackNumber(_numberController.text),
                icon: _trackingNumber
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(
                  _trackingNumber ? 'Finding Queue…' : 'Track Queue Number',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _advanceTour() {
    if (_tourStep < 2) {
      setState(() => _tourStep++);
    } else {
      AppTourController.instance.advance(context);
    }
  }

  Widget _buildEmptyState() => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: const [
          Icon(Icons.manage_search, size: 42, color: AppColors.primary),
          SizedBox(height: 12),
          Text(
            'Enter a queue number to see live serving information.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    ),
  );

  Widget _buildStatusCard(QueueTrackingData tracking) {
    final statusColor = _statusColor(tracking.status);
    final statusMessage = switch (tracking.status) {
      'called' => 'Please proceed to ${tracking.line.counterLabel}',
      'cancelled' => 'This queue number was cancelled',
      'completed' => 'Service for this queue number is complete',
      _ => 'You will be notified when it is your turn',
    };
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statusColor, Color.lerp(statusColor, Colors.black, 0.22)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Your Queue Number',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              tracking.number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tracking.status.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildQueueStat(
                  'Now Serving',
                  tracking.line.currentNumber,
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: Colors.white24,
                margin: const EdgeInsets.symmetric(horizontal: 5),
              ),
              Expanded(
                child: _buildQueueStat(
                  'People Ahead',
                  '${tracking.peopleAhead}',
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: Colors.white24,
                margin: const EdgeInsets.symmetric(horizontal: 5),
              ),
              Expanded(
                child: _buildQueueStat(
                  'Est. Wait',
                  tracking.estimatedWaitMinutes == 0
                      ? 'Now'
                      : '~${tracking.estimatedWaitMinutes} min',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.vibration, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    statusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineInformation(QueueLineInfo line) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildInfoRow(
            Icons.confirmation_number_outlined,
            'Queue Line',
            line.name,
          ),
          const Divider(height: 24),
          _buildInfoRow(
            Icons.support_agent_outlined,
            'Service',
            line.serviceArea,
          ),
          if (line.counter?.trim().isNotEmpty ?? false) ...[
            const Divider(height: 24),
            _buildInfoRow(
              Icons.meeting_room_outlined,
              'Counter',
              line.counter!.trim(),
            ),
          ],
          const Divider(height: 24),
          _buildInfoRow(
            Icons.schedule_outlined,
            'Operating Hours',
            line.operatingHours ?? 'Contact venue staff',
          ),
          const Divider(height: 24),
          _buildInfoRow(
            Icons.info_outline,
            'Queue Status',
            line.status.toUpperCase(),
          ),
        ],
      ),
    ),
  );

  Color _statusColor(String status) => switch (status) {
    'waiting' => AppColors.secondary,
    'called' => AppColors.accent,
    'completed' => AppColors.success,
    'cancelled' => AppColors.emergency,
    _ => AppColors.textMuted,
  };

  static Widget _buildQueueStat(String label, String value) => Column(
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white60, fontSize: 10),
      ),
    ],
  );

  static Widget _buildInfoRow(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ],
  );
}

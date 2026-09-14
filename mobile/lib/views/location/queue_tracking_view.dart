import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../models/entities/queue_tracking.dart';
import '../../models/repositories/feature_usage_repository.dart';
import '../../models/repositories/queue_repository.dart';
import '../../services/queue_notification_service.dart';
import '../../services/venue_session_service.dart';
import '../../widgets/app_message_banner.dart';

class QueueTrackingView extends StatefulWidget {
  const QueueTrackingView({super.key});

  @override
  State<QueueTrackingView> createState() => _QueueTrackingViewState();
}

class _QueueTrackingViewState extends State<QueueTrackingView>
    with WidgetsBindingObserver {
  final QueueRepository _repository = QueueRepository();
  final TextEditingController _numberController = TextEditingController();
  List<QueueLineInfo> _lines = const [];
  QueueTrackingData? _tracking;
  RealtimeChannel? _channel;
  String? _selectedLineId;
  String? _error;
  bool _loadingLines = true;
  bool _trackingNumber = false;

  QueueLineInfo? get _selectedLine {
    for (final line in _lines) {
      if (line.id == _selectedLineId) return line;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FeatureUsageTracker.instance.opened(TrackedFeature.queueTracking);
    _loadLines();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _numberController.dispose();
    final channel = _channel;
    if (channel != null) _repository.removeSubscription(channel);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Realtime events raised while the app was suspended are only picked up
    // when it resumes, so refresh the tracked number on return.
    if (state == AppLifecycleState.resumed) {
      if (_tracking == null) {
        _loadLines();
      } else {
        _refreshTracking();
      }
    }
  }

  Future<void> _loadLines() async {
    final institutionId = VenueSessionService.instance.session?.institutionId;
    if (institutionId == null) {
      if (mounted) {
        setState(() {
          _lines = const [];
          _tracking = null;
          _selectedLineId = null;
          _loadingLines = false;
          _error = null;
        });
      }
      return;
    }
    try {
      // Queue lines are intentionally institution-wide: the selected service
      // area is shown as information but never filters this list.
      final lines = await _repository.getActiveQueueLines(
        institutionId: institutionId,
      );
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _error = null;
        _loadingLines = false;
        if (!lines.any((line) => line.id == _selectedLineId)) {
          _tracking = null;
          _selectedLineId = null;
        }
      });
      final saved = QueueNotificationService.instance.current;
      final savedLineIsHere =
          saved != null && lines.any((line) => line.id == saved.line.id);
      if (saved != null && savedLineIsHere && mounted) {
        _numberController.text = saved.number;
        setState(() {
          _tracking = saved;
          _selectedLineId = saved.line.id;
        });
        _channel = _repository.subscribeToTracking(
          saved.line.id,
          _refreshTracking,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load queue lines. Please sign in and try again.';
        _loadingLines = false;
      });
    }
  }

  Future<void> _trackNumber() async {
    final institutionId = VenueSessionService.instance.session?.institutionId;
    if (institutionId == null) {
      setState(() => _error = 'Start a venue session before tracking a queue.');
      return;
    }
    final number = _numberController.text.trim();
    if (number.isEmpty) {
      setState(() => _error = 'Enter your queue number.');
      return;
    }
    // Instant feedback: a number beyond the selected line's maximum queue
    // number can never be called, so do not even look it up.
    final selectedLine = _selectedLine;
    if (selectedLine != null) {
      final capError = QueueRepository.maximumQueueNumberViolation(
        number,
        selectedLine,
      );
      if (capError != null) {
        setState(() => _error = capError);
        return;
      }
    }
    setState(() {
      _trackingNumber = true;
      _error = null;
    });
    try {
      final result = await _repository.trackNumber(
        number: number,
        queueLineId: _selectedLineId,
        queuePrefix: _selectedLine?.prefix,
        institutionId: institutionId,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _tracking = null;
          _error = 'Queue number not found. Check the number and queue line.';
        });
        return;
      }
      final previous = _channel;
      if (previous != null) await _repository.removeSubscription(previous);
      _channel = _repository.subscribeToTracking(
        result.line.id,
        _refreshTracking,
      );
      setState(() {
        _tracking = result;
        _selectedLineId = result.line.id;
      });
      await QueueNotificationService.instance.track(result);
      FeatureUsageTracker.instance.completed(TrackedFeature.queueTracking);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is QueueNumberBeyondMaximumException
            ? error.message
            : 'Unable to track this queue number right now.',
      );
    } finally {
      if (mounted) setState(() => _trackingNumber = false);
    }
  }

  Future<void> _refreshTracking() async {
    final current = _tracking;
    final institutionId = VenueSessionService.instance.session?.institutionId;
    if (current == null || institutionId == null) return;
    try {
      final result = await _repository.trackNumber(
        number: current.number,
        queueLineId: current.line.id,
        queuePrefix: current.line.prefix,
        institutionId: institutionId,
      );
      if (mounted && result != null) setState(() => _tracking = result);
    } catch (_) {
      // Keep the last known state during transient realtime refresh failures.
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = VenueSessionService.instance.session;
    final serviceUnavailable =
        session != null && !_loadingLines && _lines.isEmpty && _error == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue Number Tracking'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _tracking == null ? _loadLines : _refreshTracking,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loadingLines)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
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
            else if (_error == null)
              _buildTrackingForm(context),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AppMessageBanner(message: _error!, type: AppMessageType.error),
            ],
            if (!_loadingLines &&
                session != null &&
                !serviceUnavailable &&
                _error == null) ...[
              const SizedBox(height: 20),
              if (_tracking == null)
                _buildEmptyState()
              else ...[
                _buildStatusCard(_tracking!),
                const SizedBox(height: 24),
                Text(
                  'Queue Line Information',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _buildLineInformation(_tracking!.line),
              ],
            ],
          ],
        ),
      ),
    );
  }

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
              onChanged: _loadingLines
                  ? null
                  : (value) => setState(() => _selectedLineId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _numberController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Queue Number',
                hintText: 'A-047 or A047',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
              onSubmitted: (_) => _trackNumber(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _trackingNumber ? null : _trackNumber,
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
      'called' ||
      'serving' => 'Please proceed to ${tracking.line.counterLabel}',
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
    'serving' => AppColors.primary,
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

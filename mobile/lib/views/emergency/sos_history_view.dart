import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/entities/sos_history_entry.dart';
import '../../viewmodels/sos_history_viewmodel.dart';

class SosHistoryView extends StatelessWidget {
  const SosHistoryView({super.key});
  @override
  Widget build(BuildContext context) => const EmergencyHistoryView();
}

class EmergencyCommunicationHistoryView extends StatelessWidget {
  const EmergencyCommunicationHistoryView({super.key});
  @override
  Widget build(BuildContext context) =>
      const EmergencyHistoryView(communications: true);
}

/// Both pages use the same owner-scoped repository data and TravelEase cards.
class EmergencyHistoryView extends StatefulWidget {
  const EmergencyHistoryView({super.key, this.communications = false});
  final bool communications;
  @override
  State<EmergencyHistoryView> createState() => _EmergencyHistoryViewState();
}

class _EmergencyHistoryViewState extends State<EmergencyHistoryView> {
  late final SosHistoryViewModel _viewModel;
  Timer? _refreshTimer;
  String _filter = 'All';
  @override
  void initState() {
    super.initState();
    _viewModel = SosHistoryViewModel()..load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_viewModel.isLoading) _viewModel.load(quiet: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _viewModel.dispose();
    super.dispose();
  }

  String _date(DateTime value) {
    final date = value.toLocal();
    return '${date.day}/${date.month}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.communications ? 'Emergency notifications' : 'SOS History',
      ),
    ),
    body: ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        if (_viewModel.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_viewModel.errorMessage != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_viewModel.errorMessage!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _viewModel.load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        final communications = _viewModel.communications;
        final events = _viewModel.events
            .where(
              (event) => switch (_filter) {
                'Ongoing' => event.assistanceOngoing,
                'Resolved' => event.requestStatus == 'resolved',
                _ => true,
              },
            )
            .toList();
        final count = widget.communications
            ? communications.length
            : events.length;
        return RefreshIndicator(
          onRefresh: _viewModel.load,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount:
                (count == 0 ? 1 : count) + (widget.communications ? 0 : 1),
            itemBuilder: (context, index) {
              if (!widget.communications) {
                if (index == 0) return _overview();
                index--;
              }
              if (count == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 64,
                    horizontal: 16,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        widget.communications
                            ? Icons.forum_outlined
                            : Icons.history,
                        size: 56,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.communications
                            ? 'No communication history yet'
                            : _filter == 'All'
                            ? 'No SOS history yet'
                            : 'No ${_filter.toLowerCase()} requests',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Pull down to refresh.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }
              if (widget.communications) {
                final item = communications[index];
                return _card(Icons.notifications_outlined, item.recipient, [
                  item.type,
                  _date(item.occurredAt),
                  'Status: ${item.status}',
                ]);
              }
              final event = events[index];
              return _SosRecordCard(
                event: event,
                date: _date(event.triggeredAt),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SosHistoryDetailView(
                      eventId: event.id,
                      viewModel: _viewModel,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );

  Widget _overview() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF134E4A), Color(0xFF0F766E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.health_and_safety_outlined,
              color: Color(0xFF99F6E4),
              size: 36,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your safety timeline',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Follow your requests, from the first alert to completed assistance.',
              style: TextStyle(color: Color(0xFFCCFBF1), height: 1.5),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _summary('${_viewModel.events.length}', 'requests'),
                _summary(
                  '${_viewModel.events.where((e) => e.assistanceOngoing).length}',
                  'ongoing',
                ),
                _summary(
                  '${_viewModel.events.where((e) => e.requestStatus == 'resolved').length}',
                  'resolved',
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        children: [
          for (final filter in ['All', 'Ongoing', 'Resolved'])
            ChoiceChip(
              label: Text(filter),
              labelStyle: const TextStyle(color: Colors.black),
              selected: _filter == filter,
              onSelected: (_) => setState(() => _filter = filter),
            ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'MOST RECENT FIRST',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 12),
    ],
  );

  Widget _summary(String count, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      '$count $label',
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
  );

  Widget _card(IconData icon, String title, List<String> lines) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SosRecordCard extends StatelessWidget {
  const _SosRecordCard({
    required this.event,
    required this.date,
    required this.onTap,
  });
  final SosHistoryEntry event;
  final String date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final resolved = event.requestStatus == 'resolved';
    final color = resolved
        ? AppColors.primaryDark
        : event.assistanceOngoing
        ? const Color(0xFFB45309)
        : AppColors.textSecondary;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withValues(alpha: .2)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      resolved ? Icons.verified_outlined : Icons.sos_rounded,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          date,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          event.institution ?? 'Emergency alert',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  historyStatusLabel(event.progressStatus),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 14),
              _line(
                Icons.place_outlined,
                event.serviceArea ?? 'No service area matched',
              ),
              _line(Icons.my_location_rounded, event.location),
              if (event.assignedStaff != null)
                _line(Icons.support_agent_rounded, event.assignedStaff!),
              const Divider(height: 24),
              Text(
                event.assistanceSummary,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class SosHistoryDetailView extends StatefulWidget {
  const SosHistoryDetailView({
    super.key,
    required this.eventId,
    required this.viewModel,
  });
  final String eventId;
  final SosHistoryViewModel viewModel;

  @override
  State<SosHistoryDetailView> createState() => _SosHistoryDetailViewState();
}

class _SosHistoryDetailViewState extends State<SosHistoryDetailView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.viewModel.load(quiet: true));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('SOS details'),
      actions: [
        IconButton(
          onPressed: widget.viewModel.load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh progress',
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final model = widget.viewModel;
        if (model.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        // Never retain a detached snapshot after logout or a failed refresh.
        if (model.errorMessage != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(model.errorMessage!),
            ),
          );
        }
        final matches = model.events.where(
          (entry) => entry.id == widget.eventId,
        );
        if (matches.isEmpty) {
          return const Center(child: Text('This SOS record is unavailable.'));
        }
        final event = matches.first;
        const stages = [
          'sent',
          'acknowledged',
          'assigned',
          'en_route',
          'resolved',
        ];
        final current = stages.indexOf(event.progressStatus);
        return RefreshIndicator(
          onRefresh: model.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF134E4A), Color(0xFF0F766E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            event.requestStatus == 'resolved'
                                ? Icons.verified_outlined
                                : Icons.health_and_safety_outlined,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'EMERGENCY RECORD',
                            style: TextStyle(
                              color: Color(0xFFCCFBF1),
                              fontSize: 11,
                              letterSpacing: 1.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      event.assistanceSummary,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCCFBF1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        historyStatusLabel(event.progressStatus),
                        style: const TextStyle(
                          color: Color(0xFF134E4A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFF5C9E96)),
                    const SizedBox(height: 8),
                    Text(
                      'Triggered ${_date(event.triggeredAt)}',
                      style: const TextStyle(
                        color: Color(0xFFCCFBF1),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (current >= 0) ...[
                const SizedBox(height: 16),
                _section(Icons.route_outlined, 'Assistance journey', [
                  const Text(
                    'Your current response stage',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  for (var index = 0; index < stages.length; index++)
                    _stage(
                      stages[index],
                      index,
                      current,
                      index == stages.length - 1,
                    ),
                ]),
              ],
              const SizedBox(height: 16),
              _section(Icons.location_on_outlined, 'Where help was requested', [
                _detail('Institution', event.institution ?? 'Not matched'),
                _detail('Service area', event.serviceArea ?? 'Not matched'),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TRIGGER LOCATION',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        event.location,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              _section(Icons.support_agent_rounded, 'Your response team', [
                _detail(
                  'Assigned staff',
                  event.assignedStaff ?? 'Awaiting assignment',
                ),
                if (event.staffContact?.trim().isNotEmpty ?? false)
                  _detail('Staff contact', event.staffContact!),
                if (event.assignedStaff == null)
                  const Text(
                    'Staff details will appear here when someone is assigned.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
              ]),
              if (event.resolvedAt != null || event.endedAt != null) ...[
                const SizedBox(height: 16),
                _section(Icons.history_rounded, 'Event timestamps', [
                  if (event.resolvedAt != null)
                    _detail('Resolved', _date(event.resolvedAt!)),
                  if (event.endedAt != null) ...[
                    _detail('Device alerts ended', _date(event.endedAt!)),
                    const Text(
                      'Ending device alerts does not mark institution assistance as resolved.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ]),
              ],
              const SizedBox(height: 16),
              const Text(
                'Progress refreshes every 15 seconds. Pull down to refresh now.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  String _date(DateTime value) {
    final date = value.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _section(IconData icon, String title, List<Widget> children) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.primary.withValues(alpha: .13)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primaryDark, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );

  Widget _stage(String status, int index, int current, bool last) {
    final selected = index == current;
    const icons = [
      Icons.notifications_active_outlined,
      Icons.mark_chat_read_outlined,
      Icons.person_outline,
      Icons.directions_walk_rounded,
      Icons.verified_outlined,
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryDark
                      : AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icons[index],
                  size: 19,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: AppColors.cardBorder),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 20, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status == 'sent'
                        ? 'Waiting for acknowledgement'
                        : historyStatusLabel(status),
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                      color: selected
                          ? AppColors.primaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'CURRENT STAGE',
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 5),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

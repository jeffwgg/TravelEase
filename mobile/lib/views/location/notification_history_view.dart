import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/repositories/notification_history_store.dart';
import '../../services/app_notification_service.dart';

enum _NotificationFilter { announcement, alert, queue, message }

/// Device-local history of raised notifications. Tapping an announcement or
/// queue entry deep-links into its screen; entries survive quitting the
/// venue session because the history is stored on the device.
class NotificationHistoryView extends StatefulWidget {
  const NotificationHistoryView({super.key});

  @override
  State<NotificationHistoryView> createState() =>
      _NotificationHistoryViewState();
}

class _NotificationHistoryViewState extends State<NotificationHistoryView>
    with WidgetsBindingObserver {
  final NotificationHistoryStore _store = NotificationHistoryStore.instance;
  StreamSubscription<void>? _changes;
  List<NotificationHistoryEntry> _entries = [];
  bool _loading = true;
  _NotificationFilter? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _changes = _store.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changes?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Notifications raised while the app was inactive are recorded by the
    // background isolate, whose store events cannot cross isolates — reload
    // when the traveller returns so the list is always current.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final entries = await _store.entries();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  String _dayLabel(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return MaterialLocalizations.of(context).formatMediumDate(day);
  }

  String _timeLabel(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inDays < 1) {
      return TimeOfDay.fromDateTime(time).format(context);
    }
    return '${MaterialLocalizations.of(context).formatCompactDate(time)} · '
        '${TimeOfDay.fromDateTime(time).format(context)}';
  }

  IconData _iconFor(String kind) => switch (kind) {
    'announcement' => Icons.campaign,
    'captured' => Icons.mic,
    'queue' => Icons.confirmation_num,
    _ => Icons.notifications_active,
  };

  Color _colorFor(String kind) => switch (kind) {
    'announcement' => AppColors.primary,
    'captured' => AppColors.accent,
    'queue' => AppColors.success,
    _ => AppColors.secondary,
  };

  List<NotificationHistoryEntry> get _visibleEntries {
    final filter = _filter;
    if (filter == null) return _entries;
    return _entries.where((entry) {
      return switch (filter) {
        _NotificationFilter.announcement =>
          entry.kind == 'announcement' || entry.kind == 'captured',
        _NotificationFilter.alert => entry.kind == 'sound',
        _NotificationFilter.queue => entry.kind == 'queue',
        _NotificationFilter.message => entry.kind == 'request',
      };
    }).toList();
  }

  String get _filterLabel => switch (_filter) {
    _NotificationFilter.announcement => 'announcement',
    _NotificationFilter.alert => 'alert',
    _NotificationFilter.queue => 'queue',
    _NotificationFilter.message => 'message',
    null => 'notification',
  };

  Future<bool> _confirmDeletion({required bool all}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(all ? 'Delete all notifications?' : 'Delete notification?'),
        content: Text(
          all
              ? 'This removes all notification records from this device.'
              : 'This removes this notification record from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emergency,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _deleteEntry(NotificationHistoryEntry entry) async {
    if (!await _confirmDeletion(all: false)) return;
    await AppNotificationService.instance.deleteHistoryEntry(entry);
  }

  Future<void> _deleteAll() async {
    if (!await _confirmDeletion(all: true)) return;
    await AppNotificationService.instance.clearNotificationHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Delete all notifications',
            onPressed: _entries.isEmpty ? null : _deleteAll,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Mark all as read',
            onPressed: _entries.isEmpty
                ? null
                : () => AppNotificationService.instance.markAllAsRead(),
            icon: const Icon(Icons.done_all_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 48,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No notifications yet',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildFilters(),
                  const SizedBox(height: 10),
                  if (_visibleEntries.isEmpty)
                    _buildFilteredEmptyState()
                  else
                    ..._buildSections(_visibleEntries),
                ],
              ),
            ),
    );
  }

  Widget _buildFilters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _buildFilterButton(_NotificationFilter.announcement, 'Announcement'),
        const SizedBox(width: 8),
        _buildFilterButton(_NotificationFilter.alert, 'Alerts'),
        const SizedBox(width: 8),
        _buildFilterButton(_NotificationFilter.queue, 'Queue'),
        const SizedBox(width: 8),
        _buildFilterButton(_NotificationFilter.message, 'Message'),
      ],
    ),
  );

  Widget _buildFilterButton(_NotificationFilter filter, String label) {
    final selected = _filter == filter;
    return FilterChip(
      label: Text(label),
      labelStyle: TextStyle(color: AppColors.primaryDark),
      selectedColor: AppColors.background,
      disabledColor: AppColors.accentLight,
      selected: selected,
      onSelected: (_) => setState(() => _filter = selected ? null : filter),
    );
  }

  Widget _buildFilteredEmptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        const Icon(
          Icons.filter_list_off_outlined,
          size: 42,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 10),
        Text(
          'No $_filterLabel notifications',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose the selected filter again to show all notifications.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted),
        ),
      ],
    ),
  );

  List<Widget> _buildSections(List<NotificationHistoryEntry> entries) {
    final widgets = <Widget>[];
    var currentLabel = '';
    for (final entry in entries) {
      final label = _dayLabel(entry.createdAt);
      if (label != currentLabel) {
        currentLabel = label;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 8),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
        );
      }
      widgets.add(_buildNotification(entry));
    }
    widgets.add(const SizedBox(height: 16));
    return widgets;
  }

  Widget _buildNotification(NotificationHistoryEntry entry) {
    final color = _colorFor(entry.kind);
    final tappable = entry.route != null && entry.route!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: entry.read ? null : color.withValues(alpha: 0.03),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: entry.read
              ? BorderSide.none
              : BorderSide(color: color.withValues(alpha: 0.2)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: tappable
              ? () async {
                  // Opening the notification counts as reading it.
                  await AppNotificationService.instance.markAsRead(entry);
                  if (!mounted) return;
                  context.push(entry.route!);
                }
              : () => AppNotificationService.instance.markAsRead(entry),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_iconFor(entry.kind), color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              entry.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: entry.read
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (!entry.read)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.body,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _timeLabel(entry.createdAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Delete notification',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _deleteEntry(entry),
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 19,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

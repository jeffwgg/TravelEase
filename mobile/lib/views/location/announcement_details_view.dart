import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/entities/announcement.dart';
import '../../models/entities/captured_announcement.dart';
import '../../models/repositories/announcement_repository.dart';
import '../../models/repositories/captured_announcement_store.dart';
import '../../widgets/app_message_banner.dart';

/// Full content of a single announcement reached from the home preview or the
/// announcement list.
class AnnouncementDetailsView extends StatefulWidget {
  final String id;

  const AnnouncementDetailsView({super.key, required this.id});

  @override
  State<AnnouncementDetailsView> createState() =>
      _AnnouncementDetailsViewState();
}

class _AnnouncementDetailsViewState extends State<AnnouncementDetailsView> {
  final _repository = AnnouncementRepository();
  Announcement? _announcement;
  CapturedAnnouncement? _capture;
  bool _loading = true;
  String? _error;
  String _language = 'en';

  @override
  void initState() {
    super.initState();
    _loadAnnouncement();
  }

  Future<void> _loadAnnouncement() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final announcement = await _repository.getAnnouncementById(widget.id);
      CapturedAnnouncement? capture;
      var resolved = announcement;
      if (resolved == null) {
        // Not an official row — check device-local captured announcements.
        capture = await CapturedAnnouncementStore.instance.byId(widget.id);
        resolved = capture?.toAnnouncement();
      }
      if (!mounted) return;
      setState(() {
        _announcement = resolved;
        _capture = capture;
        _loading = false;
        if (resolved == null) {
          _error = 'This announcement is no longer available.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Announcement could not be loaded.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcement Details'),
        actions: [
          if (_announcement != null)
            PopupMenuButton<String>(
              tooltip: 'Announcement language',
              icon: const Icon(Icons.translate),
              initialValue: _language,
              onSelected: (value) => setState(() => _language = value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'en', child: Text('English')),
                PopupMenuItem(value: 'ms', child: Text('Bahasa Melayu')),
                PopupMenuItem(value: 'zh', child: Text('Chinese (Simplified)')),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAnnouncement,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null || _announcement == null)
              Column(
                children: [
                  AppMessageBanner(
                    message: _error ?? 'Announcement could not be loaded.',
                    type: AppMessageType.error,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _loadAnnouncement,
                      child: const Text('Try Again'),
                    ),
                  ),
                ],
              )
            else
              _buildDetails(context, _announcement!),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, Announcement announcement) {
    final captured = announcement.isCaptured;
    final color = captured ? AppColors.accent : _colorFor(announcement);
    final translation = announcement.translations[_language];
    final title =
        _language == 'en' || translation == null || translation.title.isEmpty
        ? announcement.title
        : translation.title;
    final message =
        _language == 'en' || translation == null || translation.message.isEmpty
        ? announcement.messageEn
        : translation.message;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: announcement.isUrgent
                ? BorderSide(color: color, width: 1.5)
                : BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        captured ? Icons.mic_outlined : _iconFor(announcement.type),
                        color: color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                  child: Text(
                                    captured
                                        ? 'CAPTURED • ${((announcement.confidence ?? 0) * 100).round()}%'
                                        : announcement.priority.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ),
                              if (!captured)
                                const Text(
                                  'Official',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 17,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (captured) ...[
                  if (_capture != null) ...[
                    _buildMetaRow(
                      Icons.hearing_outlined,
                      'Language: ${_capture!.language.toUpperCase()} • heard ${_capture!.repetitionCount} time${_capture!.repetitionCount == 1 ? '' : 's'}',
                    ),
                    _buildMetaRow(
                      Icons.history_outlined,
                      'First heard ${_formatDateTime(_capture!.firstCapturedAt)}',
                    ),
                  ],
                  _buildMetaRow(
                    Icons.info_outline,
                    'Recognised from the environment — content may be imperfect.',
                  ),
                ] else ...[
                  _buildMetaRow(
                    Icons.account_balance_outlined,
                    announcement.institutionName ?? 'Participating institution',
                  ),
                  if (announcement.zoneName != null)
                    _buildMetaRow(Icons.pin_drop_outlined, announcement.zoneName!),
                  _buildMetaRow(
                    Icons.schedule_outlined,
                    'Published ${_formatDateTime(announcement.publishedAt)}',
                  )
                ],
                const Divider(height: 24),
                Text(message, style: Theme.of(context).textTheme.bodyLarge),
                if (_language != 'en' && !captured && translation == null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Translation unavailable — showing English.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaRow(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) => switch (type) {
    'boarding' => Icons.flight_takeoff,
    'delay_cancellation' => Icons.schedule,
    'emergency' => Icons.warning_amber_rounded,
    'travel_update' => Icons.swap_horiz,
    _ => Icons.campaign_outlined,
  };

  Color _colorFor(Announcement announcement) => switch (announcement.priority) {
    'urgent' => AppColors.emergency,
    'high' => AppColors.secondary,
    'low' => AppColors.textSecondary,
    _ => AppColors.primary,
  };

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} at $hour:$minute';
  }
}

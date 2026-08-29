import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../models/entities/announcement.dart';
import '../../models/repositories/announcement_repository.dart';
import '../../widgets/app_message_banner.dart';

class AnnouncementView extends StatefulWidget {
  const AnnouncementView({super.key});

  @override
  State<AnnouncementView> createState() => _AnnouncementViewState();
}

class _AnnouncementViewState extends State<AnnouncementView> {
  final _repository = AnnouncementRepository();
  List<Announcement> _announcements = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _urgentOnly = false;
  String _language = 'en';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
    _channel = _repository.subscribeToAnnouncements(_loadAnnouncements);
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _repository.removeSubscription(channel);
    super.dispose();
  }

  Future<void> _loadAnnouncements() async {
    try {
      final announcements = await _repository.getActiveAnnouncements();
      if (!mounted) return;
      setState(() {
        _announcements = announcements;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _urgentOnly
        ? _announcements.where((item) => item.isUrgent).toList()
        : _announcements;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
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
          IconButton(
            tooltip: _urgentOnly
                ? 'Show all announcements'
                : 'Show urgent only',
            icon: Icon(
              _urgentOnly ? Icons.filter_alt : Icons.filter_list,
              color: _urgentOnly ? AppColors.primary : null,
            ),
            onPressed: () => setState(() => _urgentOnly = !_urgentOnly),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAnnouncements,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildVenueHeader(context),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loading && _error != null) _buildError(context),
            if (!_loading && _error == null && visible.isEmpty)
              _buildEmpty(context),
            if (!_loading && _error == null)
              ...visible.map(
                (announcement) => _buildAnnouncement(context, announcement),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'KLIA Terminal 1',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.primary),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Live',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.success),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Column(
      children: [
        const AppMessageBanner(
          message: 'Announcements could not be loaded.',
          type: AppMessageType.error,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _loadAnnouncements,
            child: const Text('Try Again'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(
            Icons.campaign_outlined,
            color: AppColors.textMuted,
            size: 42,
          ),
          const SizedBox(height: 12),
          Text(
            _urgentOnly
                ? 'No urgent announcements.'
                : 'No active announcements.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncement(BuildContext context, Announcement announcement) {
    final color = _colorFor(announcement);
    final translation = announcement.translations[_language];
    final title =
        _language == 'en' || translation == null || translation.title.isEmpty
        ? announcement.title
        : translation.title;
    final message =
        _language == 'en' || translation == null || translation.message.isEmpty
        ? announcement.messageEn
        : translation.message;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _iconFor(announcement.type),
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (announcement.isUrgent)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.emergency.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  announcement.priority.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.emergency,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _relativeTime(announcement.publishedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(message, style: Theme.of(context).textTheme.bodyMedium),
              if (_language != 'en' && translation == null) ...[
                const SizedBox(height: 6),
                Text(
                  'Translation unavailable — showing English.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.pin_drop_outlined,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    announcement.zoneName ?? 'All Zones',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
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

  String _relativeTime(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} hr ago';
    if (difference.inDays < 7) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    }
    return '${value.day}/${value.month}/${value.year}';
  }
}

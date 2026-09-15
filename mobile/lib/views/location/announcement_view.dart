import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../models/entities/announcement.dart';
import '../../models/repositories/announcement_repository.dart';
import '../../models/repositories/captured_announcement_store.dart';
import '../../models/repositories/feature_usage_repository.dart';
import '../../services/venue_session_service.dart';
import '../../widgets/app_message_banner.dart';

enum AnnouncementFeed { spoken, official }

class AnnouncementView extends StatefulWidget {
  const AnnouncementView({super.key, this.feed = AnnouncementFeed.official});

  final AnnouncementFeed feed;

  @override
  State<AnnouncementView> createState() => _AnnouncementViewState();
}

class _AnnouncementViewState extends State<AnnouncementView> {
  final _repository = AnnouncementRepository();
  List<Announcement> _announcements = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  final bool _urgentOnly = false;
  String _language = 'en';
  String? _error;
  String? _institutionId;
  String? _institutionName;
  String? _serviceAreaId;
  String? _serviceAreaName;

  @override
  void initState() {
    super.initState();
    FeatureUsageTracker.instance.opened(TrackedFeature.announcements);
    if (widget.feed == AnnouncementFeed.official) {
      _syncSession(reload: true);
      VenueSessionService.instance.addListener(_onSessionChanged);
    } else {
      _loadSpokenAnnouncements();
      CapturedAnnouncementStore.instance.version.addListener(
        _onCapturedAnnouncementsChanged,
      );
    }
  }

  @override
  void dispose() {
    VenueSessionService.instance.removeListener(_onSessionChanged);
    CapturedAnnouncementStore.instance.version.removeListener(
      _onCapturedAnnouncementsChanged,
    );
    final channel = _channel;
    if (channel != null) _repository.removeSubscription(channel);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _syncSession(reload: true);
  }

  void _onCapturedAnnouncementsChanged() {
    if (!mounted) return;
    _loadSpokenAnnouncements();
  }

  /// Official announcements are institution-scoped, so this feed follows the
  /// active venue session and resubscribes when the session changes.
  Future<void> _syncSession({required bool reload}) async {
    final session = VenueSessionService.instance.session;
    final institutionId = session?.institutionId;
    final serviceAreaId = session?.serviceAreaId;
    final changed =
        institutionId != _institutionId || serviceAreaId != _serviceAreaId;
    setState(() {
      _institutionId = institutionId;
      _institutionName = session?.institutionName;
      _serviceAreaId = serviceAreaId;
      _serviceAreaName = session?.serviceAreaName;
    });
    final previous = _channel;
    _channel = null;
    if (previous != null) await _repository.removeSubscription(previous);
    if (institutionId == null) {
      if (mounted) {
        setState(() {
          _announcements = const [];
          _loading = false;
          _error = null;
        });
      }
      return;
    }
    _channel = _repository.subscribeToAnnouncements(
      _loadAnnouncements,
      institutionId: institutionId,
    );
    if (reload || changed) await _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    final institutionId = _institutionId;
    if (institutionId == null) return;
    try {
      final official = await _repository.getActiveAnnouncements(
        institutionId: institutionId,
        serviceAreaId: _serviceAreaId,
      );
      if (!mounted) return;
      setState(() {
        _announcements = official;
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

  Future<void> _loadSpokenAnnouncements() async {
    try {
      final spoken = await CapturedAnnouncementStore.instance.announcements();
      if (!mounted) return;
      setState(() {
        _announcements = spoken;
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

  Future<void> _reload() => widget.feed == AnnouncementFeed.spoken
      ? _loadSpokenAnnouncements()
      : _loadAnnouncements();

  @override
  Widget build(BuildContext context) {
    final isSpokenFeed = widget.feed == AnnouncementFeed.spoken;
    final visible = _urgentOnly
        ? _announcements.where((item) => item.isUrgent).toList()
        : _announcements;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isSpokenFeed ? 'Spoken Announcements' : 'Official Announcements',
        ),
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
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isSpokenFeed)
              _buildSpokenHeader(context)
            else
              _buildVenueHeader(context),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loading && !isSpokenFeed && _institutionId == null)
              _buildNoSession(context),
            if (!_loading &&
                _error != null &&
                (isSpokenFeed || _institutionId != null))
              _buildError(context),
            if (!_loading &&
                _error == null &&
                (isSpokenFeed || _institutionId != null) &&
                visible.isEmpty)
              _buildEmpty(context, isSpokenFeed: isSpokenFeed),
            if (!_loading &&
                _error == null &&
                (isSpokenFeed || _institutionId != null))
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
              _institutionName == null
                  ? 'No active venue session'
                  : _serviceAreaName == null
                  ? _institutionName!
                  : '$_institutionName · $_serviceAreaName',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: AppColors.primary),
            ),
          ),
          if (_institutionId != null) ...[
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
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.success),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpokenHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.mic_outlined, color: AppColors.accent, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Captured on this device — no venue session needed.'),
          ),
          TextButton(
            onPressed: () => context.push('/environment-sound-alert'),
            child: const Text('Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSession(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: AppMessageBanner(
        message:
            'Identify your location on the home page and start a venue session '
            'to receive its official announcements.',
        type: AppMessageType.information,
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

  Widget _buildEmpty(BuildContext context, {required bool isSpokenFeed}) {
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
            isSpokenFeed
                ? 'No spoken announcements yet.'
                : _urgentOnly
                ? 'No urgent announcements.'
                : 'No active announcements.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncement(BuildContext context, Announcement announcement) {
    final captured = announcement.isCaptured;
    final color = captured ? AppColors.accent : _colorFor(announcement);
    final translation = announcement.translations[_language];
    final title =
        _language == 'en' || translation == null || translation.title.isEmpty
        ? announcement.title
        : translation.title;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: announcement.isUrgent
              ? BorderSide(color: color, width: 1.5)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () =>
              context.push('/announcement-details?id=${announcement.id}'),
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
                        captured
                            ? Icons.mic_outlined
                            : _iconFor(announcement.type),
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
                              if (captured)
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'CAPTURED • ${((announcement.confidence ?? 0) * 100).round()}%',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.accent,
                                    ),
                                  ),
                                )
                              else
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
                                    announcement.priorityLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: color,
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
                              const Icon(
                                Icons.chevron_right,
                                color: AppColors.textMuted,
                                size: 20,
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      captured
                          ? Icons.phone_android_outlined
                          : Icons.pin_drop_outlined,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      captured
                          ? 'Captured on this device'
                          : announcement.serviceAreaName ?? 'All service areas',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
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

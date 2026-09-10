import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../models/entities/announcement.dart';
import '../../models/entities/venue_search_result.dart';
import '../../models/entities/venue_session.dart';
import '../../models/repositories/announcement_repository.dart';
import '../../models/repositories/captured_announcement_store.dart';
import '../../models/repositories/venue_repository.dart';
import '../../services/venue_session_service.dart';
import '../../widgets/app_message_banner.dart';

class VenueIdentificationView extends StatefulWidget {
  const VenueIdentificationView({super.key});

  @override
  State<VenueIdentificationView> createState() =>
      _VenueIdentificationViewState();
}

class _VenueIdentificationViewState extends State<VenueIdentificationView>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _venueRepository = VenueRepository();
  final _announcementRepository = AnnouncementRepository();

  Timer? _searchDebounce;

  /// Catch-up refresh for the announcement feed: scheduled announcements are
  /// published when their time arrives without any database change, so
  /// realtime delivers no event and the list must re-fetch on its own.
  Timer? _feedRefreshTimer;
  List<VenueSearchResult> _searchResults = const [];
  bool _searching = false;
  String? _searchError;

  // Location detection (reuses the request-help module's detection settings).
  bool _locating = false;
  bool _matching = false;
  String? _locationStatus;
  String? _locationError;
  List<VenueSearchResult> _detectedVenues = const [];

  // Official announcements of the active venue session.
  List<Announcement> _recentAnnouncements = [];
  RealtimeChannel? _announcementChannel;

  VenueSession? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = VenueSessionService.instance.session;
    VenueSessionService.instance.addListener(_onSessionChanged);
    CapturedAnnouncementStore.instance.version.addListener(_onSessionChanged);
    _refreshAnnouncementFeed();
    _feedRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshAnnouncementFeed(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Tapping an announcement notification resumes the app after the
    // background poller raised it; the feed must catch up on return.
    if (state == AppLifecycleState.resumed) _refreshAnnouncementFeed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feedRefreshTimer?.cancel();
    VenueSessionService.instance.removeListener(_onSessionChanged);
    CapturedAnnouncementStore.instance.version.removeListener(
      _onSessionChanged,
    );
    _searchDebounce?.cancel();
    _searchController.dispose();
    final channel = _announcementChannel;
    if (channel != null) _announcementRepository.removeSubscription(channel);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() => _session = VenueSessionService.instance.session);
    _refreshAnnouncementFeed();
  }

  void _refreshAnnouncementFeed() {
    _loadRecentAnnouncements();
    _resubscribeToAnnouncements();
  }

  Future<void> _loadRecentAnnouncements() async {
    final session = VenueSessionService.instance.session;
    if (session == null) {
      if (mounted) setState(() => _recentAnnouncements = const []);
      return;
    }
    try {
      final official = await _announcementRepository.getActiveAnnouncements(
        institutionId: session.institutionId,
      );
      final captured = await CapturedAnnouncementStore.instance
          .announcementsFor(session.institutionId);
      final merged = [...official, ...captured]
        ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      if (mounted) {
        setState(() => _recentAnnouncements = merged.take(2).toList());
      }
    } catch (_) {
      // The full announcement page exposes retry/error UI. Keep the home preview quiet.
    }
  }

  Future<void> _resubscribeToAnnouncements() async {
    final institutionId = VenueSessionService.instance.session?.institutionId;
    final previous = _announcementChannel;
    _announcementChannel = null;
    if (previous != null) {
      await _announcementRepository.removeSubscription(previous);
    }
    if (institutionId == null || !mounted) return;
    _announcementChannel = _announcementRepository.subscribeToAnnouncements(
      _loadRecentAnnouncements,
      institutionId: institutionId,
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchVenues(query),
    );
  }

  Future<void> _searchVenues(String query) async {
    try {
      final results = await _venueRepository.search(query);
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _searchResults = const [];
        _searching = false;
        _searchError = 'Unable to search participating institutions right now.';
      });
    }
  }

  /// Detects the traveller's position with the same permission flow and
  /// accuracy settings used by the request-help location picker (FR-M2-02).
  Future<void> _detectCurrentLocation() async {
    if (_locating || _matching) return;
    setState(() {
      _locating = true;
      _locationStatus = 'Detecting your location…';
      _locationError = null;
      _detectedVenues = const [];
    });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locating = false;
          _locationStatus = null;
          _locationError =
              'Location permission is required to detect nearby institutions. '
              'Search for your institution or choose its location on the map instead.';
        });
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() => _locationStatus = 'Matching against participating institutions…');
      await _handleDetectedPosition(position.latitude, position.longitude);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationStatus = null;
        _locationError =
            'Unable to detect your current location. Choose your location on the map instead.';
      });
    }
  }

  /// Lets the traveller pick their location on the map when GPS detection is
  /// unavailable or undesired, using the request-help module's map picker.
  Future<void> _chooseOnMap() async {
    if (_locating || _matching) return;
    final result = await context.push<Map<String, dynamic>>('/location-picker');
    final latitude = (result?['lat'] as num?)?.toDouble();
    final longitude = (result?['lng'] as num?)?.toDouble();
    if (!mounted || latitude == null || longitude == null) return;
    setState(() {
      _locationStatus = 'Matching against participating institutions…';
      _locationError = null;
      _detectedVenues = const [];
    });
    await _handleDetectedPosition(latitude, longitude);
  }

  /// Compares the chosen position against the institution list: a direct
  /// match starts a venue session, otherwise nearby institutions are offered
  /// as a list to choose from (FR-M2-03).
  Future<void> _handleDetectedPosition(double latitude, double longitude) async {
    setState(() {
      _locating = false;
      _matching = true;
      _searchResults = const [];
      _searchError = null;
    });
    try {
      final match = await _venueRepository.matchLocation(
        latitude: latitude,
        longitude: longitude,
      );
      if (!mounted) return;
      if (match != null) {
        setState(() {
          _matching = false;
          _locationStatus = null;
        });
        await _confirmAndEstablish(match, autoSuggested: true);
        return;
      }
      final nearby = await _venueRepository.nearby(
        latitude: latitude,
        longitude: longitude,
      );
      if (!mounted) return;
      setState(() {
        _matching = false;
        _locationStatus = null;
        _detectedVenues = nearby;
        _locationError = nearby.isEmpty
            ? 'No participating institution was found near this location. '
                'Search for your institution manually instead.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _matching = false;
        _locationStatus = null;
        _locationError =
            'Unable to match your location against the institution list right now.';
      });
    }
  }

  /// Requires the traveller to confirm the institution before the venue
  /// session starts (FR-M2-03).
  Future<void> _confirmAndEstablish(
    VenueSearchResult venue, {
    bool autoSuggested = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start venue session?'),
        content: Text(
          autoSuggested
              ? 'You appear to be at ${venue.name}. Start a venue session to '
                  'receive its official announcements and location services?'
              : 'Connect to ${venue.name} to receive its official '
                  'announcements and location services?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Start Session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await VenueSessionService.instance.establish(
      VenueSession(
        institutionId: venue.id,
        institutionName: venue.name,
        branch: venue.branch,
        startedAt: DateTime.now(),
      ),
    );
  }

  /// Ends the active venue session (FR-M2-06, manual end).
  Future<void> _quitSession() async {
    final session = _session;
    if (session == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End venue session?'),
        content: Text(
          'You will stop receiving official announcements from '
          '${session.institutionName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await VenueSessionService.instance.quit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset(
                                'assets/logo.png',
                                width: 38,
                                height: 38,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hello, Jeff',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineLarge,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Where are you traveling today?',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => context.push('/notifications'),
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.notifications_outlined,
                                  size: 22,
                                ),
                              ),
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.emergency,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Quick Actions
                    Text(
                      'Quick Actions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildQuickAction(
                            context,
                            Icons.sign_language_rounded,
                            'Sign\nTranslate',
                            AppColors.primary,
                            () => context.push('/sign-camera'),
                          ),
                          _buildQuickAction(
                            context,
                            Icons.record_voice_over,
                            'Speech\nto Sign',
                            AppColors.accent,
                            () => context.push('/speech-to-sign'),
                          ),
                          _buildQuickAction(
                            context,
                            Icons.forum_rounded,
                            'Two-Way\nDialogue',
                            AppColors.secondary,
                            () => context.push('/dialogue'),
                          ),
                          _buildQuickAction(
                            context,
                            Icons.menu_book_rounded,
                            'Sign\nDictionary',
                            AppColors.primaryDark,
                            () => context.push('/sign-dictionary'),
                          ),
                          _buildQuickAction(
                            context,
                            Icons.help_outline_rounded,
                            'Request\nHelp',
                            AppColors.emergency,
                            () => context.push('/assistance-request'),
                          ),
                          _buildQuickAction(
                            context,
                            Icons.confirmation_number_outlined,
                            'Queue\nTracking',
                            AppColors.accent,
                            () => context.push('/queue'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Venue session: active session card replaces the identification section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _session != null
                    ? _buildActiveSessionCard(context, _session!)
                    : _buildIdentifyLocationCard(context),
              ),
              const SizedBox(height: 24),

              // Announcements of the active venue session
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Announcements',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    TextButton(
                      onPressed: () => context.push('/announcements'),
                      child: const Text('View All'),
                    ),
                  ],
                ),
              ),
              if (_session == null)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: AppMessageBanner(
                    message:
                        'Start a venue session to receive official announcements '
                        'from your institution.',
                    type: AppMessageType.information,
                  ),
                )
              else if (_recentAnnouncements.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: AppMessageBanner(
                    message: 'No active announcements at this venue.',
                    type: AppMessageType.information,
                  ),
                )
              else
                ..._recentAnnouncements.map(
                  (announcement) => _buildAnnouncementCard(context, announcement),
                ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentifyLocationCard(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Identify Your Location',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Detect where you are or search for a participating institution.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search institution, airport, hotel...',
                prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: _venueActionStyle(),
                    onPressed: _detectCurrentLocation,
                    child: _venueActionContent(
                      _locating ? Icons.location_searching : Icons.near_me_outlined,
                      _locating ? 'Detecting…' : 'Use Current Location',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: _venueActionStyle(),
                    onPressed: _chooseOnMap,
                    child: _venueActionContent(
                      Icons.map_outlined,
                      'Choose on Map',
                    ),
                  ),
                ),
              ],
            ),
            if (_searching || _matching) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_locationStatus != null) ...[
              const SizedBox(height: 12),
              AppMessageBanner(
                message: _locationStatus!,
                type: AppMessageType.information,
              ),
            ],
            if (_searchError != null) ...[
              const SizedBox(height: 12),
              AppMessageBanner(
                message: _searchError!,
                type: AppMessageType.error,
              ),
            ],
            if (_locationError != null) ...[
              const SizedBox(height: 12),
              AppMessageBanner(
                message: _locationError!,
                type: AppMessageType.error,
              ),
            ],
            if (!_searching &&
                _searchController.text.trim().isNotEmpty &&
                _searchError == null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              if (_searchResults.isEmpty)
                const AppMessageBanner(
                  message: 'No matching participating institution was found.',
                  type: AppMessageType.information,
                )
              else
                ..._searchResults.map(_buildVenueOption),
            ],
            if (_detectedVenues.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              const Text(
                'Institutions near your location — choose one to connect.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              ..._detectedVenues.map(_buildVenueOption),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionCard(BuildContext context, VenueSession session) {
    final startedAt = session.startedAt;
    final startedLabel =
        '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.location_on, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.successLight,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Venue session active',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    Text(
                      session.institutionName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${session.branch ?? 'Participating venue'} • since $startedLabel',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _quitSession,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Quit Venue Session'),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _venueActionStyle() => OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(40),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
  );

  Widget _venueActionContent(IconData icon, String label) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16),
      const SizedBox(width: 5),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1),
        ),
      ),
    ],
  );

  Widget _buildVenueOption(VenueSearchResult venue) {
    final distance = venue.distanceLabel;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _confirmAndEstablish(venue),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.account_balance_outlined,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    venue.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    distance.isEmpty ? venue.branch : '${venue.branch} • $distance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 19),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnouncementCard(
    BuildContext context,
    Announcement announcement,
  ) {
    final captured = announcement.isCaptured;
    final urgent = announcement.isUrgent;
    final color = captured
        ? AppColors.accent
        : announcement.priority == 'urgent'
        ? AppColors.emergency
        : urgent
        ? AppColors.secondary
        : AppColors.primary;
    final icon = captured
        ? Icons.mic_outlined
        : switch (announcement.type) {
            'boarding' => Icons.flight_takeoff,
            'delay_cancellation' => Icons.schedule,
            'emergency' => Icons.warning_amber_rounded,
            'travel_update' => Icons.swap_horiz,
            _ => Icons.campaign_outlined,
          };
    final elapsed = DateTime.now().difference(announcement.publishedAt);
    final time = elapsed.inMinutes < 1
        ? 'Just now'
        : elapsed.inMinutes < 60
        ? '${elapsed.inMinutes} min ago'
        : '${elapsed.inHours} hr ago';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: urgent && !captured
              ? BorderSide(color: color, width: 1)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/announcement-details?id=${announcement.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
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
                              announcement.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Text(
                            time,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      if (captured) ...[
                        const SizedBox(height: 4),
                        _buildCapturedChip(announcement.confidence),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        announcement.messageEn,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildCapturedChip(double? confidence) {
    final label = confidence == null
        ? 'CAPTURED'
        : 'CAPTURED • ${(confidence * 100).round()}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

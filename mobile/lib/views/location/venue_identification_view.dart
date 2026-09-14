import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../models/entities/announcement.dart';
import '../../models/entities/venue_search_result.dart';
import '../../models/entities/venue_session.dart';
import '../../models/entities/venue_service_area.dart';
import '../../models/repositories/announcement_repository.dart';
import '../../models/repositories/captured_announcement_store.dart';
import '../../models/repositories/feature_usage_repository.dart';
import '../../models/repositories/home_guidance_repository.dart';
import '../../models/repositories/venue_repository.dart';
import '../../services/venue_session_service.dart';
import '../../widgets/app_message_banner.dart';
import '../../widgets/home_guidance_overlay.dart';
import '../widgets/notification_bell_button.dart';

enum _HomeTourStep {
  quickActions,
  locationChoice,
  spokenAnnouncements,
  officialAnnouncements,
  queueTracking,
}

class VenueIdentificationView extends StatefulWidget {
  const VenueIdentificationView({super.key, this.forceTour = false});

  /// Used only by the Help Center's replay action. Normal first-login checks
  /// still decide whether the tour opens on its own.
  final bool forceTour;

  @override
  State<VenueIdentificationView> createState() =>
      _VenueIdentificationViewState();
}

class _VenueIdentificationViewState extends State<VenueIdentificationView>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _venueRepository = VenueRepository();
  final _announcementRepository = AnnouncementRepository();
  final _homeGuidanceRepository = HomeGuidanceRepository();

  final _quickActionsKey = GlobalKey();
  final _queueTrackingKey = GlobalKey();
  final _locationCardKey = GlobalKey();
  final _spokenAnnouncementsKey = GlobalKey();
  final _officialAnnouncementsKey = GlobalKey();

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

  // Kept separate so captured speech never appears as an official broadcast.
  List<Announcement> _recentSpokenAnnouncements = [];
  List<Announcement> _recentOfficialAnnouncements = [];
  RealtimeChannel? _announcementChannel;

  VenueSession? _session;
  _HomeTourStep? _tourStep;
  bool _tourCheckStarted = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHomeTour());
  }

  @override
  void didUpdateWidget(covariant VenueIdentificationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceTour && !oldWidget.forceTour) {
      _tourCheckStarted = false;
      _loadHomeTour();
    }
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
    _scrollController.dispose();
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
    try {
      final session = VenueSessionService.instance.session;
      final spoken = await CapturedAnnouncementStore.instance.announcements();
      final official = session == null
          ? const <Announcement>[]
          : await _announcementRepository.getActiveAnnouncements(
              institutionId: session.institutionId,
              serviceAreaId: session.serviceAreaId,
            );
      if (mounted) {
        setState(() {
          _recentSpokenAnnouncements = spoken.take(2).toList();
          _recentOfficialAnnouncements = official.take(2).toList();
        });
      }
    } catch (_) {
      // The full announcement page exposes official-feed errors. Keep the home
      // preview quiet while any source is temporarily unavailable.
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
        _searchError = 'Unable to search registered institutions right now.';
      });
    }
  }

  /// Detects the traveller's position with the same permission flow and
  /// accuracy settings used by the request-help location picker (FR-M2-02).
  Future<void> _detectCurrentLocation() async {
    if (_locating || _matching) return;
    FeatureUsageTracker.instance.opened(TrackedFeature.gpsLocation);
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
              'Search for your institution instead.';
        });
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      FeatureUsageTracker.instance.completed(TrackedFeature.gpsLocation);
      if (!mounted) return;
      setState(
        () => _locationStatus = 'Matching against registered institutions…',
      );
      await _handleDetectedPosition(position.latitude, position.longitude);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationStatus = null;
        _locationError = 'Unable to detect your current location. Search for your institution instead.';
      });
    }
  }

  /// Compares the detected position against service areas first. Institutions
  /// are only matched directly when they have not configured service areas.
  Future<void> _handleDetectedPosition(
    double latitude,
    double longitude,
  ) async {
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
        await _confirmAndEstablish(
          match.venue,
          serviceArea: match.serviceArea,
          autoSuggested: true,
        );
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
            ? 'No registered institution was found near this location. '
                  'Search for your institution manually instead.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _matching = false;
        _locationStatus = null;
        _locationError = 'Unable to match your location against the institution list right now.';
      });
    }
  }

  /// A manual institution selection asks for the current service area when
  /// the institution has configured one or more active areas.
  Future<void> _selectInstitution(VenueSearchResult venue) async {
    if (_matching) return;
    setState(() {
      _matching = true;
      _searchError = null;
      _locationError = null;
    });
    List<VenueServiceArea> serviceAreas;
    try {
      serviceAreas = await _venueRepository.getActiveServiceAreas(venue.id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _matching = false;
          _searchError = 'Unable to load this institution\'s service areas.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _matching = false);
    if (serviceAreas.isEmpty) {
      await _confirmAndEstablish(venue);
      return;
    }
    final serviceArea = await _chooseServiceArea(venue, serviceAreas);
    if (serviceArea == null || !mounted) return;
    await _confirmAndEstablish(venue, serviceArea: serviceArea);
  }

  Future<VenueServiceArea?> _chooseServiceArea(
    VenueSearchResult venue,
    List<VenueServiceArea> serviceAreas,
  ) {
    return showDialog<VenueServiceArea>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose your service area'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Where are you currently at ${venue.name}?'),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: serviceAreas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final area = serviceAreas[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(area.name),
                      subtitle: area.address == null || area.address!.isEmpty
                          ? null
                          : Text(area.address!),
                      onTap: () => Navigator.pop(dialogContext, area),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Requires the traveller to confirm the resolved session before it starts.
  Future<void> _confirmAndEstablish(
    VenueSearchResult venue, {
    VenueServiceArea? serviceArea,
    bool autoSuggested = false,
  }) async {
    final locationLabel = serviceArea == null
        ? venue.name
        : '${venue.name} — ${serviceArea.name}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start venue session?'),
        content: Text(
          autoSuggested
              ? 'You appear to be at $locationLabel. Start a venue session to '
                    'receive its official announcements and location services?'
              : 'Connect to $locationLabel to receive its official '
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
        serviceAreaId: serviceArea?.id,
        serviceAreaName: serviceArea?.name,
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

  Future<void> _loadHomeTour() async {
    if (_tourCheckStarted) return;
    _tourCheckStarted = true;
    final shouldShow =
        widget.forceTour || await _homeGuidanceRepository.shouldShowHomeTour();
    if (!mounted || !shouldShow) return;
    _setTourStep(_HomeTourStep.quickActions);
  }

  void _setTourStep(_HomeTourStep step) {
    if (!mounted) return;
    setState(() => _tourStep = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _targetKeyFor(step).currentContext;
      if (targetContext == null || !mounted) return;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.24,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  GlobalKey _targetKeyFor(_HomeTourStep step) => switch (step) {
    _HomeTourStep.quickActions => _quickActionsKey,
    _HomeTourStep.locationChoice => _locationCardKey,
    _HomeTourStep.spokenAnnouncements => _spokenAnnouncementsKey,
    _HomeTourStep.officialAnnouncements => _officialAnnouncementsKey,
    _HomeTourStep.queueTracking => _queueTrackingKey,
  };

  void _advanceHomeTour() {
    final nextStep = switch (_tourStep) {
      _HomeTourStep.quickActions => _HomeTourStep.locationChoice,
      _HomeTourStep.locationChoice => _HomeTourStep.spokenAnnouncements,
      _HomeTourStep.spokenAnnouncements => _HomeTourStep.officialAnnouncements,
      _HomeTourStep.officialAnnouncements => _HomeTourStep.queueTracking,
      _HomeTourStep.queueTracking || null => null,
    };
    if (nextStep == null) {
      unawaited(_finishTour());
    } else {
      _setTourStep(nextStep);
    }
  }

  Future<void> _finishTour() async {
    if (!mounted) return;
    setState(() {
      _tourStep = null;
    });
    try {
      await _homeGuidanceRepository.markHomeTourComplete();
    } catch (_) {
      // The local/home-account persistence layer already has its own recovery
      // path. Never keep the traveller trapped in a tour due to a storage issue.
    }
  }

  Widget _buildHomeGuidanceOverlay() {
    final step = _tourStep;
    if (step == null) return const SizedBox.shrink();

    switch (step) {
      case _HomeTourStep.quickActions:
        return _buildTourStepOverlay(
          targetKey: _quickActionsKey,
          title: 'Quick Actions',
          message: 'Your key tools are here.',
          showSwipeHint: true,
        );
      case _HomeTourStep.locationChoice:
        return _buildTourStepOverlay(
          targetKey: _locationCardKey,
          title: 'Your Location',
          message: _session == null
              ? 'Find your venue with search or GPS.'
              : 'Your active venue is shown here.',
        );
      case _HomeTourStep.spokenAnnouncements:
        return _buildTourStepOverlay(
          targetKey: _spokenAnnouncementsKey,
          title: 'Spoken Announcements',
          message: 'Captured speech appears here.',
        );
      case _HomeTourStep.officialAnnouncements:
        return _buildTourStepOverlay(
          targetKey: _officialAnnouncementsKey,
          title: 'Official Announcements',
          message: 'Verified venue updates appear here.',
        );
      case _HomeTourStep.queueTracking:
        return _buildTourStepOverlay(
          targetKey: _queueTrackingKey,
          title: 'Queue Tracking',
          message: 'Track your queue number here.',
        );
    }
  }

  Widget _buildTourStepOverlay({
    required GlobalKey targetKey,
    required String title,
    required String message,
    bool showSwipeHint = false,
  }) => HomeGuidanceOverlay(
    targetKey: targetKey,
    scrollController: _scrollController,
    title: title,
    message: message,
    showSwipeHint: showSwipeHint,
    onSkip: _advanceHomeTour,
    skipLabel: 'Skip',
    actions: [
      HomeGuidanceAction(
        label: 'Next',
        isPrimary: true,
        onPressed: _advanceHomeTour,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineLarge,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Where are you traveling today?',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const NotificationBellButton(),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Quick Actions',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          key: _quickActionsKey,
                          height: 100,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _buildQuickAction(
                                Icons.sign_language_rounded,
                                'Sign\nTranslate',
                                AppColors.primary,
                                () => context.push('/sign-camera'),
                              ),
                              _buildQuickAction(
                                Icons.forum_rounded,
                                'Two-Way\nDialogue',
                                AppColors.secondary,
                                () => context.push('/dialogue'),
                              ),
                              _buildQuickAction(
                                Icons.menu_book_rounded,
                                'Sign\nDictionary',
                                AppColors.success,
                                () => context.push('/sign-dictionary'),
                              ),
                              _buildQuickAction(
                                Icons.help_outline_rounded,
                                'Request\nHelp',
                                AppColors.emergency,
                                () => context.go('/assistance-request'),
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
                    key: _locationCardKey,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _session != null
                        ? _buildActiveSessionCard(context, _session!)
                        : _buildIdentifyLocationCard(context),
                  ),
                  const SizedBox(height: 24),

                  Padding(
                    key: _spokenAnnouncementsKey,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildHomeFeatureCard(
                      context,
                      icon: Icons.mic_outlined,
                      title: 'Spoken Announcements',
                      description: _announcementSummary(
                        _recentSpokenAnnouncements,
                        emptyMessage:
                            'No spoken announcements have been captured yet.',
                        itemLabel: 'captured announcement',
                      ),
                      color: AppColors.accent,
                      onTap: () => context.push('/announcements?type=spoken'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    key: _officialAnnouncementsKey,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildHomeFeatureCard(
                      context,
                      icon: Icons.campaign_outlined,
                      title: 'Official Announcements',
                      description: _session == null
                          ? 'Start a venue session to view official announcements.'
                          : _announcementSummary(
                              _recentOfficialAnnouncements,
                              emptyMessage: 'No active official announcements in this service area.',
                              itemLabel: 'active announcement',
                            ),
                      color: AppColors.primary,
                      onTap: () => _openVenueFeature(
                        featureName: 'Official Announcements',
                        route: '/announcements?type=official',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    key: _queueTrackingKey,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildQueueTrackingCard(context),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
        if (_tourStep != null)
          Positioned.fill(child: _buildHomeGuidanceOverlay()),
      ],
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
              'Detect where you are or search for a registered institution.',
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
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: _venueActionStyle(),
                onPressed: _locating || _matching
                    ? null
                    : _detectCurrentLocation,
                child: _venueActionContent(
                  _locating ? Icons.location_searching : Icons.near_me_outlined,
                  _locating ? 'Detecting…' : 'Use Current Location',
                ),
              ),
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
                  message: 'No matching registered institution was found.',
                  type: AppMessageType.error,
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
                child: const Icon(
                  Icons.location_on,
                  color: Colors.white,
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
                      '${session.serviceAreaName ?? session.branch ?? 'Institution-wide'} • since $startedLabel',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
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
      onTap: () => _selectInstitution(venue),
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
                    distance.isEmpty
                        ? venue.branch
                        : '${venue.branch} • $distance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textMuted,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueTrackingCard(BuildContext context) {
    final session = _session;
    final description = session == null
        ? 'Identify your institution above, then check whether queue tracking is available.'
        : 'Track a queue number and view live serving information at ${session.institutionName}.';

    return _buildHomeFeatureCard(
      context,
      icon: Icons.confirmation_number_outlined,
      title: 'Queue Tracking',
      description: description,
      color: AppColors.accent,
      onTap: () =>
          _openVenueFeature(featureName: 'Queue Tracking', route: '/queue'),
    );
  }

  Future<void> _openVenueFeature({
    required String featureName,
    required String route,
  }) async {
    if (_session != null) {
      await context.push(route);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.location_off_outlined),
        title: const Text('Active venue session required'),
        content: Text(
          'Start a venue session before using $featureName. Identify your current institution in the location section above.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.textMuted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right_rounded, color: color, size: 26),
            ],
          ),
        ),
      ),
    );
  }

  String _announcementSummary(
    List<Announcement> announcements, {
    required String emptyMessage,
    required String itemLabel,
  }) {
    if (announcements.isEmpty) return emptyMessage;
    final count = announcements.length;
    final label = count == 1 ? itemLabel : '${itemLabel}s';
    return '$count recent $label. Latest: ${announcements.first.title}';
  }

  Widget _buildQuickAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Semantics(
      button: true,
      label: label.replaceAll('\n', ' '),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 88,
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
      ),
    );
  }
}

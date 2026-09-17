import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme.dart';
import '../../models/entities/announcement.dart';
import '../../models/entities/venue_search_result.dart';
import '../../models/entities/venue_information.dart';
import '../../models/entities/venue_session.dart';
import '../../models/entities/venue_service_area.dart';
import '../../models/repositories/announcement_repository.dart';
import '../../models/repositories/auth_repository.dart';
import '../../models/repositories/spoken_announcement_repository.dart';
import '../../models/repositories/feature_usage_repository.dart';
import '../../services/app_tour_controller.dart';
import '../../models/repositories/venue_repository.dart';
import '../../services/app_tour_controller.dart';
import '../../viewmodels/venue_identification_viewmodel.dart';
import '../../widgets/app_message_banner.dart';
import '../../widgets/home_guidance_overlay.dart';
import '../widgets/notification_bell_button.dart';

enum _HomeTourStep {
  quickActions,
  activeVenueSession,
  quitVenueSession,
  locationSearch,
  locationGps,
  // locationResults,
  spokenAnnouncements,
  officialAnnouncements,
  queueTracking,
}

class VenueIdentificationView extends StatefulWidget {
  const VenueIdentificationView({super.key, this.forceTour = false});

  /// Supports an explicit complete-tour entry point. Normal first-login
  /// checks still decide whether the tour opens on its own.
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
  final _authRepository = AuthRepository();
  final _viewModel = VenueIdentificationViewModel();
  int _appliedSearchInputResetVersion = 0;

  final _quickActionsKey = GlobalKey();
  final _locationCardKey = GlobalKey();
  final _quitVenueSessionKey = GlobalKey();
  final _locationSearchKey = GlobalKey();
  final _locationGpsKey = GlobalKey();
  final _spokenAnnouncementsKey = GlobalKey();
  final _officialAnnouncementsKey = GlobalKey();
  final _queueTrackingKey = GlobalKey();

  List<VenueSearchResult> get _searchResults => _viewModel.searchResults;
  bool get _searching => _viewModel.searching;
  String? get _searchError => _viewModel.searchError;

  // Location detection (reuses the request-help module's detection settings).
  bool get _locating => _viewModel.locating;
  bool get _matching => _viewModel.matching;
  String? get _locationStatus => _viewModel.locationStatus;
  String? get _locationError => _viewModel.locationError;

  /// Location-based results retain their service-area match, so selecting an
  /// overlapping area can go straight to the normal session confirmation.
  List<VenueLocationMatch> get _detectedVenues => _viewModel.detectedVenues;
  List<VenueLocationMatch> get _manualServiceAreaOptions =>
      _viewModel.manualServiceAreaOptions;

  // Kept separate so captured speech never appears as an official broadcast.
  List<Announcement> get _recentSpokenAnnouncements =>
      _viewModel.recentSpokenAnnouncements;
  List<Announcement> get _recentOfficialAnnouncements =>
      _viewModel.recentOfficialAnnouncements;

  VenueSession? get _session => _viewModel.session;
  VenuePublicInformation? get _venueInformation => _viewModel.venueInformation;
  VenueServiceArea? get _activeServiceArea => _viewModel.activeServiceArea;
  bool get _loadingVenueInformation => _viewModel.loadingVenueInformation;
  _HomeTourStep? _tourStep;
  bool _tourCheckStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel.addListener(_syncSearchInput);
    unawaited(_viewModel.initialize());
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
    if (state == AppLifecycleState.resumed) _viewModel.onAppResumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.removeListener(_syncSearchInput);
    _searchController.dispose();
    _scrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _syncSearchInput() {
    final revision = _viewModel.searchInputResetVersion;
    if (revision == _appliedSearchInputResetVersion) return;
    _appliedSearchInputResetVersion = revision;
    scheduleMicrotask(() {
      if (mounted) _searchController.clear();
    });
  }

  /// A manual institution selection can either open service-area choices or
  /// proceed to the existing view-owned confirmation dialog.
  Future<void> _selectInstitution(VenueSearchResult venue) async {
    if (await _viewModel.selectInstitution(venue) && mounted) {
      await _confirmAndEstablish(venue);
    }
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
    await _viewModel.establishSession(venue, serviceArea: serviceArea);
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
    await _viewModel.quitSession();
  }

  /// First word of the signed-in traveller's full name, kept in sync with the
  /// auth user metadata (set at sign-up and refreshed on profile updates).
  String get _greetingName {
    final fullName = _authRepository.currentUser?.userMetadata?['full_name'];
    if (fullName is String && fullName.trim().isNotEmpty) {
      return fullName.trim().split(RegExp(r'\s+')).first;
    }
    return 'traveller';
  }

  Future<void> _loadHomeTour() async {
    if (_tourCheckStarted) return;
    _tourCheckStarted = true;
    final shouldShow = await AppTourController.instance.start(
      force: widget.forceTour,
    );
    if (!mounted || !shouldShow) return;
    _setTourStep(_initialTourStep());
  }

  _HomeTourStep _initialTourStep() =>
      switch (AppTourController.instance.homeSection) {
        HomeGuideSection.location =>
          _session == null
              ? _HomeTourStep.locationSearch
              : _HomeTourStep.activeVenueSession,
        HomeGuideSection.spokenAnnouncements =>
          _HomeTourStep.spokenAnnouncements,
        HomeGuideSection.officialAnnouncements =>
          _HomeTourStep.officialAnnouncements,
        HomeGuideSection.queueTracking => _HomeTourStep.queueTracking,
        HomeGuideSection.quickActions || null => _HomeTourStep.quickActions,
      };

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
    _HomeTourStep.activeVenueSession => _locationCardKey,
    _HomeTourStep.quitVenueSession => _quitVenueSessionKey,
    _HomeTourStep.locationSearch => _locationSearchKey,
    _HomeTourStep.locationGps => _locationGpsKey,
    // _HomeTourStep.locationResults => _locationCardKey,
    _HomeTourStep.spokenAnnouncements => _spokenAnnouncementsKey,
    _HomeTourStep.officialAnnouncements => _officialAnnouncementsKey,
    _HomeTourStep.queueTracking => _queueTrackingKey,
  };

  void _advanceHomeTour() {
    if (AppTourController.instance.homeSection != null) {
      _leaveHomeTour();
      return;
    }
    final nextStep = switch (_tourStep) {
      _HomeTourStep.quickActions =>
        _session == null
            ? _HomeTourStep.locationSearch
            : _HomeTourStep.activeVenueSession,
      _HomeTourStep.activeVenueSession => _HomeTourStep.quitVenueSession,
      _HomeTourStep.quitVenueSession => _HomeTourStep.spokenAnnouncements,
      _HomeTourStep.locationSearch => _HomeTourStep.locationGps,
      _HomeTourStep.locationGps => _HomeTourStep.spokenAnnouncements,
      // _HomeTourStep.locationResults => _HomeTourStep.spokenAnnouncements,
      _HomeTourStep.spokenAnnouncements => _HomeTourStep.officialAnnouncements,
      _HomeTourStep.officialAnnouncements => _HomeTourStep.queueTracking,
      _HomeTourStep.queueTracking || null => null,
    };
    if (nextStep == null) {
      _leaveHomeTour();
    } else {
      _setTourStep(nextStep);
    }
  }

  void _leaveHomeTour() {
    if (!mounted) return;
    setState(() => _tourStep = null);
    AppTourController.instance.leaveHome(context);
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
        );
      case _HomeTourStep.activeVenueSession:
        return _buildTourStepOverlay(
          targetKey: _locationCardKey,
          title: 'Active Venue Session',
          message: 'You are connected to this venue and service area. Official announcements and queue information are matched to this session.',
        );
      case _HomeTourStep.quitVenueSession:
        return _buildTourStepOverlay(
          targetKey: _quitVenueSessionKey,
          title: 'End Venue Session',
          message: 'Use this when you leave the venue. You will stop receiving its location-based announcements.',
        );
      case _HomeTourStep.locationSearch:
        return _buildTourStepOverlay(
          targetKey: _locationSearchKey,
          title: 'Search location',
          message: 'Type your venue or destination here.',
        );
      case _HomeTourStep.locationGps:
        return _buildTourStepOverlay(
          targetKey: _locationGpsKey,
          title: 'Use GPS',
          message: 'Or use your current location to find nearby venues.',
        );
      // case _HomeTourStep.locationResults:
      //   return _buildTourStepOverlay(
      //     targetKey: _locationCardKey,
      //     title: 'Choose a result',
      //     message: 'Matching venues appear here. Select one to connect.',
      //   );
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
          message: 'In queue? Track your queue number here.',
        );
    }
  }

  Widget _buildTourStepOverlay({
    required GlobalKey targetKey,
    required String title,
    required String message,
  }) => HomeGuidanceOverlay(
    targetKey: targetKey,
    scrollController: _scrollController,
    title: title,
    message: message,
    onSkip: _skipTour,
    skipLabel: 'Skip',
    actions: [
      HomeGuidanceAction(
        label: 'Next',
        isPrimary: true,
        onPressed: _advanceHomeTour,
      ),
    ],
  );

  Future<void> _skipTour() async {
    final skipped = await AppTourController.instance.confirmAndSkip(context);
    if (skipped && mounted) setState(() => _tourStep = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hello, $_greetingName',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineLarge,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Where are you traveling today?',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
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
              'Detect where you are or search for a registered institution.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              key: _locationSearchKey,
              controller: _searchController,
              onChanged: _viewModel.searchVenues,
              decoration: const InputDecoration(
                hintText: 'Search institution, airport, hotel...',
                prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              key: _locationGpsKey,
              width: double.infinity,
              child: OutlinedButton(
                style: _venueActionStyle(),
                onPressed: _locating || _matching
                    ? null
                    : _viewModel.detectCurrentLocation,
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
            if (_manualServiceAreaOptions.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              const Text(
                'Choose your service area.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              ..._manualServiceAreaOptions.map(
                (match) => _buildLocationMatchOption(match),
              ),
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
              ..._detectedVenues.map(
                (match) =>
                    _buildLocationMatchOption(match, autoSuggested: true),
              ),
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
    final information = _venueInformation;
    final serviceArea = _activeServiceArea;
    final latitude = serviceArea?.latitude ?? information?.latitude;
    final longitude = serviceArea?.longitude ?? information?.longitude;
    final radiusMeters =
        serviceArea?.radiusMeters ?? information?.radiusMeters ?? 500;
    final coverageName =
        serviceArea?.name ??
        session.serviceAreaName ??
        'Institution service area';
    final address = serviceArea?.address ?? information?.address;
    final hotline = information?.hotline;

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
                        Text(
                          'Venue session active since $startedLabel',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
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
                      coverageName,
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
          Container(
            padding: const EdgeInsets.all(8),
            child: _loadingVenueInformation
                ? const SizedBox(
                    height: 72,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (latitude != null && longitude != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 180,
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: LatLng(latitude, longitude),
                                zoom: _zoomForRadius(radiusMeters),
                              ),
                              markers: {
                                Marker(
                                  markerId: const MarkerId('service-area'),
                                  position: LatLng(latitude, longitude),
                                  infoWindow: InfoWindow(title: coverageName),
                                ),
                              },
                              circles: {
                                Circle(
                                  circleId: const CircleId('service-coverage'),
                                  center: LatLng(latitude, longitude),
                                  radius: radiusMeters,
                                  fillColor: AppColors.primary.withValues(
                                    alpha: 0.16,
                                  ),
                                  strokeColor: AppColors.primary,
                                  strokeWidth: 2,
                                ),
                              },
                              zoomControlsEnabled: false,
                              myLocationButtonEnabled: false,
                              mapToolbarEnabled: false,
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 10),
                        const Text(
                          'This institution has not provided map coverage yet.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (address != null && address.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildVenueDetail(
                          Icons.location_on_outlined,
                          'Address',
                          address.trim(),
                        ),
                      ],
                      if (hotline != null && hotline.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _buildVenueDetail(
                          Icons.support_agent_outlined,
                          'Support hotline',
                          hotline.trim(),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            key: _quitVenueSessionKey,
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

  Widget _buildVenueDetail(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: Colors.white),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    ],
  );

  double _zoomForRadius(double radiusMeters) {
    if (radiusMeters <= 150) return 17;
    if (radiusMeters <= 350) return 16;
    if (radiusMeters <= 900) return 15;
    if (radiusMeters <= 2000) return 14;
    return 13;
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

  Widget _buildVenueOption(VenueSearchResult venue) =>
      _buildVenueListItem(venue, onTap: () => _selectInstitution(venue));

  Widget _buildLocationMatchOption(
    VenueLocationMatch match, {
    bool autoSuggested = false,
  }) {
    final area = match.serviceArea;
    final detail = <String>[
      area?.name ?? match.venue.branch,
      if (area?.address?.trim().isNotEmpty ?? false) area!.address!.trim(),
      if (match.venue.distanceLabel.isNotEmpty) match.venue.distanceLabel,
    ].join(' • ');
    return _buildVenueListItem(
      match.venue,
      icon: Icons.location_on_outlined,
      subtitle: detail,
      onTap: () => _confirmAndEstablish(
        match.venue,
        serviceArea: area,
        autoSuggested: autoSuggested,
      ),
    );
  }

  Widget _buildVenueListItem(
    VenueSearchResult venue, {
    required VoidCallback onTap,
    String? subtitle,
    IconData icon = Icons.account_balance_outlined,
  }) {
    final distance = venue.distanceLabel;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
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
              child: Icon(icon, color: AppColors.primary, size: 20),
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
                    subtitle ??
                        (distance.isEmpty
                            ? venue.branch
                            : '${venue.branch} • $distance'),
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

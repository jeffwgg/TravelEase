import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/entities/announcement.dart';
import '../models/entities/venue_information.dart';
import '../models/entities/venue_search_result.dart';
import '../models/entities/venue_service_area.dart';
import '../models/entities/venue_session.dart';
import '../models/repositories/announcement_repository.dart';
import '../models/repositories/feature_usage_repository.dart';
import '../models/repositories/spoken_announcement_repository.dart';
import '../models/repositories/venue_repository.dart';
import '../services/venue_session_service.dart';

/// State and use-cases for Module 2 venue identification.
class VenueIdentificationViewModel extends ChangeNotifier {
  VenueIdentificationViewModel({
    VenueRepository? venueRepository,
    AnnouncementRepository? announcementRepository,
  }) : _venueRepository = venueRepository ?? VenueRepository(),
       _announcementRepository =
           announcementRepository ?? AnnouncementRepository();

  final VenueRepository _venueRepository;
  final AnnouncementRepository _announcementRepository;

  List<VenueSearchResult> searchResults = const [];
  bool searching = false;
  String? searchError;
  bool locating = false;
  bool matching = false;
  String? locationStatus;
  String? locationError;
  List<VenueLocationMatch> detectedVenues = const [];
  List<VenueLocationMatch> manualServiceAreaOptions = const [];
  List<Announcement> recentSpokenAnnouncements = [];
  List<Announcement> recentOfficialAnnouncements = [];
  RealtimeChannel? announcementChannel;
  VenueSession? session;
  VenuePublicInformation? venueInformation;
  VenueServiceArea? activeServiceArea;
  bool loadingVenueInformation = false;

  /// The view uses this to clear its text controller after GPS matching starts,
  /// without making a controller part of the view model.
  int searchInputResetVersion = 0;

  Timer? _searchDebounce;
  Timer? _feedRefreshTimer;
  String _activeSearchQuery = '';
  bool _initialized = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    session = VenueSessionService.instance.session;
    VenueSessionService.instance.addListener(_onSessionChanged);
    CapturedAnnouncementStore.instance.version.addListener(_onSessionChanged);
    _feedRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => refreshAnnouncementFeed(),
    );
    unawaited(loadVenueInformation(session));
    refreshAnnouncementFeed();
    _notify();
  }

  void onAppResumed() => refreshAnnouncementFeed();

  void _onSessionChanged() {
    if (_disposed) return;
    session = VenueSessionService.instance.session;
    _notify();
    unawaited(loadVenueInformation(session));
    refreshAnnouncementFeed();
  }

  Future<void> loadVenueInformation(VenueSession? nextSession) async {
    if (nextSession == null) {
      venueInformation = null;
      activeServiceArea = null;
      loadingVenueInformation = false;
      _notify();
      return;
    }
    loadingVenueInformation = true;
    _notify();
    try {
      final values = await Future.wait([
        _venueRepository.getPublicInformation(nextSession.institutionId),
        _venueRepository.getActiveServiceAreas(nextSession.institutionId),
      ]);
      if (_disposed || session?.institutionId != nextSession.institutionId) {
        return;
      }
      final areas = values[1] as List<VenueServiceArea>;
      VenueServiceArea? selectedArea;
      for (final area in areas) {
        if (area.id == nextSession.serviceAreaId) {
          selectedArea = area;
          break;
        }
      }
      venueInformation = values[0] as VenuePublicInformation?;
      activeServiceArea = selectedArea;
    } catch (_) {
      // Venue matching still works if the optional public profile cannot be
      // retrieved. Do not disrupt the traveller's active session.
    } finally {
      if (!_disposed && session?.institutionId == nextSession.institutionId) {
        loadingVenueInformation = false;
        _notify();
      }
    }
  }

  void refreshAnnouncementFeed() {
    if (_disposed) return;
    unawaited(loadRecentAnnouncements());
    unawaited(resubscribeToAnnouncements());
  }

  Future<void> loadRecentAnnouncements() async {
    try {
      final activeSession = VenueSessionService.instance.session;
      final spoken = await CapturedAnnouncementStore.instance.announcements();
      final official = activeSession == null
          ? const <Announcement>[]
          : await _announcementRepository.getActiveAnnouncements(
              institutionId: activeSession.institutionId,
              serviceAreaId: activeSession.serviceAreaId,
            );
      if (_disposed) return;
      recentSpokenAnnouncements = spoken.take(2).toList();
      recentOfficialAnnouncements = official.take(2).toList();
      _notify();
    } catch (_) {
      // The full announcement page exposes official-feed errors. Keep the home
      // preview quiet while any source is temporarily unavailable.
    }
  }

  Future<void> resubscribeToAnnouncements() async {
    final institutionId = VenueSessionService.instance.session?.institutionId;
    final previous = announcementChannel;
    announcementChannel = null;
    if (previous != null) {
      await _announcementRepository.removeSubscription(previous);
    }
    if (_disposed || institutionId == null) return;
    announcementChannel = _announcementRepository.subscribeToAnnouncements(
      loadRecentAnnouncements,
      institutionId: institutionId,
    );
  }

  void searchVenues(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    _activeSearchQuery = query;
    if (query.isEmpty) {
      searchResults = const [];
      manualServiceAreaOptions = const [];
      searchError = null;
      searching = false;
      _notify();
      return;
    }
    // Manual search and nearby-location results are different choice flows.
    // Hide the previous GPS suggestions as soon as the traveller starts typing
    // so only the manual search result list is presented.
    detectedVenues = const [];
    locationStatus = null;
    locationError = null;
    searching = true;
    searchError = null;
    _notify();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_searchVenues(query)),
    );
  }

  Future<void> _searchVenues(String query) async {
    try {
      final results = await _venueRepository.search(query);
      if (_disposed || _activeSearchQuery != query) return;
      searchResults = results;
      manualServiceAreaOptions = const [];
      searching = false;
    } catch (_) {
      if (_disposed || _activeSearchQuery != query) return;
      searchResults = const [];
      searching = false;
      searchError = 'Unable to search registered institutions right now.';
    }
    _notify();
  }

  /// Detects the traveller's position using the shared request-help location
  /// permission flow and accuracy settings (FR-M2-02).
  Future<void> detectCurrentLocation() async {
    if (locating || matching) return;
    FeatureUsageTracker.instance.opened(TrackedFeature.gpsLocation);
    locating = true;
    locationStatus = 'Detecting your location…';
    locationError = null;
    detectedVenues = const [];
    manualServiceAreaOptions = const [];
    _notify();
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (_disposed) return;
        locating = false;
        locationStatus = null;
        locationError =
            'Location permission is required to detect nearby institutions. '
            'Search for your institution instead.';
        _notify();
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      FeatureUsageTracker.instance.completed(TrackedFeature.gpsLocation);
      if (_disposed) return;
      locationStatus = 'Matching against registered institutions…';
      _notify();
      await matchDetectedPosition(position.latitude, position.longitude);
    } catch (_) {
      if (_disposed) return;
      locating = false;
      locationStatus = null;
      locationError = 'Unable to detect your current location. Search for your institution instead.';
      _notify();
    }
  }

  /// Compares a position against service areas first. Institutions are only
  /// matched directly when they have not configured service areas.
  Future<void> matchDetectedPosition(double latitude, double longitude) async {
    locating = false;
    matching = true;
    _activeSearchQuery = '';
    searchResults = const [];
    manualServiceAreaOptions = const [];
    searchError = null;
    searchInputResetVersion++;
    _notify();
    try {
      final matches = await _venueRepository.matchLocations(
        latitude: latitude,
        longitude: longitude,
      );
      if (_disposed) return;
      if (matches.isNotEmpty) {
        matching = false;
        locationStatus = null;
        detectedVenues = matches;
        _notify();
        return;
      }
      final nearby = await _venueRepository.nearby(
        latitude: latitude,
        longitude: longitude,
      );
      if (_disposed) return;
      matching = false;
      locationStatus = null;
      detectedVenues = nearby
          .map((venue) => VenueLocationMatch(venue: venue))
          .toList();
      locationError = nearby.isEmpty
          ? 'No registered institution was found near this location. '
                'Search for your institution manually instead.'
          : null;
    } catch (_) {
      if (_disposed) return;
      matching = false;
      locationStatus = null;
      locationError = 'Unable to match your location against the institution list right now.';
    }
    _notify();
  }

  /// Loads a selected institution's service areas. A `true` result tells the
  /// view that it may show its existing session-confirmation dialog directly.
  Future<bool> selectInstitution(VenueSearchResult venue) async {
    if (matching) return false;
    matching = true;
    searchError = null;
    locationError = null;
    _notify();
    try {
      final serviceAreas = await _venueRepository.getActiveServiceAreas(
        venue.id,
      );
      if (_disposed) return false;
      matching = false;
      if (serviceAreas.isEmpty) {
        _notify();
        return true;
      }
      manualServiceAreaOptions = serviceAreas
          .map((area) => VenueLocationMatch(venue: venue, serviceArea: area))
          .toList();
      _notify();
      return false;
    } catch (_) {
      if (_disposed) return false;
      matching = false;
      searchError = 'Unable to load this institution\'s service areas.';
      _notify();
      return false;
    }
  }

  Future<void> establishSession(
    VenueSearchResult venue, {
    VenueServiceArea? serviceArea,
  }) => VenueSessionService.instance.establish(
    VenueSession(
      institutionId: venue.id,
      institutionName: venue.name,
      branch: venue.branch,
      serviceAreaId: serviceArea?.id,
      serviceAreaName: serviceArea?.name,
      startedAt: DateTime.now(),
    ),
  );

  Future<void> quitSession() => VenueSessionService.instance.quit();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce?.cancel();
    _feedRefreshTimer?.cancel();
    VenueSessionService.instance.removeListener(_onSessionChanged);
    CapturedAnnouncementStore.instance.version.removeListener(
      _onSessionChanged,
    );
    final channel = announcementChannel;
    announcementChannel = null;
    if (channel != null) {
      unawaited(_announcementRepository.removeSubscription(channel));
    }
    super.dispose();
  }
}

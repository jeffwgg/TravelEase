import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/venue_session_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';
import '../views/auth/authentication_view.dart';
import '../views/auth/check_email_view.dart';
import '../views/auth/reset_password_view.dart';
import '../views/profile/profile_management_view.dart';
import '../views/profile/edit_profile_view.dart';
import '../views/profile/preferences_view.dart';
import '../views/profile/help_center_view.dart';
import '../views/profile/tour_complete_view.dart';
import '../views/profile/about_travelease_view.dart';
import '../views/emergency/emergency_contact_settings_view.dart';
import '../views/emergency/emergency_communication_card_view.dart';
import '../views/emergency/environment_sound_alert_view.dart';
import '../views/emergency/sos_countdown_view.dart';
import '../views/emergency/sos_active_view.dart';
import '../views/location/venue_identification_view.dart';
import '../views/location/announcement_view.dart';
import '../views/location/announcement_details_view.dart';
import '../views/location/queue_tracking_view.dart';
import '../views/location/notification_history_view.dart';
import '../views/communication/communication_hub_view.dart';
import '../views/communication/sign_translation_camera_view.dart';
import '../views/communication/speech_to_sign_view.dart';
import '../views/communication/two_way_dialogue_view.dart';
import '../views/sign_reference/sign_dictionary_view.dart';
import '../views/sign_reference/favorite_phrases_view.dart';
import '../views/sign_reference/sign_media_viewer_view.dart';
import '../views/assistance/assistance_request_view.dart';
import '../views/assistance/assistance_menu_view.dart';
import '../views/assistance/request_tracking_view.dart';
import '../views/assistance/chat_view.dart';
import '../views/assistance/accessibility_issue_view.dart';
import '../views/assistance/location_picker_view.dart';
import '../views/home/home_view.dart';

final AuthRouterNotifier _authRouterNotifier = AuthRouterNotifier();

final GoRouter appRouter = GoRouter(
  initialLocation: _authRouterNotifier.isAuthenticated ? '/home' : '/auth',
  refreshListenable: Listenable.merge([
    VenueSessionService.instance,
    _authRouterNotifier,
  ]),
  redirect: (context, state) {
    final path = state.uri.path;
    final isAuthenticated = _authRouterNotifier.isAuthenticated;
    if (path == '/check-email' || path == '/reset-password') return null;
    if (!isAuthenticated && path != '/auth') return '/auth';
    if (isAuthenticated && path == '/auth') return '/home';
    return null;
  },
  routes: [
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthenticationView(),
    ),
    GoRoute(
      path: '/check-email',
      builder: (context, state) =>
          CheckEmailView(email: state.uri.queryParameters['email']),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) => const ResetPasswordView(),
    ),
    // Main app with bottom nav
    ShellRoute(
      builder: (context, state, child) => HomeView(child: child),
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) =>
              _HomeTab(forceTour: state.uri.queryParameters['tour'] == '1'),
        ),
        GoRoute(
          path: '/communicate',
          builder: (context, state) => const _CommunicateTab(),
        ),
        GoRoute(
          path: '/assistance-request',
          builder: (context, state) => const _AssistanceTab(),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const _ProfileTab(),
        ),
      ],
    ),
    // Standalone routes
    GoRoute(
      path: '/profile/edit',
      builder: (context, state) => const EditProfileView(),
    ),
    GoRoute(
      path: '/preferences',
      builder: (context, state) => const PreferencesView(),
    ),
    GoRoute(
      path: '/help-center',
      builder: (context, state) => const HelpCenterView(),
    ),
    GoRoute(
      path: '/tour-complete',
      builder: (context, state) => const TourCompleteView(),
    ),
    GoRoute(
      path: '/about',
      builder: (context, state) => const AboutTravelEaseView(),
    ),
    GoRoute(
      path: '/emergency-contacts',
      builder: (context, state) => const EmergencyContactSettingsView(),
    ),
    GoRoute(
      path: '/emergency-card',
      builder: (context, state) => const EmergencyCommunicationCardView(),
    ),
    GoRoute(
      path: '/environment-sound-alert',
      builder: (context, state) => const EnvironmentSoundAlertView(),
    ),
    GoRoute(
      path: '/sos-countdown',
      builder: (context, state) => const SosCountdownView(),
    ),
    GoRoute(
      path: '/sos-active',
      builder: (context, state) => const SosActiveView(),
    ),
    GoRoute(
      path: '/venue',
      builder: (context, state) => const VenueIdentificationView(),
    ),
    GoRoute(
      path: '/announcements',
      builder: (context, state) => AnnouncementView(
        feed: state.uri.queryParameters['type'] == 'spoken'
            ? AnnouncementFeed.spoken
            : AnnouncementFeed.official,
      ),
    ),
    GoRoute(
      path: '/announcement-details',
      builder: (context, state) =>
          AnnouncementDetailsView(id: state.uri.queryParameters['id'] ?? ''),
    ),
    GoRoute(
      path: '/queue',
      builder: (context, state) => const QueueTrackingView(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationHistoryView(),
    ),
    GoRoute(
      path: '/sign-camera',
      builder: (context, state) => const SignTranslationCameraView(),
    ),
    GoRoute(
      path: '/speech-to-sign',
      builder: (context, state) => const SpeechToSignView(),
    ),
    GoRoute(
      path: '/dialogue',
      builder: (context, state) => const TwoWayDialogueView(),
    ),
    GoRoute(
      path: '/sign-dictionary',
      builder: (context, state) => const SignDictionaryView(),
    ),
    GoRoute(
      path: '/favorite-phrases',
      builder: (context, state) => const FavoritePhrasesView(),
    ),
    GoRoute(
      path: '/sign-media',
      builder: (context, state) => const SignMediaViewerView(),
    ),
    GoRoute(
      path: '/request-tracking',
      builder: (context, state) => const RequestTrackingView(),
    ),
    GoRoute(
      path: '/assistance-request/new',
      builder: (context, state) => const AssistanceRequestView(),
    ),
    GoRoute(
      path: '/chat',
      builder: (context, state) {
        final requestId = state.uri.queryParameters['requestId'] ?? '';
        return ChatView(requestId: requestId);
      },
    ),
    GoRoute(
      path: '/accessibility-issue',
      builder: (context, state) => const AccessibilityIssueView(),
    ),
    GoRoute(
      path: '/location-picker',
      builder: (context, state) => const LocationPickerView(),
    ),
  ],
);

class AuthRouterNotifier extends ChangeNotifier {
  AuthRouterNotifier() {
    _subscription = SupabaseClientHelper.client.auth.onAuthStateChange.listen(
      (_) => notifyListeners(),
    );
  }

  late final StreamSubscription<AuthState> _subscription;

  bool get isAuthenticated =>
      SupabaseClientHelper.client.auth.currentSession != null;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// Tab placeholder widgets that build the actual tab content
class _HomeTab extends StatelessWidget {
  const _HomeTab({this.forceTour = false});

  final bool forceTour;

  @override
  Widget build(BuildContext context) {
    return VenueIdentificationView(forceTour: forceTour);
  }
}

class _CommunicateTab extends StatelessWidget {
  const _CommunicateTab();

  @override
  Widget build(BuildContext context) {
    return const CommunicationHubView();
  }
}

class _AssistanceTab extends StatelessWidget {
  const _AssistanceTab();

  @override
  Widget build(BuildContext context) {
    return const AssistanceMenuView();
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    return const ProfileManagementView();
  }
}

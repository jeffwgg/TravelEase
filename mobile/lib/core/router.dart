import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../views/auth/authentication_view.dart';
import '../views/profile/profile_management_view.dart';
import '../views/profile/preferences_view.dart';
import '../views/emergency/emergency_contact_settings_view.dart';
import '../views/emergency/emergency_communication_card_view.dart';
import '../views/emergency/environment_sound_alert_view.dart';
import '../views/location/venue_identification_view.dart';
import '../views/location/announcement_view.dart';
import '../views/location/emergency_alert_view.dart';
import '../views/location/queue_tracking_view.dart';
import '../views/location/notification_history_view.dart';
import '../views/communication/sign_translation_camera_view.dart';
import '../views/communication/speech_to_sign_view.dart';
import '../views/communication/two_way_dialogue_view.dart';
import '../views/sign_reference/sign_dictionary_view.dart';
import '../views/sign_reference/favorite_phrases_view.dart';
import '../views/sign_reference/sign_media_viewer_view.dart';
import '../views/assistance/assistance_request_view.dart';
import '../views/assistance/request_tracking_view.dart';
import '../views/assistance/chat_view.dart';
import '../views/assistance/accessibility_issue_view.dart';
import '../views/home/home_view.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/auth',
  routes: [
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthenticationView(),
    ),
    // Main app with bottom nav
    ShellRoute(
      builder: (context, state, child) => HomeView(child: child),
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const _HomeTab(),
        ),
        GoRoute(
          path: '/communicate',
          builder: (context, state) => const _CommunicateTab(),
        ),
        GoRoute(
          path: '/alerts',
          builder: (context, state) => const _AlertsTab(),
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
      builder: (context, state) => const ProfileManagementView(),
    ),
    GoRoute(
      path: '/preferences',
      builder: (context, state) => const PreferencesView(),
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
      path: '/venue',
      builder: (context, state) => const VenueIdentificationView(),
    ),
    GoRoute(
      path: '/announcements',
      builder: (context, state) => const AnnouncementView(),
    ),
    GoRoute(
      path: '/emergency-alerts',
      builder: (context, state) => const EmergencyAlertView(),
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
      path: '/assistance-request',
      builder: (context, state) => const AssistanceRequestView(),
    ),
    GoRoute(
      path: '/request-tracking',
      builder: (context, state) => const RequestTrackingView(),
    ),
    GoRoute(
      path: '/chat',
      builder: (context, state) => const ChatView(),
    ),
    GoRoute(
      path: '/accessibility-issue',
      builder: (context, state) => const AccessibilityIssueView(),
    ),
  ],
);

// Tab placeholder widgets that build the actual tab content
class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return const VenueIdentificationView();
  }
}

class _CommunicateTab extends StatelessWidget {
  const _CommunicateTab();

  @override
  Widget build(BuildContext context) {
    return const SignTranslationCameraView();
  }
}

class _AlertsTab extends StatelessWidget {
  const _AlertsTab();

  @override
  Widget build(BuildContext context) {
    return const NotificationHistoryView();
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    return const ProfileManagementView();
  }
}

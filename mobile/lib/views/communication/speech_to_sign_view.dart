import 'package:flutter/material.dart';
import 'sign_translation_camera_view.dart';

class SpeechToSignView extends StatelessWidget {
  const SpeechToSignView({super.key});

  @override
  Widget build(BuildContext context) {
    // Renders the unified dual-mode translation screen in Speech-to-Sign mode
    return const SignTranslationCameraView(
      initialMode: SignTranslationMode.speechToSign,
    );
  }
}

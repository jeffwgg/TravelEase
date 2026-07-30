import 'package:flutter/material.dart';
import '../../core/theme.dart';

class SignMediaViewerView extends StatelessWidget {
  const SignMediaViewerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Media'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(icon: const Icon(Icons.favorite_border), onPressed: () {}),
          IconButton(icon: const Icon(Icons.share), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video player
            Container(
              width: double.infinity,
              height: 300,
              color: AppColors.darkSurface,
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.sign_language, size: 40, color: AppColors.primaryLight),
                        ),
                        const SizedBox(height: 12),
                        Text('Sign Language Video', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
                      ],
                    ),
                  ),
                  // Controls overlay
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                        ),
                      ),
                      child: Column(
                        children: [
                          // Progress bar
                          SliderTheme(
                            data: SliderThemeData(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                            child: Slider(value: 0.35, onChanged: (_) {}, activeColor: AppColors.primary, inactiveColor: Colors.white30),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('0:03', style: TextStyle(color: Colors.white60, fontSize: 12)),
                              Row(
                                children: [
                                  IconButton(icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: () {}),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                                  ),
                                  IconButton(icon: const Icon(Icons.forward_10, color: Colors.white), onPressed: () {}),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(icon: const Icon(Icons.slow_motion_video, color: Colors.white70, size: 20), onPressed: () {}),
                                  IconButton(icon: const Icon(Icons.fullscreen, color: Colors.white70, size: 20), onPressed: () {}),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Speed indicator
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                      child: const Text('1.0x', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            // Phrase details
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.flag_outlined, size: 14, color: AppColors.primary),
                            SizedBox(width: 4),
                            Text('BIM (Malaysia)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(6)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.flight_takeoff, size: 14, color: AppColors.textMuted),
                            SizedBox(width: 4),
                            Text('Airport', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Where is the gate?', style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text('Di mana pintu masuk?', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 24),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.volume_up, size: 18),
                          label: const Text('Play Audio'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy Text'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Description
                  Text('How to sign', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStep('1', 'Raise both hands with palms facing up'),
                          const Divider(height: 20),
                          _buildStep('2', 'Move hands slightly apart in a questioning gesture'),
                          const Divider(height: 20),
                          _buildStep('3', 'Point forward with index finger while raising eyebrows'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Related phrases
                  Text('Related Phrases', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _buildRelated(context, Icons.flight_takeoff, 'Which gate is my flight?'),
                  _buildRelated(context, Icons.confirmation_number_outlined, 'I need to check in'),
                  _buildRelated(context, Icons.schedule, 'What time is boarding?'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildStep(String num, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(num, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(desc, style: const TextStyle(fontSize: 14, height: 1.4))),
      ],
    );
  }

  static Widget _buildRelated(BuildContext context, IconData icon, String text) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary, size: 22),
        title: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.play_circle_outline, color: AppColors.primary),
        onTap: () {},
      ),
    );
  }
}

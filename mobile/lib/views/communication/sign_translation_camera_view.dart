import 'package:flutter/material.dart';
import '../../core/theme.dart';

class SignTranslationCameraView extends StatefulWidget {
  const SignTranslationCameraView({super.key});

  @override
  State<SignTranslationCameraView> createState() => _SignTranslationCameraViewState();
}

class _SignTranslationCameraViewState extends State<SignTranslationCameraView> {
  bool _isRecording = false;
  String _signLanguage = 'BIM';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview placeholder
          Container(
            width: double.infinity,
            height: double.infinity,
            color: const Color(0xFF1A1A2E),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam, size: 64, color: Colors.white.withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  Text('Camera Preview', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Point camera at sign language gestures', style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 12)),
                ],
              ),
            ),
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTopButton(Icons.arrow_back, () => Navigator.pop(context)),
                  // Language selector
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _signLanguage,
                        dropdownColor: Colors.black87,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                        items: const [
                          DropdownMenuItem(
                            value: 'BIM',
                            child: Row(
                              children: [
                                Icon(Icons.flag_outlined, size: 16, color: AppColors.primaryLight),
                                SizedBox(width: 6),
                                Text('BIM (Malaysia)'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'ASL',
                            child: Row(
                              children: [
                                Icon(Icons.flag_outlined, size: 16, color: AppColors.secondaryLight),
                                SizedBox(width: 6),
                                Text('ASL (USA)'),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _signLanguage = v!),
                      ),
                    ),
                  ),
                  _buildTopButton(Icons.flip_camera_ios, () {}),
                ],
              ),
            ),
          ),

          // Hand detection overlay
          if (_isRecording)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.25,
              left: 40,
              right: 40,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primaryLight, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.back_hand, color: AppColors.primaryLight, size: 40),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Detecting...', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Translation result
          Positioned(
            bottom: 180,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Translation ($_signLanguage)', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      Row(
                        children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: _isRecording ? AppColors.success : AppColors.textMuted, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(_isRecording ? 'Live' : 'Paused', style: TextStyle(color: _isRecording ? AppColors.success : AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRecording ? 'Hello, I need help finding my gate.' : 'Tap record to start translating',
                    style: TextStyle(color: Colors.white, fontSize: _isRecording ? 18 : 14, fontWeight: _isRecording ? FontWeight.w600 : FontWeight.w400),
                  ),
                  if (_isRecording) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildActionChip(Icons.volume_up, 'Speak', () {}),
                        const SizedBox(width: 8),
                        _buildActionChip(Icons.copy, 'Copy', () {}),
                        const SizedBox(width: 8),
                        _buildActionChip(Icons.edit, 'Edit', () {}),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildBottomButton(Icons.photo_library, 'Gallery', () {}),
                  // Record button
                  GestureDetector(
                    onTap: () => setState(() => _isRecording = !_isRecording),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        color: _isRecording ? AppColors.emergency : Colors.transparent,
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.circle,
                        color: _isRecording ? Colors.white : AppColors.primary,
                        size: _isRecording ? 32 : 56,
                      ),
                    ),
                  ),
                  _buildBottomButton(Icons.history, 'History', () {}),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildActionChip(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 24),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

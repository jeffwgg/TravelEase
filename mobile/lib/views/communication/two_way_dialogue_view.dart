import 'package:flutter/material.dart';
import '../../core/theme.dart';

class TwoWayDialogueView extends StatelessWidget {
  const TwoWayDialogueView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Two-Way Dialogue'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(icon: const Icon(Icons.translate), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          // Language bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surfaceVariant,
            child: Row(
              children: [
                _buildLangChip('English', true),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.swap_horiz, color: AppColors.primary),
                ),
                _buildLangChip('Bahasa Melayu', false),
              ],
            ),
          ),
          // Chat messages - split view
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSystemMessage(context, 'Conversation started • Auto-translating'),
                const SizedBox(height: 16),
                // User (deaf) messages - right
                _buildMessage(context, 'Hello, I need help checking in. I am deaf.', true, 'Sign → Text', '10:30 AM'),
                // Other person messages - left
                _buildMessage(context, 'Of course! Let me help you. May I see your passport and booking confirmation?', false, 'Speech → Text', '10:31 AM'),
                _buildMessage(context, 'Here is my booking. Where do I go after check-in?', true, 'Text', '10:32 AM'),
                _buildMessage(context, 'After check-in, go to Gate B5 on Level 2. Turn right after security.', false, 'Speech → Text', '10:33 AM'),
                _buildMessage(context, 'Thank you! What time does boarding start?', true, 'Sign → Text', '10:34 AM'),
                _buildMessage(context, 'Boarding begins at 11:15 AM. You still have about 40 minutes.', false, 'Speech → Text', '10:34 AM'),
              ],
            ),
          ),
          // Quick phrases
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildQuickPhrase('Thank you'),
                  _buildQuickPhrase('Where is...?'),
                  _buildQuickPhrase('I need help'),
                  _buildQuickPhrase('Please repeat'),
                  _buildQuickPhrase('How much?'),
                ],
              ),
            ),
          ),
          // Input area
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
                  child: IconButton(icon: const Icon(Icons.sign_language, color: AppColors.primary), onPressed: () {}),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                  child: IconButton(icon: const Icon(Icons.mic, color: Colors.white), onPressed: () {}),
                ),
                const SizedBox(width: 4),
                Container(
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                  child: IconButton(icon: const Icon(Icons.volume_up, color: Colors.white), onPressed: () {}),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildMessage(BuildContext context, String text, bool isUser, String source, String time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(radius: 16, backgroundColor: AppColors.surfaceVariant, child: const Icon(Icons.person, size: 16, color: AppColors.textMuted)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser ? null : Border.all(color: AppColors.cardBorder),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: TextStyle(color: isUser ? Colors.white : AppColors.textPrimary, fontSize: 15)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.translate, size: 10, color: isUser ? Colors.white54 : AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(source, style: TextStyle(fontSize: 10, color: isUser ? Colors.white54 : AppColors.textMuted)),
                      const SizedBox(width: 8),
                      Text(time, style: TextStyle(fontSize: 10, color: isUser ? Colors.white54 : AppColors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildSystemMessage(BuildContext context, String text) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  static Widget _buildLangChip(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: active ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? AppColors.primary : AppColors.cardBorder),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: active ? AppColors.primary : AppColors.textSecondary)),
    );
  }

  static Widget _buildQuickPhrase(String text) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
    );
  }
}

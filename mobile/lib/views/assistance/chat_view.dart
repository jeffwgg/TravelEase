import 'package:flutter/material.dart';
import '../../core/theme.dart';

class ChatView extends StatelessWidget {
  const ChatView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.support_agent, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('KLIA Staff', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('Online', style: TextStyle(fontSize: 11, color: AppColors.success)),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.call), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          // Request context
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(child: Text('Request #REQ-2847 — Communication Help', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text('In Progress', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildSystemMsg(context, 'Staff member Ahmad has been assigned'),
                const SizedBox(height: 12),
                _buildMsg('Hello! I\'m Ahmad from KLIA guest services. I see you need communication help. How can I assist you?', false, '10:35 AM'),
                _buildMsg('Hi Ahmad! I need help understanding the boarding announcement. My flight is MH370.', true, '10:36 AM'),
                _buildMsg('Of course! Your flight MH370 has been moved to Gate B12. Boarding starts at 11:15 AM. You have about 35 minutes.', false, '10:37 AM'),
                _buildMsg('Thank you! How do I get to Gate B12 from here?', true, '10:38 AM'),
                _buildMsg('From your current location near Gate A5, take the travelator to your right. Follow signs to Gates B1-B15. Gate B12 will be on your left. It\'s about a 5 minute walk.', false, '10:38 AM'),
                _buildMsg('I\'ll send you a map. 📍', false, '10:39 AM'),
              ],
            ),
          ),
          // Input
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.add_circle_outline, color: AppColors.textMuted), onPressed: () {}),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                  child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 20), onPressed: () {}),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildMsg(String text, bool isUser, String time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser ? null : Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(text, style: TextStyle(color: isUser ? Colors.white : AppColors.textPrimary, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(time, style: TextStyle(fontSize: 10, color: isUser ? Colors.white54 : AppColors.textMuted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildSystemMsg(BuildContext context, String text) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}

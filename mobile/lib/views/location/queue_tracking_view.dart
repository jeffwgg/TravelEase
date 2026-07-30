import 'package:flutter/material.dart';
import '../../core/theme.dart';

class QueueTrackingView extends StatelessWidget {
  const QueueTrackingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue Tracking'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Your queue status
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              children: [
                const Text('Your Queue Number', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                const Text('A-047', style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: 4)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildQueueStat('Now Serving', 'A-042'),
                    Container(width: 1, height: 40, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 20)),
                    _buildQueueStat('People Ahead', '5'),
                    Container(width: 1, height: 40, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 20)),
                    _buildQueueStat('Est. Wait', '~15 min'),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.vibration, color: Colors.white70, size: 18),
                      SizedBox(width: 8),
                      Text('You will be notified when it\'s your turn', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Queue progress
          Text('Queue Progress', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...List.generate(8, (i) {
            final num = 40 + i;
            final isCurrent = num == 42;
            final isYou = num == 47;
            final isPassed = num < 42;
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              child: Card(
                color: isYou ? AppColors.primary.withValues(alpha: 0.05) : isCurrent ? AppColors.success.withValues(alpha: 0.05) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isYou ? const BorderSide(color: AppColors.primary) : isCurrent ? const BorderSide(color: AppColors.success) : BorderSide.none,
                ),
                child: ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isPassed ? AppColors.surfaceVariant : isCurrent ? AppColors.success.withValues(alpha: 0.15) : isYou ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text('A-0$num', style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isPassed ? AppColors.textMuted : isCurrent ? AppColors.success : isYou ? AppColors.primary : AppColors.textPrimary,
                      decoration: isPassed ? TextDecoration.lineThrough : null,
                    )),
                  ),
                  title: Text(
                    isCurrent ? 'Now Serving' : isYou ? 'Your Number' : isPassed ? 'Completed' : 'Waiting',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: isPassed ? AppColors.textMuted : null,
                    ),
                  ),
                  trailing: isPassed
                      ? const Icon(Icons.check_circle, color: AppColors.success, size: 20)
                      : isCurrent
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                              child: const Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success)),
                            )
                          : isYou
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                  child: const Text('YOU', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                )
                              : null,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  static Widget _buildQueueStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }
}

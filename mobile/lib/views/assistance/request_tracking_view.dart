import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

class RequestTrackingView extends StatelessWidget {
  const RequestTrackingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Requests'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildRequestCard(context, '#REQ-2847', 'Communication Help', 'KLIA Terminal 1', 'In Progress', AppColors.secondary, '10 min ago', true),
          _buildRequestCard(context, '#REQ-2831', 'Finding Gate B12', 'KLIA Terminal 1', 'Resolved', AppColors.success, '2 hrs ago', false),
          _buildRequestCard(context, '#REQ-2798', 'Luggage Assistance', 'KLIA Terminal 2', 'Resolved', AppColors.success, 'Yesterday', false),
          _buildRequestCard(context, '#REQ-2756', 'Check-in Help', 'Gateway Hotel', 'Closed', AppColors.textMuted, '2 days ago', false),
        ],
      ),
    );
  }

  Widget _buildRequestCard(BuildContext context, String id, String title, String venue, String status, Color statusColor, String time, bool active) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: active ? BorderSide(color: statusColor.withValues(alpha: 0.5)) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: active ? () => context.push('/chat') : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(id, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(venue, style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  Text(time, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              if (active) ...[
                const SizedBox(height: 12),
                // Timeline
                Row(
                  children: [
                    _buildTimelineDot(AppColors.success, true),
                    Expanded(child: Container(height: 2, color: AppColors.success)),
                    _buildTimelineDot(AppColors.success, true),
                    Expanded(child: Container(height: 2, color: AppColors.secondary)),
                    _buildTimelineDot(AppColors.secondary, true),
                    Expanded(child: Container(height: 2, color: AppColors.divider)),
                    _buildTimelineDot(AppColors.divider, false),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sent', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                    Text('Received', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                    Text('Assigned', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10, color: AppColors.secondary, fontWeight: FontWeight.w600)),
                    Text('Resolved', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/chat'),
                        icon: const Icon(Icons.chat, size: 16),
                        label: const Text('Open Chat'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildTimelineDot(Color color, bool filled) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: filled ? color : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}

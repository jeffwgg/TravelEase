import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../viewmodels/request_tracking_viewmodel.dart';

class RequestTrackingView extends StatefulWidget {
  const RequestTrackingView({super.key});

  @override
  State<RequestTrackingView> createState() => _RequestTrackingViewState();
}

class _RequestTrackingViewState extends State<RequestTrackingView> {
  final _viewModel = RequestTrackingViewModel();

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onChanged);
    _viewModel.loadRequests();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Requests'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _viewModel.loadRequests(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_viewModel.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading requests...', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    if (_viewModel.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.emergency),
              const SizedBox(height: 16),
              Text(_viewModel.errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _viewModel.loadRequests(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_viewModel.requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 56, color: AppColors.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              const Text('No requests yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              const Text(
                'Your assistance requests will appear here once you submit one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.add),
                label: const Text('Request Assistance'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _viewModel.loadRequests(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _viewModel.requests.length,
        itemBuilder: (context, index) {
          final req = _viewModel.requests[index];
          return _buildRequestCard(context, req);
        },
      ),
    );
  }

  Widget _buildRequestCard(BuildContext context, Map<String, dynamic> req) {
    final id = req['request_code'] ?? '';
    final title = req['category'] ?? 'Assistance Request';
    final venue = req['venue_name'] ?? '';
    final status = req['status'] ?? 'pending';
    final createdAt = req['created_at'] as String?;
    final requestId = req['id']?.toString() ?? '';

    final statusLabel = _viewModel.getStatusLabel(status);
    final statusColor = _viewModel.getStatusColor(status);
    final active = _viewModel.isActive(status);
    final timeAgo = _viewModel.getTimeAgo(createdAt);
    final timelineStep = _viewModel.getTimelineStep(status);

    // Format category for display
    String displayTitle = title;
    if (title.isNotEmpty) {
      displayTitle = title.replaceAll('_', ' ');
      displayTitle = displayTitle[0].toUpperCase() + displayTitle.substring(1);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: active ? BorderSide(color: statusColor.withValues(alpha: 0.5)) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: active ? () => context.push('/chat?requestId=$requestId') : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('#$id', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Expanded(child: Text(venue, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                  Text(timeAgo, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              if (active) ...[
                const SizedBox(height: 12),
                // Timeline
                Row(
                  children: [
                    _buildTimelineDot(timelineStep >= 0 ? AppColors.success : AppColors.divider, timelineStep >= 0),
                    Expanded(child: Container(height: 2, color: timelineStep >= 1 ? AppColors.success : AppColors.divider)),
                    _buildTimelineDot(timelineStep >= 1 ? AppColors.success : AppColors.divider, timelineStep >= 1),
                    Expanded(child: Container(height: 2, color: timelineStep >= 2 ? AppColors.secondary : AppColors.divider)),
                    _buildTimelineDot(timelineStep >= 2 ? AppColors.secondary : AppColors.divider, timelineStep >= 2),
                    Expanded(child: Container(height: 2, color: timelineStep >= 3 ? AppColors.success : AppColors.divider)),
                    _buildTimelineDot(timelineStep >= 3 ? AppColors.success : AppColors.divider, timelineStep >= 3),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sent', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10, color: timelineStep >= 0 ? AppColors.success : null, fontWeight: timelineStep == 0 ? FontWeight.w600 : null)),
                    Text('Received', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10, color: timelineStep >= 1 ? AppColors.success : null, fontWeight: timelineStep == 1 ? FontWeight.w600 : null)),
                    Text('Assigned', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10, color: timelineStep >= 2 ? AppColors.secondary : null, fontWeight: timelineStep == 2 ? FontWeight.w600 : null)),
                    Text('Resolved', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10, color: timelineStep >= 3 ? AppColors.success : null, fontWeight: timelineStep == 3 ? FontWeight.w600 : null)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/chat?requestId=$requestId'),
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

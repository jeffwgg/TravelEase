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
    _viewModel.loadRequests().then((_) {
      // After loading, auto-prompt for any resolved requests needing confirmation
      if (mounted && _viewModel.pendingResolution.isNotEmpty) {
        final req = _viewModel.requests.firstWhere(
          (r) => _viewModel.pendingResolution.contains(r['id']?.toString()),
          orElse: () => {},
        );
        if (req.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) _showResolutionDialog(req);
          });
        }
      }
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onChanged);
    _viewModel.dispose();
    super.dispose();
  }

  // ── UC503: Resolution Confirmation Dialog ─────────────────────────────────
  void _showResolutionDialog(Map<String, dynamic> req) {
    final requestId = req['id']?.toString() ?? '';
    String selectedOutcome = '';
    int selectedRating = 0;
    final commentCtrl = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
                  ),
                ),

                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Issue Resolved?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          Text('Request #${req['request_code'] ?? ''}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'The staff has marked your request as resolved. Was your issue actually resolved?',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 20),

                // Outcome Selection
                const Text('Outcome', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildOutcomeChip('fully_resolved', '✅ Fully Resolved', AppColors.success, selectedOutcome, (v) => setSheetState(() => selectedOutcome = v)),
                    const SizedBox(width: 8),
                    _buildOutcomeChip('partially_resolved', '⚠️ Partial', AppColors.secondary, selectedOutcome, (v) => setSheetState(() => selectedOutcome = v)),
                    const SizedBox(width: 8),
                    _buildOutcomeChip('unresolved', '❌ Unresolved', AppColors.emergency, selectedOutcome, (v) => setSheetState(() => selectedOutcome = v)),
                  ],
                ),
                const SizedBox(height: 20),

                // Star Rating
                const Text('Satisfaction Rating', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return GestureDetector(
                      onTap: () => setSheetState(() => selectedRating = star),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          star <= selectedRating ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 42,
                          color: star <= selectedRating ? const Color(0xFFF59E0B) : AppColors.textMuted,
                        ),
                      ),
                    );
                  }),
                ),
                if (selectedRating > 0) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      ['', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent'][selectedRating],
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Optional comment
                TextField(
                  controller: commentCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Any additional comments? (optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (selectedOutcome.isEmpty || selectedRating == 0 || isSubmitting)
                        ? null
                        : () async {
                            setSheetState(() => isSubmitting = true);
                            final success = await _viewModel.submitResolutionFeedback(
                              requestId: requestId,
                              outcome: selectedOutcome,
                              rating: selectedRating,
                              comment: commentCtrl.text.trim().isEmpty ? null : commentCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (success && mounted) {
                              final isFullyResolved = selectedOutcome == 'fully_resolved';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isFullyResolved
                                      ? '✅ Request closed. Thank you for your feedback!'
                                      : '⚠️ Ticket re-opened and flagged for supervisor review.'),
                                  backgroundColor: isFullyResolved ? AppColors.success : AppColors.secondary,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Submit Feedback'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOutcomeChip(String value, String label, Color color, String selected, ValueChanged<String> onTap) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? color : AppColors.cardBorder, width: isSelected ? 2 : 1),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? color : AppColors.textMuted)),
        ),
      ),
    );
  }

  // ── Cancel Confirmation ───────────────────────────────────────────────────
  void _confirmCancel(String requestId, String requestCode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Request?'),
        content: Text(
          'Are you sure you want to cancel request #$requestCode? This action cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emergency),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await _viewModel.cancelRequest(requestId);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Request cancelled.'),
                    backgroundColor: AppColors.emergency,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
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
    final needsResolution = _viewModel.pendingResolution.contains(requestId);
    final rating = req['user_rating'];

    final statusLabel = _viewModel.getStatusLabel(status);
    final statusColor = _viewModel.getStatusColor(status);
    final active = _viewModel.isActive(status);
    final cancellable = _viewModel.isCancellable(status);
    final timeAgo = _viewModel.getTimeAgo(createdAt);
    final timelineStep = _viewModel.getTimelineStep(status);

    String displayTitle = title;
    if (title.isNotEmpty) {
      displayTitle = title.replaceAll('_', ' ');
      displayTitle = displayTitle[0].toUpperCase() + displayTitle.substring(1);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: needsResolution
            ? BorderSide(color: AppColors.success.withValues(alpha: 0.7), width: 2)
            : active
                ? BorderSide(color: statusColor.withValues(alpha: 0.5))
                : BorderSide.none,
      ),
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

            // ── Resolution pending banner ──
            if (needsResolution) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 18, color: AppColors.success),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Staff marked this resolved. Was it?',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.success)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _showResolutionDialog(req),
                      child: const Text('Confirm', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],

            // ── Rating display for closed requests ──
            if (status == 'closed' && rating != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 4),
                  Text('Your Rating: $rating/5', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ],

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
                  if (req['preferred_communication'] != 'location') ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/chat?requestId=$requestId'),
                        icon: const Icon(Icons.chat, size: 16),
                        label: const Text('Open Chat'),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.directions_walk_rounded, size: 16, color: Color(0xFFB45309)),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'In-Person Assistance',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  // FR-M5-29: Cancel button
                  if (cancellable) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _confirmCancel(requestId, id),
                      icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.emergency),
                      label: const Text('Cancel', style: TextStyle(color: AppColors.emergency)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.emergency)),
                    ),
                  ],
                ],
              ),
            ],
          ],
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

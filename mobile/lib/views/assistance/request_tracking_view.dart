import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../viewmodels/request_tracking_viewmodel.dart';
import 'resolution_feedback_sheet.dart';

class RequestTrackingView extends StatefulWidget {
  const RequestTrackingView({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<RequestTrackingView> createState() => _RequestTrackingViewState();
}

class _RequestTrackingViewState extends State<RequestTrackingView> {
  final _viewModel = RequestTrackingViewModel();

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onChanged);
    _viewModel.subscribeToRealtime();
    _viewModel.loadAll().then((_) {
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
  Future<void> _showResolutionDialog(Map<String, dynamic> req) async {
    final requestId = req['id']?.toString() ?? '';
    final feedback = await showResolutionFeedbackSheet(
      context,
      title: 'Issue Resolved?',
      subtitle: 'Request #${req['request_code'] ?? ''}',
      question: 'The staff has marked your request as resolved. Was your issue actually resolved?',
      onSubmit: (fb) => _viewModel.submitResolutionFeedback(
        requestId: requestId,
        outcome: fb.outcome,
        rating: fb.rating,
        comment: fb.comment,
      ),
    );
    if (feedback == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(feedback.isFullyResolved
            ? 'Request closed. Thank you for your feedback!'
            : 'Ticket re-opened and flagged for supervisor review.'),
        backgroundColor: feedback.isFullyResolved ? AppColors.success : AppColors.secondary,
        behavior: SnackBarBehavior.floating,
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

  void _confirmResolve(String requestId, String requestCode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Mark as Resolved?'),
        content: Text(
          'Confirm that request #$requestCode has been resolved and the staff member helped you.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Not Yet')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await _viewModel.resolveRequest(requestId);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Request marked as resolved.'),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Yes, Resolved'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Track Requests & Reports'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.support_agent_rounded), text: 'Assistance'),
              Tab(icon: Icon(Icons.report_problem_outlined), text: 'Barrier Reports'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => _viewModel.loadAll(),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildRequestsBody(),
            _buildBarrierReportsBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsBody() {
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
    final zone = req['location_zone'] ?? '';
    final venueLabel =
        zone.isNotEmpty && zone != venue ? '$venue — $zone' : venue;
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
                Expanded(child: Text(venueLabel, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
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
                        onPressed: () async {
                          await context.push('/chat?requestId=$requestId');
                          // Chat can change the status (e.g. traveler confirmed the
                          // resolution) — refresh so the card updates immediately.
                          if (mounted) await _viewModel.loadRequests();
                        },
                        icon: const Icon(Icons.chat, size: 16),
                        label: const Text('Open Chat'),
                      ),
                    ),
                  ] else ...[ 
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
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
                          if (status == 'in_progress') ...[ 
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () => _confirmResolve(requestId, id),
                              icon: const Icon(Icons.check_circle_outline, size: 16),
                              label: const Text('Mark Resolved'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ],
                        ],
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

  Widget _buildBarrierReportsBody() {
    if (_viewModel.isLoadingReports) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading barrier reports...', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    if (_viewModel.reportsErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.emergency),
              const SizedBox(height: 16),
              Text(
                _viewModel.reportsErrorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _viewModel.loadAccessibilityReports(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_viewModel.accessibilityReports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fact_check_outlined, size: 56, color: AppColors.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              const Text(
                'No barrier reports yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Accessibility barriers you report will appear here along with inspection and resolution updates from venue staff.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => context.push('/accessibility-issue'),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Report a Barrier'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _viewModel.loadAccessibilityReports(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _viewModel.accessibilityReports.length,
        itemBuilder: (context, index) {
          final rep = _viewModel.accessibilityReports[index];
          return _buildBarrierReportCard(context, rep);
        },
      ),
    );
  }

  Widget _buildBarrierReportCard(BuildContext context, Map<String, dynamic> rep) {
    final code = rep['report_code'] ?? 'Report';
    final issueType = rep['issue_type']?.toString() ?? 'other';
    final issueLabel = _viewModel.getIssueTypeLabel(issueType);
    final status = rep['status']?.toString() ?? 'reported';
    final statusLabel = _viewModel.getBarrierStatusLabel(status);
    final statusColor = _viewModel.getBarrierStatusColor(status);
    final severity = rep['severity']?.toString() ?? 'moderate';
    final venue = rep['venue_name'] ?? '';
    final zone = rep['location_zone'] ?? '';
    final description = rep['description'] ?? '';
    final photoUrl = rep['photo_url'] as String?;
    final adminNotes = rep['admin_notes'] as String?;
    final timeAgo = _viewModel.getTimeAgo(rep['created_at'] as String?);

    Color severityColor;
    switch (severity.toLowerCase()) {
      case 'minor':
        severityColor = AppColors.success;
        break;
      case 'severe':
        severityColor = AppColors.emergency;
        break;
      default:
        severityColor = AppColors.secondary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Code, status, time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        code,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            statusLabel,
                            style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(timeAgo, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),

            // Issue Type & Severity tags
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    issueLabel,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${severity[0].toUpperCase()}${severity.substring(1)} Severity',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: severityColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Location
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    zone.isNotEmpty && zone != venue ? '$zone • $venue' : venue,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // Description
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.3),
              ),
            ],

            // Photo Evidence
            if (photoUrl != null && photoUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _showImageDialog(context, photoUrl, code),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      Image.network(
                        photoUrl,
                        width: double.infinity,
                        height: 150,
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            height: 150,
                            color: AppColors.surfaceVariant,
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 80,
                          color: AppColors.surfaceVariant,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, color: AppColors.textMuted),
                              SizedBox(width: 8),
                              Text('Photo unavailable', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_in, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('Tap to view', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Processing Result / Staff action card
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: status == 'resolved'
                    ? AppColors.success.withValues(alpha: 0.08)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: status == 'resolved'
                      ? AppColors.success.withValues(alpha: 0.25)
                      : AppColors.cardBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        status == 'resolved' ? Icons.task_alt_rounded : Icons.info_outline,
                        size: 16,
                        color: status == 'resolved' ? AppColors.success : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Processing Result',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: status == 'resolved' ? AppColors.success : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    adminNotes != null && adminNotes.isNotEmpty
                        ? adminNotes
                        : (status == 'resolved'
                            ? 'The venue has reviewed and resolved this barrier.'
                            : (status == 'investigating' || status == 'in_progress'
                                ? 'Staff is currently investigating and addressing this barrier.'
                                : 'Awaiting staff inspection and action.')),
                    style: TextStyle(
                      fontSize: 13,
                      color: adminNotes != null && adminNotes.isNotEmpty
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageDialog(BuildContext context, String imageUrl, String reportCode) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 240,
                      color: Colors.black12,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(32),
                    color: Colors.white,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('Could not load image'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
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

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Outcome, rating and optional comment captured by [showResolutionFeedbackSheet].
class ResolutionFeedback {
  const ResolutionFeedback({
    required this.outcome,
    required this.rating,
    this.comment,
  });

  final String outcome;
  final int rating;
  final String? comment;

  bool get isFullyResolved => outcome == 'fully_resolved';
}

/// UC503: shared "Confirm Resolution" bottom sheet (emoji-free).
///
/// Calls [onSubmit] with the captured feedback; the sheet only closes when the
/// future resolves to `true`. Resolves with the feedback on success, or `null`
/// if the traveler dismissed the sheet.
Future<ResolutionFeedback?> showResolutionFeedbackSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String question,
  String submitHint = 'Select an outcome and a rating to continue',
  required Future<bool> Function(ResolutionFeedback feedback) onSubmit,
}) {
  return showModalBottomSheet<ResolutionFeedback>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ResolutionFeedbackSheet(
      title: title,
      subtitle: subtitle,
      question: question,
      submitHint: submitHint,
      onSubmit: onSubmit,
    ),
  );
}

class _ResolutionFeedbackSheet extends StatefulWidget {
  const _ResolutionFeedbackSheet({
    required this.title,
    required this.subtitle,
    required this.question,
    required this.submitHint,
    required this.onSubmit,
  });

  final String title;
  final String? subtitle;
  final String question;
  final String submitHint;
  final Future<bool> Function(ResolutionFeedback feedback) onSubmit;

  @override
  State<_ResolutionFeedbackSheet> createState() => _ResolutionFeedbackSheetState();
}

class _ResolutionFeedbackSheetState extends State<_ResolutionFeedbackSheet> {
  String? _outcome;
  int _rating = 0;
  bool _isSubmitting = false;
  final TextEditingController _commentCtrl = TextEditingController();

  static const _outcomes = <_OutcomeOption>[
    _OutcomeOption('fully_resolved', 'Resolved', Icons.check_circle_outline, AppColors.success),
    _OutcomeOption('partially_resolved', 'Partial', Icons.warning_amber_rounded, AppColors.secondary),
    _OutcomeOption('unresolved', 'Unresolved', Icons.cancel_outlined, AppColors.emergency),
  ];

  static const _ratingLabels = ['', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent'];

  bool get _canSubmit => _outcome != null && _rating > 0 && !_isSubmitting;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);
    final feedback = ResolutionFeedback(
      outcome: _outcome!,
      rating: _rating,
      comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
    );
    final success = await widget.onSubmit(feedback);
    if (!mounted) return;
    if (success) {
      Navigator.pop(context, feedback);
    } else {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not submit your feedback. Please try again.'),
          backgroundColor: AppColors.emergency,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.support_agent_outlined,
                        color: AppColors.success,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (widget.subtitle != null)
                            Text(
                              widget.subtitle!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textMuted),
                      tooltip: 'Dismiss',
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.question,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Outcome',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final option in _outcomes) ...[
                      Expanded(
                        child: _OutcomeCard(
                          option: option,
                          selected: _outcome == option.value,
                          onTap: () => setState(() => _outcome = option.value),
                        ),
                      ),
                      if (option != _outcomes.last) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Text(
                      'Satisfaction Rating',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _rating > 0 ? 1 : 0,
                      child: Text(
                        _rating > 0 ? _ratingLabels[_rating] : '',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    final filled = star <= _rating;
                    return IconButton(
                      onPressed: _isSubmitting ? null : () => setState(() => _rating = star),
                      tooltip: '$star / 5 — ${_ratingLabels[star]}',
                      iconSize: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      icon: Icon(
                        filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: filled ? const Color(0xFFF59E0B) : AppColors.textMuted,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _commentCtrl,
                  maxLines: 3,
                  enabled: !_isSubmitting,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Any feedback comments? (optional)',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.cardBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Not Now', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _canSubmit ? _submit : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.success,
                            disabledBackgroundColor: AppColors.surfaceVariant,
                            disabledForegroundColor: AppColors.textMuted,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : const Text(
                                  'Submit Feedback',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!_canSubmit && !_isSubmitting) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      widget.submitHint,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutcomeOption {
  const _OutcomeOption(this.value, this.label, this.icon, this.color);

  final String value;
  final String label;
  final IconData icon;
  final Color color;
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _OutcomeOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? option.color.withValues(alpha: 0.1) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? option.color : AppColors.cardBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              selected ? _selectedIcon(option.icon) : option.icon,
              size: 24,
              color: selected ? option.color : AppColors.textMuted,
            ),
            const SizedBox(height: 6),
            Text(
              option.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? option.color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _selectedIcon(IconData icon) {
    if (icon == Icons.check_circle_outline) return Icons.check_circle;
    if (icon == Icons.warning_amber_rounded) return Icons.warning_amber_rounded;
    return Icons.cancel;
  }
}

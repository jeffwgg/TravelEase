import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/entities/announcement.dart';
import '../../models/entities/spoken_announcement.dart';
import '../../models/repositories/spoken_announcement_repository.dart';
import '../../viewmodels/announcement_details_viewmodel.dart';
import '../../widgets/app_message_banner.dart';

/// Full content of a single announcement reached from the home preview or the
/// announcement list.
class AnnouncementDetailsView extends StatefulWidget {
  final String id;

  const AnnouncementDetailsView({super.key, required this.id});

  @override
  State<AnnouncementDetailsView> createState() =>
      _AnnouncementDetailsViewState();
}

class _AnnouncementDetailsViewState extends State<AnnouncementDetailsView> {
  final _viewModel = AnnouncementDetailsViewModel();
  Announcement? get _announcement => _viewModel.announcement;
  CapturedAnnouncement? get _capture => _viewModel.capture;
  bool get _loading => _viewModel.isLoading;
  String? get _error => _viewModel.error;
  String get _language => _viewModel.language;
  bool get _translating => _viewModel.isTranslating;
  String? get _translationError => _viewModel.translationError;
  Map<String, AnnouncementTranslation> get _deviceTranslations =>
      _viewModel.deviceTranslations;

  @override
  void initState() {
    super.initState();
    _viewModel.load(widget.id);
  }

  Future<void> _loadAnnouncement() => _viewModel.load(widget.id);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Announcement Details'),
          actions: [
            if (_announcement != null)
              PopupMenuButton<String>(
                tooltip: 'Announcement language',
                icon: const Icon(Icons.translate),
                initialValue: _language,
                onSelected: _selectLanguage,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'en', child: Text('English')),
                  PopupMenuItem(value: 'ms', child: Text('Bahasa Melayu')),
                  PopupMenuItem(
                    value: 'zh',
                    child: Text('Chinese (Simplified)'),
                  ),
                ],
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadAnnouncement,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null || _announcement == null)
                Column(
                  children: [
                    AppMessageBanner(
                      message: _error ?? 'Announcement could not be loaded.',
                      type: AppMessageType.error,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _loadAnnouncement,
                        child: const Text('Try Again'),
                      ),
                    ),
                  ],
                )
              else
                _buildDetails(context, _announcement!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, Announcement announcement) {
    final captured = announcement.isCaptured;
    final color = captured ? AppColors.accent : _colorFor(announcement);
    final translation =
        _deviceTranslations[_language] ?? announcement.translations[_language];
    final title =
        _language == 'en' || translation == null || translation.title.isEmpty
        ? announcement.title
        : translation.title;
    final message =
        _language == 'en' || translation == null || translation.message.isEmpty
        ? announcement.messageEn
        : translation.message;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: announcement.isUrgent
                ? BorderSide(color: color, width: 1.5)
                : BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        captured
                            ? Icons.mic_outlined
                            : _iconFor(announcement.type),
                        color: color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  captured
                                      ? 'CAPTURED • ${((announcement.confidence ?? 0) * 100).round()}%'
                                      : announcement.priorityLabel,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ),
                              if (!captured)
                                const Text(
                                  'Official',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 17,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (captured) ...[
                  if (_capture != null) ...[
                    _buildMetaRow(
                      Icons.hearing_outlined,
                      'Language: ${_capture!.language.toUpperCase()} • heard ${_capture!.repetitionCount} time${_capture!.repetitionCount == 1 ? '' : 's'}',
                    ),
                    _buildMetaRow(
                      Icons.history_outlined,
                      'First heard ${_formatDateTime(_capture!.firstCapturedAt)}',
                    ),
                    _buildMetaRow(
                      Icons.format_size_outlined,
                      'Recognised text was formatted on this device. Verify names, times and gates against official displays.',
                    ),
                  ],
                ] else ...[
                  _buildMetaRow(
                    Icons.account_balance_outlined,
                    announcement.institutionName ?? 'Participating institution',
                  ),
                  if (announcement.serviceAreaName != null)
                    _buildMetaRow(
                      Icons.pin_drop_outlined,
                      announcement.serviceAreaName!,
                    ),
                  _buildMetaRow(
                    Icons.schedule_outlined,
                    'Published ${_formatDateTime(announcement.publishedAt)}',
                  ),
                  if (announcement.expiresAt != null)
                    _buildMetaRow(
                      Icons.timer_off_outlined,
                      'Expires ${_formatDateTime(announcement.expiresAt!)}',
                    ),
                ],
                const Divider(height: 24),
                Text(message, style: Theme.of(context).textTheme.bodyLarge),
                if (captured &&
                    _capture != null &&
                    _capture!.originalTranscript != _capture!.transcript) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Original recognised text',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _capture!.originalTranscript,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_translating) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  Text(
                    'Translating announcement…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_language != 'en' && translation == null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _translationError ??
                        (captured
                            ? 'Translation unavailable — showing recognised text.'
                            : 'Translation unavailable — showing English.'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (captured) ...[
          const SizedBox(height: 12),
          const AppMessageBanner(
            message: 'This spoken caption is automatically recognised and may be incomplete or inaccurate. Verify important details with official information.',
            type: AppMessageType.information,
          ),
        ],
      ],
    );
  }

  Future<void> _selectLanguage(String language) =>
      _viewModel.selectLanguage(language);

  Widget _buildMetaRow(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) => switch (type) {
    'boarding' => Icons.flight_takeoff,
    'delay_cancellation' => Icons.schedule,
    'emergency' => Icons.warning_amber_rounded,
    'travel_update' => Icons.swap_horiz,
    _ => Icons.campaign_outlined,
  };

  Color _colorFor(Announcement announcement) => switch (announcement.priority) {
    'urgent' => AppColors.emergency,
    'high' => AppColors.secondary,
    'low' => AppColors.textSecondary,
    _ => AppColors.primary,
  };

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} at $hour:$minute';
  }
}

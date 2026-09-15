import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/entities/announcement.dart';
import '../../models/entities/captured_announcement.dart';
import '../../models/repositories/announcement_repository.dart';
import '../../models/repositories/captured_announcement_store.dart';
import '../../models/repositories/feature_usage_repository.dart';
import '../../services/translation_service.dart';
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
  final _repository = AnnouncementRepository();
  final _translator = TranslationService();
  final Map<String, AnnouncementTranslation> _deviceTranslations = {};
  Announcement? _announcement;
  CapturedAnnouncement? _capture;
  bool _loading = true;
  String? _error;
  String _language = 'en';
  bool _translating = false;
  String? _translationError;

  @override
  void initState() {
    super.initState();
    _loadAnnouncement();
  }

  Future<void> _loadAnnouncement() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // A captured id uses the local `cap-...` format, not Supabase's UUID
      // format. Resolve locally first so the remote query cannot throw before
      // this page gets its fallback.
      final capture = await CapturedAnnouncementStore.instance.byId(widget.id);
      final resolved =
          capture?.toAnnouncement() ??
          await _repository.getAnnouncementById(widget.id);
      if (!mounted) return;
      setState(() {
        _announcement = resolved;
        _capture = capture;
        _loading = false;
        if (resolved == null) {
          _error = 'This announcement is no longer available.';
        }
      });
      if (resolved != null) {
        FeatureUsageTracker.instance.completed(TrackedFeature.announcements);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Announcement could not be loaded.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                PopupMenuItem(value: 'zh', child: Text('Chinese (Simplified)')),
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
      ],
    );
  }

  Future<void> _selectLanguage(String language) async {
    setState(() {
      _language = language;
      _translationError = null;
    });

    final announcement = _announcement;
    if (announcement == null ||
        language == 'en' ||
        _deviceTranslations.containsKey(language) ||
        (announcement.translations[language]?.title.isNotEmpty == true &&
            announcement.translations[language]?.message.isNotEmpty == true)) {
      return;
    }

    setState(() => _translating = true);
    try {
      // Captures and official announcements without an institution-provided
      // translation both use the phone's translation service on demand. The
      // result remains only in this detail page; it never overwrites the
      // official announcement supplied by the institution.
      final capture = _capture;
      final sourceTitle = capture == null
          ? announcement.title
          : CapturedAnnouncement.deriveTitle(capture.transcript);
      final sourceMessage = capture?.transcript ?? announcement.messageEn;
      final sourceLanguage = capture == null
          ? 'en'
          : await _translator.detectLanguage(sourceMessage);
      final translated = await Future.wait([
        _translator.translateText(
          text: sourceTitle,
          fromLang: sourceLanguage,
          toLang: language,
        ),
        _translator.translateText(
          text: sourceMessage,
          fromLang: sourceLanguage,
          toLang: language,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _deviceTranslations[language] = AnnouncementTranslation(
          title: translated[0],
          message: translated[1],
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _translationError = 'Translation failed — showing recognised text.';
      });
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

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

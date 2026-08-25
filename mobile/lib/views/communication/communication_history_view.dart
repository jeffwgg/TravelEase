import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/entities/conversation_log_entity.dart';
import '../../viewmodels/two_way_dialogue_viewmodel.dart';

/// Communication history browser (FR-M3-17, FR-M3-18, UC304).
/// Opens from the 2-Way Dialogue app bar; lists every saved conversation log
/// with its full sentence-by-sentence transcript and supports deletion.
class CommunicationHistoryView extends StatefulWidget {
  final TwoWayDialogueViewModel viewModel;

  const CommunicationHistoryView({super.key, required this.viewModel});

  @override
  State<CommunicationHistoryView> createState() =>
      _CommunicationHistoryViewState();
}

class _CommunicationHistoryViewState extends State<CommunicationHistoryView> {
  String _filter = 'all';

  static const Map<String, String> _typeLabels = {
    'two_way_dialogue': '2-Way Dialogue',
    'sign_to_text': 'Sign to Text',
    'speech_to_sign': 'Speech to Sign',
  };

  static const Map<String, IconData> _typeIcons = {
    'two_way_dialogue': Icons.swap_horiz_rounded,
    'sign_to_text': Icons.sign_language_rounded,
    'speech_to_sign': Icons.record_voice_over_rounded,
  };

  @override
  void initState() {
    super.initState();
    widget.viewModel.loadSavedLogs();
  }

  String _formatDate(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} $hh:$mm';
  }

  Future<void> _confirmDelete(ConversationLog log) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Log'),
        content: Text('Delete "${log.logTitle}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emergency,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.viewModel.deleteSavedLog(log.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final logs = widget.viewModel.savedLogs;
        final filtered = _filter == 'all'
            ? logs
            : logs.where((l) => l.translationType == _filter).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Communication History'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Column(
            children: [
              // ── Type filter chips ──
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  children: [
                    _buildFilterChip('all', 'All'),
                    ..._typeLabels.entries.map(
                      (e) => _buildFilterChip(e.key, e.value),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // ── Log list ──
              Expanded(
                child: widget.viewModel.isLoadingLogs
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: widget.viewModel.loadSavedLogs,
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.only(top: 4, bottom: 16),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) =>
                                  _buildLogCard(filtered[i]),
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: AppColors.primary.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? AppColors.primary : AppColors.textSecondary,
        ),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.textMuted.withValues(alpha: 0.4),
        ),
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded,
                size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text(
              'No saved conversations yet.\n'
              'Use the save button during a dialogue\n'
              'to store the transcript here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.6, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard(ConversationLog log) {
    final typeLabel = _typeLabels[log.translationType] ?? log.translationType;
    final typeIcon = _typeIcons[log.translationType] ?? Icons.description_rounded;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: Icon(typeIcon, color: AppColors.primary, size: 22),
          title: Text(
            log.logTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '$typeLabel • ${_formatDate(log.createdAt)} • ${log.messageCount} msgs',
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ),
          children: [
            if (log.summary != null && log.summary!.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    log.summary!,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: AppColors.emergency),
                label: const Text('Delete',
                    style: TextStyle(color: AppColors.emergency)),
                onPressed: () => _confirmDelete(log),
              ),
            ),
            ...log.fullTranscript.map(_buildTranscriptEntry),
            if (log.fullTranscript.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Transcript unavailable.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ),
          ],
        ),
      ),
    );
  }

  /// One saved sentence: original caption above its translation.
  Widget _buildTranscriptEntry(Map<String, dynamic> entry) {
    final original = entry['original_text']?.toString() ?? '';
    final translated = entry['translated_text']?.toString() ?? '';
    if (original.isEmpty && translated.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mic_rounded, size: 11, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(
                (entry['source_language']?.toString() ?? '').toUpperCase(),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(original,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(translated,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

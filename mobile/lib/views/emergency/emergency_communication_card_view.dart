import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../viewmodels/emergency_communication_card_viewmodel.dart';
import '../../services/app_tour_controller.dart';
import '../../widgets/app_tour_coachmark.dart';

class EmergencyCommunicationCardView extends StatefulWidget {
  const EmergencyCommunicationCardView({super.key});

  @override
  State<EmergencyCommunicationCardView> createState() =>
      _EmergencyCommunicationCardViewState();
}

class _EmergencyCommunicationCardViewState
    extends State<EmergencyCommunicationCardView> {
  late final EmergencyCommunicationCardViewModel _viewModel;
  final _tourTargetKey = GlobalKey();
  final _scrollController = ScrollController();
  bool _inputScrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _viewModel = EmergencyCommunicationCardViewModel()..load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Emergency Communication Card'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) {
              if (_viewModel.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (AppTourController.instance.isShowing(
                    AppTourFeature.emergencyCard,
                  ) &&
                  !_inputScrollScheduled) {
                _inputScrollScheduled = true;
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  final inputContext = _tourTargetKey.currentContext;
                  if (!mounted || inputContext == null) return;
                  await Scrollable.ensureVisible(
                    inputContext,
                    alignment: 0.14,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                  );
                  // The coachmark calculates its target rectangle during its
                  // build. Rebuild after scrolling so its highlight follows
                  // the Card Information section instead of its old position.
                  if (mounted) setState(() {});
                });
              }
              return ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.accentLight.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.accentLight.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppColors.accent,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Show this card to someone who can help you during emergencies or when you need communication assistance.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Card Preview',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.accessible_forward,
                                      color: AppColors.primaryLight,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'TravelEase',
                                    style: TextStyle(
                                      color: AppColors.primaryLight,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.emergency.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'EMERGENCY',
                                  style: TextStyle(
                                    color: AppColors.emergencyLight,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _viewModel.hearingImpairmentNote,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Saya pekak / kurang pendengaran',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildCardRow(
                            Icons.chat_bubble_outline,
                            'Communicate with me by',
                            _viewModel.communicationMethodLabel,
                          ),
                          const SizedBox(height: 12),
                          _buildCardRow(
                            Icons.sign_language,
                            'I use',
                            _viewModel.signLanguageLabel,
                          ),
                          const SizedBox(height: 12),
                          _buildCardRow(
                            Icons.language,
                            'Languages',
                            _viewModel.languagesLabel,
                          ),
                          const SizedBox(height: 12),
                          _buildCardRow(
                            Icons.bloodtype_outlined,
                            'Blood Type',
                            _viewModel.bloodTypeLabel,
                          ),
                          const SizedBox(height: 12),
                          _buildCardRow(
                            Icons.medical_information,
                            'Medical Info',
                            _viewModel.medicalInfoLabel,
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'Emergency Contact',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _viewModel.contactLabel,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _viewModel.primaryContact == null
                                        ? AppColors.emergencyLight
                                        : Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Card Information',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    key: _tourTargetKey,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _viewModel.communicationMethod,
                            decoration: const InputDecoration(
                              labelText: 'Communication Method',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'written_text',
                                child: Text('Written text / typing'),
                              ),
                              DropdownMenuItem(
                                value: 'sign_language',
                                child: Text('Sign language'),
                              ),
                              DropdownMenuItem(
                                value: 'speech_to_text',
                                child: Text('Speech-to-text'),
                              ),
                              DropdownMenuItem(
                                value: 'combined',
                                child: Text('Combined methods'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                _viewModel.update(
                                  () => _viewModel.communicationMethod = value,
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _viewModel.signLanguage,
                            decoration: const InputDecoration(
                              labelText: 'Sign Language',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'bim',
                                child: Text('BIM (Malaysian Sign Language)'),
                              ),
                              DropdownMenuItem(
                                value: 'asl',
                                child: Text('ASL (American Sign Language)'),
                              ),
                              DropdownMenuItem(
                                value: 'none',
                                child: Text('Not specified'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                _viewModel.update(
                                  () => _viewModel.signLanguage = value,
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _viewModel.languagesController,
                            decoration: const InputDecoration(
                              labelText: 'Languages Spoken/Read',
                              hintText: 'e.g., English, Bahasa Melayu',
                            ),
                            onChanged: (_) => _viewModel.update(() {}),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _viewModel.bloodType,
                            decoration: const InputDecoration(
                              labelText: 'Blood Type',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'unknown',
                                child: Text('Unknown'),
                              ),
                              DropdownMenuItem(value: 'A+', child: Text('A+')),
                              DropdownMenuItem(value: 'A-', child: Text('A-')),
                              DropdownMenuItem(value: 'B+', child: Text('B+')),
                              DropdownMenuItem(value: 'B-', child: Text('B-')),
                              DropdownMenuItem(
                                value: 'AB+',
                                child: Text('AB+'),
                              ),
                              DropdownMenuItem(
                                value: 'AB-',
                                child: Text('AB-'),
                              ),
                              DropdownMenuItem(value: 'O+', child: Text('O+')),
                              DropdownMenuItem(value: 'O-', child: Text('O-')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                _viewModel.update(
                                  () => _viewModel.bloodType = value,
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _viewModel.allergiesController,
                            decoration: const InputDecoration(
                              labelText: 'Allergy Information (Optional)',
                              hintText: 'e.g., Penicillin, peanuts',
                            ),
                            maxLines: 2,
                            onChanged: (_) => _viewModel.update(() {}),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _viewModel.medicalNotesController,
                            decoration: const InputDecoration(
                              labelText: 'Important Medical Notes (Optional)',
                              hintText: 'Additional information for helpers',
                            ),
                            maxLines: 3,
                            onChanged: (_) => _viewModel.update(() {}),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_viewModel.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _viewModel.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.emergency),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (AppTourController.instance.isWaitingForEmergencyCard) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Complete your emergency card, then tap Save Card to finish setup.',
                        style: TextStyle(color: AppColors.primaryDark),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _share,
                          icon: const Icon(Icons.share),
                          label: const Text('Share Card'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _viewModel.isSaving ? null : _save,
                          icon: const Icon(Icons.save),
                          label: Text(
                            _viewModel.isSaving ? 'Saving...' : 'Save Card',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              );
            },
          ),
        ),
        Positioned.fill(
          child: AppTourCoachmark(
            feature: AppTourFeature.emergencyCard,
            targetKey: _tourTargetKey,
            title: 'Emergency Card',
            message: 'Keep your communication and medical details here.',
            onNext: _continueTour,
          ),
        ),
      ],
    );
  }

  void _continueTour() {
    AppTourController.instance.advance(context);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (await _viewModel.save() && mounted) {
      if (AppTourController.instance.isWaitingForEmergencyCard) {
        AppTourController.instance.completeEmergencyCard(context);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency communication card saved.')),
      );
    }
  }

  Future<void> _share() async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = renderBox == null
        ? null
        : renderBox.localToGlobal(Offset.zero) & renderBox.size;
    try {
      await _viewModel.share(sharePositionOrigin: origin);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the share menu.')),
      );
    }
  }

  static Widget _buildCardRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primaryLight, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

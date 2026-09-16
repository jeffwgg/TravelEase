import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'dart:convert';

import '../../core/theme.dart';
import '../../models/repositories/feature_usage_repository.dart';
import '../../services/app_tour_controller.dart';
import '../../viewmodels/assistance_request_viewmodel.dart';
import '../../widgets/app_tour_coachmark.dart';

class AssistanceRequestView extends StatefulWidget {
  const AssistanceRequestView({super.key});

  @override
  State<AssistanceRequestView> createState() => _AssistanceRequestViewState();
}

class _AssistanceRequestViewState extends State<AssistanceRequestView> {
  final _viewModel = AssistanceRequestViewModel();
  final _venueController = TextEditingController();
  final _tourTargetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onViewModelChanged);
    FeatureUsageTracker.instance.opened(TrackedFeature.requestHelp);
    _viewModel.fetchCurrentLocation().then((_) {
      if (_viewModel.venueName.isNotEmpty) {
        _venueController.text = _viewModel.venueName;
      }
    });
  }

  void _onViewModelChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _venueController.dispose();
    super.dispose();
  }

  void _showLocationOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _LocationBottomSheet(
        currentVenue: _viewModel.venueName,
        onVenueSelected: (name) {
          _viewModel.setVenue(name);
          _venueController.text = name;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Request Assistance'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Location section ──
                Container(
                  key: _tourTargetKey,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Requesting help from:',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (_viewModel.isFetchingLocation)
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Detecting location...',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                          color: AppColors.textMuted,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  )
                                else if (_viewModel.venueName.isNotEmpty)
                                  Text(
                                    _viewModel.venueName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                else
                                  Text(
                                    'No location selected',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                      color: AppColors.textMuted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _showLocationOptions,
                            child: Text(
                              _viewModel.venueName.isNotEmpty
                                  ? 'Change'
                                  : 'Select',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Editable venue name field
                      TextField(
                        controller: _venueController,
                        onChanged: (value) => _viewModel.setVenue(value),
                        decoration: InputDecoration(
                          hintText: 'Or type venue name here...',
                          prefixIcon: const Icon(
                            Icons.edit_location_alt_outlined,
                            size: 20,
                            color: AppColors.textMuted,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColors.cardBorder),
                          ),
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Editable venue name field
                  TextField(
                    controller: _venueController,
                    onChanged: (value) => _viewModel.setVenue(value),
                    decoration: InputDecoration(
                      hintText: 'Or type venue name here...',
                      prefixIcon: const Icon(Icons.edit_location_alt_outlined, size: 20, color: AppColors.textMuted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Request type ──
            Text('What do you need help with?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTypeChip('Communication', Icons.chat_bubble_outline, 'communication'),
                _buildTypeChip('Finding Location', Icons.location_on_outlined, 'location'),
                _buildTypeChip('Check-in / Boarding', Icons.confirmation_number_outlined, 'checkin'),
                _buildTypeChip('Luggage Issue', Icons.luggage_outlined, 'luggage'),
                _buildTypeChip('Accessibility', Icons.accessible_outlined, 'accessibility'),
                _buildTypeChip('Emergency Info', Icons.warning_amber_outlined, 'emergency'),
                _buildTypeChip('General Help', Icons.help_outline, 'general'),
              ],
            ),
            const SizedBox(height: 24),

            // ── Description ──
            Text('Describe your situation', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _viewModel.descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Tell us what you need help with...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),

            // ── Urgency ──
            Text('Urgency Level', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildUrgencyOption(0, 'Low', AppColors.success),
                const SizedBox(width: 8),
                _buildUrgencyOption(1, 'Medium', AppColors.secondary),
                const SizedBox(width: 8),
                _buildUrgencyOption(2, 'High', AppColors.emergency),
              ],
            ),
            const SizedBox(height: 24),

            // ── Communication preference (2 options: In-app Chat / Come to Location) ──
            Text('How should staff reach you?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('In-app Chat', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Staff will message or call you in the app', style: TextStyle(fontSize: 11)),
                    value: 'chat',
                    groupValue: _viewModel.contactMethod,
                    activeColor: AppColors.primary,
                    onChanged: (value) => _viewModel.setContactMethod(value!),
                  ),
                  const Divider(height: 1, indent: 16),
                  RadioListTile<String>(
                    title: const Text('Come to my location', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Staff will find you in person', style: TextStyle(fontSize: 11)),
                    value: 'location',
                    groupValue: _viewModel.contactMethod,
                    activeColor: AppColors.primary,
                    onChanged: (value) => _viewModel.setContactMethod(value!),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Share location toggle ──
            Card(
              child: SwitchListTile(
                title: const Text('Share my current location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text('Helps staff find you faster', style: Theme.of(context).textTheme.bodySmall),
                secondary: const Icon(Icons.my_location, color: AppColors.primary),
                value: _viewModel.shareLocation,
                activeColor: AppColors.primary,
                onChanged: (value) => _viewModel.setShareLocation(value),
              ),
            ),
            const SizedBox(height: 16),

            // ── Error message ──
            if (_viewModel.errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.emergency.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.emergency.withValues(alpha: 0.3)),
                ),
                const SizedBox(height: 24),

                // ── Request type ──
                Text(
                  'What do you need help with?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildTypeChip(
                      'Communication',
                      Icons.chat_bubble_outline,
                      'communication',
                    ),
                    _buildTypeChip(
                      'Finding Location',
                      Icons.location_on_outlined,
                      'location',
                    ),
                    _buildTypeChip(
                      'Check-in / Boarding',
                      Icons.confirmation_number_outlined,
                      'checkin',
                    ),
                    _buildTypeChip(
                      'Luggage Issue',
                      Icons.luggage_outlined,
                      'luggage',
                    ),
                    _buildTypeChip(
                      'Accessibility',
                      Icons.accessible_outlined,
                      'accessibility',
                    ),
                    _buildTypeChip(
                      'Emergency Info',
                      Icons.warning_amber_outlined,
                      'emergency',
                    ),
                    _buildTypeChip(
                      'General Help',
                      Icons.help_outline,
                      'general',
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Description ──
                Text(
                  'Describe your situation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _viewModel.descriptionController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Tell us what you need help with...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Urgency ──
                Text(
                  'Urgency Level',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildUrgencyOption(0, 'Low', AppColors.success),
                    const SizedBox(width: 8),
                    _buildUrgencyOption(1, 'Medium', AppColors.secondary),
                    const SizedBox(width: 8),
                    _buildUrgencyOption(2, 'High', AppColors.emergency),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Communication preference (2 options: In-app Chat / Come to Location) ──
                Text(
                  'How should staff reach you?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        title: const Text(
                          'In-app Chat',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Staff will message or call you in the app',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: 'chat',
                        groupValue: _viewModel.contactMethod,
                        activeColor: AppColors.primary,
                        onChanged: (value) =>
                            _viewModel.setContactMethod(value!),
                      ),
                      const Divider(height: 1, indent: 16),
                      RadioListTile<String>(
                        title: const Text(
                          'Come to my location',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Staff will find you in person',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: 'location',
                        groupValue: _viewModel.contactMethod,
                        activeColor: AppColors.primary,
                        onChanged: (value) =>
                            _viewModel.setContactMethod(value!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Share location toggle ──
                Card(
                  child: SwitchListTile(
                    title: const Text(
                      'Share my current location',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Helps staff find you faster',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    secondary: const Icon(
                      Icons.my_location,
                      color: AppColors.primary,
                    ),
                    value: _viewModel.shareLocation,
                    activeColor: AppColors.primary,
                    onChanged: (value) => _viewModel.setShareLocation(value),
                  ),
                ),
                const SizedBox(height: 12),

                // ── FR-M5-27 / FR-M7-07: analytics consent toggle ──
                Card(
                  child: SwitchListTile(
                    title: const Text(
                      'Share anonymously for analytics',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Let the institution count this request in anonymised service-improvement statistics. Your identity is never shown.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    secondary: const Icon(
                      Icons.insights_outlined,
                      color: AppColors.secondary,
                    ),
                    value: _viewModel.shareAnalytics,
                    activeColor: AppColors.primary,
                    onChanged: (value) => _viewModel.setShareAnalytics(value),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Error message ──
                if (_viewModel.errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.emergency.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.emergency.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.emergency,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _viewModel.errorMessage!,
                            style: const TextStyle(
                              color: AppColors.emergency,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Submit ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _viewModel.isSubmitting ? null : _handleSubmit,
                    icon: _viewModel.isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      _viewModel.isSubmitting
                          ? 'Submitting...'
                          : 'Submit Request',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/request-tracking'),
                    child: const Text('View My Requests'),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => context.push('/request-tracking'),
                child: const Text('View My Requests'),
              ),
            ),

            // ── Facility barrier report (Module 5 & 7): deliberately styled
            // as the weakest action so travellers never mistake it for help.
            const SizedBox(height: 8),
            Material(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  final venue = Uri.encodeComponent(_viewModel.venueName);
                  context.push('/accessibility-issue?venue=$venue');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.report_outlined, size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Report an Accessibility Barrier',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Facility feedback only — staff will not respond to reports. For immediate help, submit a request above.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
        Positioned.fill(
          child: AppTourCoachmark(
            feature: AppTourFeature.requestHelp,
            targetKey: _tourTargetKey,
            title: 'Request Help',
            message: 'Share your location and what you need.',
          ),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    final success = await _viewModel.submitRequest();
    if (success && mounted) {
      FeatureUsageTracker.instance.completed(TrackedFeature.requestHelp);
      _showSubmitted(context);
    }
  }

  Widget _buildTypeChip(String label, IconData icon, String value) {
    final selected = _viewModel.selectedCategory == value;
    return GestureDetector(
      onTap: () => _viewModel.setCategory(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrgencyOption(int level, String label, Color color) {
    final selected = _viewModel.urgencyLevel == level;
    return Expanded(
      child: GestureDetector(
        onTap: () => _viewModel.setUrgencyLevel(level),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.1)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : AppColors.cardBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? color : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSubmitted(BuildContext context) {
    final request = _viewModel.submittedRequest;
    final requestCode = request?['request_code'] ?? 'N/A';
    final venue = _viewModel.venueName;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Request Submitted!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '$venue staff will respond shortly.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Request ID: #$requestCode',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _viewModel.reset();
                _venueController.clear();
                context.push('/request-tracking');
              },
              child: const Text('Track Request'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Location selection bottom sheet ──

class _LocationBottomSheet extends StatefulWidget {
  final String currentVenue;
  final ValueChanged<String> onVenueSelected;

  const _LocationBottomSheet({
    required this.currentVenue,
    required this.onVenueSelected,
  });

  @override
  State<_LocationBottomSheet> createState() => _LocationBottomSheetState();
}

class _LocationBottomSheetState extends State<_LocationBottomSheet> {
  bool _isGettingLocation = false;
  final _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _manualController.text = widget.currentVenue;
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isGettingLocation = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission denied. Please enable it in Settings.',
              ),
            ),
          );
        }
        setState(() => _isGettingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Reverse geocode using Nominatim for now, or Google if key provided
      // TODO: Replace with Google Maps Geocoding API if key provided
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json&addressdetails=1',
      );

      final response = await http.get(
        url,
        headers: {'User-Agent': 'TravelEase/1.0'},
      );

      String placeName =
          '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          placeName =
              address['tourism'] ??
              address['building'] ??
              address['amenity'] ??
              address['road'] ??
              address['suburb'] ??
              placeName;
          final city = address['city'] ?? address['town'] ?? address['village'];
          if (city != null && placeName != city) {
            placeName = '$placeName, $city';
          }
        }
      }

      widget.onVenueSelected(placeName);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not get location: $e')));
      }
    }

    setState(() => _isGettingLocation = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
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

          Text(
            'Choose Location',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Select how you want to set your location',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),

          // Option 1: Manual input
          TextField(
            controller: _manualController,
            decoration: InputDecoration(
              hintText: 'Type venue or address...',
              prefixIcon: const Icon(
                Icons.edit_location_alt_outlined,
                color: AppColors.textMuted,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check_circle, color: AppColors.primary),
                onPressed: () {
                  if (_manualController.text.isNotEmpty) {
                    widget.onVenueSelected(_manualController.text);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                widget.onVenueSelected(value);
                Navigator.pop(context);
              }
            },
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: Theme.of(context).textTheme.bodySmall),
              ),
              const Expanded(child: Divider()),
            ],
          ),

          const SizedBox(height: 12),

          // Option 2: Use current location
          _buildOptionTile(
            icon: Icons.my_location,
            iconColor: AppColors.primary,
            title: 'Use current location',
            subtitle: 'Detect via GPS',
            isLoading: _isGettingLocation,
            onTap: _isGettingLocation ? null : _useCurrentLocation,
          ),

          const SizedBox(height: 8),

          // Option 3: Pick from map
          _buildOptionTile(
            icon: Icons.map_outlined,
            iconColor: AppColors.accent,
            title: 'Choose from map',
            subtitle: 'Tap on the map to pin your location',
            onTap: () async {
              final result = await context.push<Map<String, dynamic>>(
                '/location-picker',
              );
              if (result != null && result['name'] != null && mounted) {
                widget.onVenueSelected(result['name'] as String);
                Navigator.pop(context);
              }
            },
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    bool isLoading = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.cardBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: iconColor,
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

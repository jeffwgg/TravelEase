import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../models/repositories/venue_repository.dart';
import '../../models/entities/venue_search_result.dart';
import '../../services/venue_session_service.dart';
import '../../viewmodels/accessibility_issue_viewmodel.dart';
import '../../viewmodels/assistance_request_viewmodel.dart';

class AccessibilityIssueView extends StatefulWidget {
  const AccessibilityIssueView({super.key, this.venueName});

  /// Venue detected on the assistance flow; required so the report can be
  /// matched to the institution's analytics scoping on the web portal.
  final String? venueName;

  @override
  State<AccessibilityIssueView> createState() => _AccessibilityIssueViewState();
}

class _AccessibilityIssueViewState extends State<AccessibilityIssueView> {
  final _viewModel = AccessibilityIssueViewModel();
  // Reused only for its venue detection (GPS + reverse geocode) when this
  // screen has neither a caller-provided venue nor an active homepage session.
  final _locationVm = AssistanceRequestViewModel();
  XFile? _selectedPhoto;
  bool _analyticsConsent = false; // FR-M5-27

  /// Venue the report will be filed under: the caller-provided one wins,
  /// then the homepage venue session, then the auto-detected location.
  String get _venue {
    final fromParam = (widget.venueName ?? '').trim();
    if (fromParam.isNotEmpty) return fromParam;
    final session = VenueSessionService.instance.session;
    if (session != null) return session.institutionName.trim();
    return _locationVm.venueName.trim();
  }

  /// Display label combining the institution and its service area.
  String get _venueDisplay {
    final area = VenueSessionService.instance.session?.serviceAreaName?.trim();
    if (_venue.isEmpty || area == null || area.isEmpty) return _venue;
    return '$_venue — $area';
  }

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onChanged);
    if ((widget.venueName ?? '').trim().isEmpty &&
        VenueSessionService.instance.session == null) {
      _locationVm.fetchCurrentLocation().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onChanged);
    _viewModel.dispose();
    _locationVm.dispose();
    super.dispose();
  }

  // FR-M5-24: Pick photo from gallery or camera
  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1280);
      if (file != null) {
        setState(() => _selectedPhoto = file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick photo: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showLocationOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AccessibilityLocationSheet(
        currentLocation: _viewModel.locationController.text,
        onLocationSelected: (name) {
          setState(() => _viewModel.locationController.text = name);
        },
      ),
    );
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () { Navigator.pop(ctx); _pickPhoto(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () { Navigator.pop(ctx); _pickPhoto(ImageSource.gallery); },
            ),
            if (_selectedPhoto != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.emergency),
                title: const Text('Remove Photo', style: TextStyle(color: AppColors.emergency)),
                onTap: () { Navigator.pop(ctx); setState(() => _selectedPhoto = null); },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    // FR-M5-27: Consent required
    if (!_analyticsConsent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please consent to share data for analytics to submit.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final venue = _venue;
    if (venue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_locationVm.isFetchingLocation
              ? 'Still detecting your location, please try again in a moment.'
              : 'No venue detected. Enable location access or choose your location on the assistance request page first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final success = await _viewModel.submitReport(
      venueName: venue,
      serviceAreaName: VenueSessionService.instance.session?.serviceAreaName,
      analyticsConsent: _analyticsConsent,
      photoFile: _selectedPhoto,
    );
    if (success && mounted) {
      final code = _viewModel.lastSubmittedReportCode;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle, color: AppColors.success, size: 48),
              ),
              const SizedBox(height: 16),
              const Text('Report Submitted!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              if (code != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Report Code: $code',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Thank you for reporting this accessibility barrier. The venue has been notified and you can check status updates in your report history.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _viewModel.reset();
                      setState(() { _selectedPhoto = null; _analyticsConsent = false; });
                      Navigator.pop(context);
                      context.push('/request-tracking?tab=reports');
                    },
                    child: const Text('View History'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _viewModel.reset();
                      setState(() { _selectedPhoto = null; _analyticsConsent = false; });
                      Navigator.pop(context);
                    },
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Accessibility Issue'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            tooltip: 'Report History',
            onPressed: () => context.push('/request-tracking?tab=reports'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accentLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Report barriers that don\'t need immediate help — like missing visual announcements or sound-only queue systems. Staff will not respond to this report; for help now, use Make Request.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Issue Type', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChip('No Visual Announcement', Icons.volume_off_outlined, 'visual'),
                _buildChip('Sound-Only Queue', Icons.campaign_outlined, 'queue'),
                _buildChip('No Sign Language', Icons.sign_language_outlined, 'sign'),
                _buildChip('Missing Visual Alert', Icons.warning_amber_outlined, 'alert'),
                _buildChip('Inaccessible Area', Icons.accessible_forward_outlined, 'access'),
                _buildChip('Other Issue', Icons.note_alt_outlined, 'other'),
              ],
            ),
            const SizedBox(height: 24),
            Text('Location of Issue', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            // Homepage venue session location, same source as the assistance
            // request's "Requesting help from" field.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: AppColors.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Reporting from:', style: Theme.of(context).textTheme.bodySmall),
                        if (_venueDisplay.isNotEmpty)
                          Text(
                            _venueDisplay,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        else if (_locationVm.isFetchingLocation)
                          Text(
                            'Detecting location...',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              color: AppColors.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else
                          Text(
                            'No location detected. Start a venue session on the home page, or type a location below.',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              color: AppColors.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Specific spot within the venue (optional free text)
            GestureDetector(
              onTap: _showLocationOptions,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _viewModel.locationController.text.isNotEmpty
                            ? _viewModel.locationController.text
                            : 'Optional: tap to search specific spot (e.g. Gate A5)',
                        style: TextStyle(
                          color: _viewModel.locationController.text.isNotEmpty
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_viewModel.locationController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _viewModel.locationController.clear()),
                        child: const Icon(Icons.close, color: AppColors.textMuted, size: 18),
                      ),
                    if (_viewModel.locationController.text.isEmpty)
                      const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Description', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _viewModel.descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Describe the accessibility barrier...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            Text('Severity', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildSeverity(0, 'Minor', 'Inconvenient but manageable', AppColors.success),
                const SizedBox(width: 8),
                _buildSeverity(1, 'Moderate', 'Significant barrier', AppColors.secondary),
                const SizedBox(width: 8),
                _buildSeverity(2, 'Severe', 'Prevents access entirely', AppColors.emergency),
              ],
            ),
            const SizedBox(height: 24),

            // FR-M5-24: Photo Upload
            Text('Attach Photo (Optional)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_selectedPhoto != null) ...[
              // Preview
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Image.file(
                      File(_selectedPhoto!.path),
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedPhoto = null),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8, right: 8,
                      child: GestureDetector(
                        onTap: _showPhotoOptions,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                          child: const Text('Change', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              GestureDetector(
                onTap: _showPhotoOptions,
                child: Container(
                  width: double.infinity,
                  height: 110,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.cardBorder, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.surfaceVariant,
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo, color: AppColors.primary, size: 32),
                      SizedBox(height: 8),
                      Text('Tap to add photo evidence', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      SizedBox(height: 2),
                      Text('Camera or Gallery', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
            ],

            // FR-M5-27: Analytics Consent
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _analyticsConsent ? AppColors.primary.withValues(alpha: 0.5) : AppColors.cardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _analyticsConsent,
                    onChanged: (v) => setState(() => _analyticsConsent = v ?? false),
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _analyticsConsent = !_analyticsConsent),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'I consent to sharing this anonymised report for institutional accessibility analytics to help improve accessibility for all travellers.',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Error message
            if (_viewModel.errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.emergency.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.emergency.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.emergency, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _viewModel.errorMessage!,
                        style: const TextStyle(color: AppColors.emergency, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                // FR-M5-27: Disabled if no consent
                onPressed: (_viewModel.isSubmitting || !_analyticsConsent) ? null : _handleSubmit,
                icon: _viewModel.isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.report),
                label: Text(_viewModel.isSubmitting ? 'Submitting...' : 'Submit Report'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            if (!_analyticsConsent)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    'Consent required to submit',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, IconData icon, String value) {
    final selected = _viewModel.issueType == value;
    return GestureDetector(
      onTap: () => _viewModel.setIssueType(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.1) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.accent : AppColors.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? AppColors.accent : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? AppColors.accent : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverity(int level, String title, String desc, Color color) {
    final selected = _viewModel.severity == level;
    return Expanded(
      child: GestureDetector(
        onTap: () => _viewModel.setSeverity(level),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.1) : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : AppColors.cardBorder, width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(height: 6),
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? color : AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Location search bottom sheet for accessibility reports ──

class _AccessibilityLocationSheet extends StatefulWidget {
  final String currentLocation;
  final ValueChanged<String> onLocationSelected;

  const _AccessibilityLocationSheet({
    required this.currentLocation,
    required this.onLocationSelected,
  });

  @override
  State<_AccessibilityLocationSheet> createState() => _AccessibilityLocationSheetState();
}

class _AccessibilityLocationSheetState extends State<_AccessibilityLocationSheet> {
  final _searchController = TextEditingController();
  final _venueRepo = VenueRepository();
  List<VenueSearchResult> _results = [];
  bool _isSearching = false;
  bool _isGettingLocation = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.currentLocation;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final q = _searchController.text.trim();
      if (q.isEmpty) {
        setState(() => _results = []);
        return;
      }
      setState(() => _isSearching = true);
      final results = await _venueRepo.search(q);
      if (mounted) setState(() { _results = results; _isSearching = false; });
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
        }
        setState(() => _isGettingLocation = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json&addressdetails=1',
      );
      final response = await http.get(url, headers: {'User-Agent': 'TravelEase/1.0'});
      String placeName = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          placeName = address['tourism'] ?? address['building'] ?? address['amenity'] ??
              address['road'] ?? address['suburb'] ?? placeName;
          final city = address['city'] ?? address['town'] ?? address['village'];
          if (city != null && placeName != city) placeName = '$placeName, $city';
        }
      }
      widget.onLocationSelected(placeName);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not get location: $e')));
    }
    setState(() => _isGettingLocation = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('Search Location', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Search venues or service areas, or use your current location', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search venue or location...',
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
              suffixIcon: _isSearching
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : _searchController.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _results = []); })
                      : null,
            ),
          ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final r = _results[i];
                  return ListTile(
                    leading: const Icon(Icons.location_on, color: AppColors.primary),
                    title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(r.branch, style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      widget.onLocationSelected('${r.name} — ${r.branch}');
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ] else if (_searchController.text.isNotEmpty && !_isSearching) ...[
            const SizedBox(height: 8),
            // Allow manual entry if no results
            ListTile(
              leading: const Icon(Icons.add_location_alt, color: AppColors.accent),
              title: Text('Use "${_searchController.text}"', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
              subtitle: const Text('Type custom location', style: TextStyle(fontSize: 12)),
              onTap: () {
                widget.onLocationSelected(_searchController.text.trim());
                Navigator.pop(context);
              },
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [const Expanded(child: Divider()), Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: Theme.of(context).textTheme.bodySmall)), const Expanded(child: Divider())]),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _isGettingLocation ? null : _useCurrentLocation,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: AppColors.cardBorder), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: _isGettingLocation
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                        : const Icon(Icons.my_location, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Use current location', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      SizedBox(height: 2),
                      Text('Detect via GPS', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  )),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}


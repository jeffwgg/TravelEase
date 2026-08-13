import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../models/announcement.dart';
import '../../repositories/announcement_repository.dart';

class VenueIdentificationView extends StatefulWidget {
  const VenueIdentificationView({super.key});

  @override
  State<VenueIdentificationView> createState() => _VenueIdentificationViewState();
}

class _VenueIdentificationViewState extends State<VenueIdentificationView> {
  String? _selectedVenue;
  bool _showNearbyVenues = false;
  final _announcementRepository = AnnouncementRepository();
  List<Announcement> _recentAnnouncements = [];
  RealtimeChannel? _announcementChannel;

  @override
  void initState() {
    super.initState();
    _loadRecentAnnouncements();
    _announcementChannel = _announcementRepository.subscribeToAnnouncements(_loadRecentAnnouncements);
  }

  @override
  void dispose() {
    final channel = _announcementChannel;
    if (channel != null) _announcementRepository.removeSubscription(channel);
    super.dispose();
  }

  Future<void> _loadRecentAnnouncements() async {
    try {
      final items = await _announcementRepository.getActiveAnnouncements();
      if (mounted) setState(() => _recentAnnouncements = items.take(2).toList());
    } catch (_) {
      // The full announcement page exposes retry/error UI. Keep the home preview quiet.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset('assets/logo.png', width: 38, height: 38),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Hello, Jeff', style: Theme.of(context).textTheme.headlineLarge),
                                const SizedBox(height: 2),
                                Text('Where are you traveling today?', style: Theme.of(context).textTheme.bodyMedium),
                              ],
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => context.push('/notifications'),
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.notifications_outlined, size: 22),
                              ),
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(color: AppColors.emergency, shape: BoxShape.circle),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Quick Actions
                    Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildQuickAction(context, Icons.sign_language_rounded, 'Sign\nTranslate', AppColors.primary, () => context.push('/sign-camera')),
                          _buildQuickAction(context, Icons.record_voice_over, 'Speech\nto Sign', AppColors.accent, () => context.push('/speech-to-sign')),
                          _buildQuickAction(context, Icons.forum_rounded, 'Two-Way\nDialogue', AppColors.secondary, () => context.push('/dialogue')),
                          _buildQuickAction(context, Icons.menu_book_rounded, 'Sign\nDictionary', AppColors.primaryDark, () => context.push('/sign-dictionary')),
                          _buildQuickAction(context, Icons.help_outline_rounded, 'Request\nHelp', AppColors.emergency, () => context.push('/assistance-request')),
                          _buildQuickAction(context, Icons.confirmation_number_outlined, 'Queue Number\nTracking', AppColors.accent, () => context.push('/queue')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Connected venue
              if (_selectedVenue != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildConnectedVenue(context),
                ),
                const SizedBox(height: 24),
              ],

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Identify Your Location', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search institution, airport, hotel...',
                        prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                        suffixIcon: Container(
                          margin: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _showNearbyVenues = !_showNearbyVenues),
                        icon: const Icon(Icons.near_me_outlined, size: 20),
                        label: Text(_showNearbyVenues ? 'Hide Nearby Institutions' : 'Detect Nearby Institutions'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Nearby Venues
              if (_showNearbyVenues) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Nearby Venues', style: Theme.of(context).textTheme.titleMedium),
                      TextButton(onPressed: () {}, child: const Text('See All')),
                    ],
                  ),
                ),
                ...[
                  const _VenueData('KLIA Terminal 1', 'Airport', Icons.flight, '0.5 km', true),
                  const _VenueData('Gateway@klia2 Hotel', 'Hotel', Icons.hotel, '1.2 km', true),
                  const _VenueData('Sepang International Circuit', 'Attraction', Icons.attractions, '8.5 km', false),
                ].map((v) => _buildVenueCard(context, v)),
              ],
              const SizedBox(height: 24),

              // Recent announcements
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Announcements', style: Theme.of(context).textTheme.titleMedium),
                    TextButton(onPressed: () => context.push('/announcements'), child: const Text('View All')),
                  ],
                ),
              ),
              ..._recentAnnouncements.map((announcement) => _buildAnnouncementCard(context, announcement)),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedVenue(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.85)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_on, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Connected to', style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text(_selectedVenue!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                const Text('Terminal 1, Zone A', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: AppColors.successLight, size: 24),
        ],
      ),
    );
  }

  Widget _buildQuickAction(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.2)),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueCard(BuildContext context, _VenueData venue) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _selectedVenue = venue.name),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(venue.icon, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(venue.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(venue.type, style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(width: 8),
                          Text('• ${venue.distance}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
                if (venue.accessible)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.successLight.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.accessible, size: 12, color: AppColors.success),
                        SizedBox(width: 4),
                        Text('Accessible', style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnouncementCard(BuildContext context, Announcement announcement) {
    final urgent = announcement.isUrgent;
    final color = announcement.priority == 'urgent' ? AppColors.emergency : urgent ? AppColors.secondary : AppColors.primary;
    final icon = switch (announcement.type) {
      'boarding' => Icons.flight_takeoff,
      'delay_cancellation' => Icons.schedule,
      'emergency' => Icons.warning_amber_rounded,
      'travel_update' => Icons.swap_horiz,
      _ => Icons.campaign_outlined,
    };
    final elapsed = DateTime.now().difference(announcement.publishedAt);
    final time = elapsed.inMinutes < 1 ? 'Just now' : elapsed.inMinutes < 60 ? '${elapsed.inMinutes} min ago' : '${elapsed.inHours} hr ago';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: urgent ? BorderSide(color: color, width: 1) : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(announcement.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        Text(time, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(announcement.messageEn, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VenueData {
  final String name, type;
  final IconData icon;
  final String distance;
  final bool accessible;
  const _VenueData(this.name, this.type, this.icon, this.distance, this.accessible);
}

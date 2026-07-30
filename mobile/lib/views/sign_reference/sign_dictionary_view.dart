import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

class SignDictionaryView extends StatefulWidget {
  const SignDictionaryView({super.key});

  @override
  State<SignDictionaryView> createState() => _SignDictionaryViewState();
}

class _SignDictionaryViewState extends State<SignDictionaryView> {
  String _selectedCategory = 'All';
  
  final _categories = [
    _CategoryItem('All', Icons.grid_view),
    _CategoryItem('Airport', Icons.flight_takeoff),
    _CategoryItem('Hotel', Icons.hotel),
    _CategoryItem('Restaurant', Icons.restaurant),
    _CategoryItem('Transit', Icons.directions_bus),
    _CategoryItem('Medical', Icons.local_hospital),
    _CategoryItem('Emergency', Icons.warning_amber),
  ];

  final _phrases = [
    const _Phrase('Hello / Greeting', 'General', Icons.waving_hand_outlined),
    const _Phrase('Thank you', 'General', Icons.volunteer_activism_outlined),
    const _Phrase('Where is the gate?', 'Airport', Icons.flight_takeoff_outlined),
    const _Phrase('I need to check in', 'Airport', Icons.confirmation_number_outlined),
    const _Phrase('My flight is delayed', 'Airport', Icons.schedule_outlined),
    const _Phrase('I have a reservation', 'Hotel', Icons.hotel_outlined),
    const _Phrase('Where is the bathroom?', 'General', Icons.wc_outlined),
    const _Phrase('I need help', 'Emergency', Icons.sos_outlined),
    const _Phrase('How much does it cost?', 'General', Icons.payments_outlined),
    const _Phrase('Can I get the menu?', 'Restaurant', Icons.restaurant_menu_outlined),
    const _Phrase('Which bus to take?', 'Transit', Icons.directions_bus_outlined),
    const _Phrase('I feel sick', 'Medical', Icons.local_hospital_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Dictionary'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite_border),
            onPressed: () => context.push('/favorite-phrases'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search signs and phrases...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                suffixIcon: Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.tune, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
          // Categories
          SizedBox(
            height: 52,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: _categories.length,
              itemBuilder: (context, i) {
                final cat = _categories[i];
                final selected = cat.name == _selectedCategory;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat.name),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cat.icon, size: 16, color: selected ? Colors.white : AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          cat.name,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: selected ? Colors.white : AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Language toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildLangToggle('BIM (Malaysia)', true),
                const SizedBox(width: 8),
                _buildLangToggle('ASL (USA)', false),
                const Spacer(),
                Text('${_phrases.length} phrases', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Phrases list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _phrases.length,
              itemBuilder: (context, i) => _buildPhraseCard(context, _phrases[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhraseCard(BuildContext context, _Phrase phrase) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/sign-media'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(phrase.icon, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(phrase.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(4)),
                          child: Text(phrase.category, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.play_circle_outline, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text('Video + Audio', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.favorite_border, size: 20, color: AppColors.textMuted),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLangToggle(String label, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? AppColors.primary : AppColors.cardBorder),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: selected ? AppColors.primary : AppColors.textMuted)),
    );
  }
}

class _CategoryItem {
  final String name;
  final IconData icon;
  const _CategoryItem(this.name, this.icon);
}

class _Phrase {
  final String text;
  final String category;
  final IconData icon;
  const _Phrase(this.text, this.category, this.icon);
}

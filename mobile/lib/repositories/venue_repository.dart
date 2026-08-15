import '../core/supabase_client.dart';
import '../models/venue_search_result.dart';

class VenueRepository {
  Future<List<VenueSearchResult>> search(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final response = await SupabaseClientHelper.client.functions.invoke(
      'search-venues',
      body: {'query': term},
    );
    final rows =
        (response.data as Map<String, dynamic>)['venues'] as List<dynamic>? ??
        const [];
    return rows
        .map((row) => VenueSearchResult.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

class MetricsService {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getStepsLog(String userId) async {
    final response = await supabase
        .from('steps_log')
        .select()
        .eq('user_id', userId)
        .order('date', ascending: true)
        .limit(7); // get recent 7 days

    if (response == null || response.isEmpty) return [];

    return List<Map<String, dynamic>>.from(response);
  }
}

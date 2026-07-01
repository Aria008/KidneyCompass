import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StepTrackerService {
  static final StepTrackerService _instance = StepTrackerService._internal();
  factory StepTrackerService() => _instance;
  StepTrackerService._internal();

  bool _autoSyncEnabled = false;

  /// Check if auto sync is enabled
  bool get isAutoSyncEnabled => _autoSyncEnabled;

  /// Initialize and load preferences
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _autoSyncEnabled = prefs.getBool('step_auto_sync_enabled') ?? false;
  }

  /// Enable/disable auto sync (placeholder for future Google Fit integration)
  Future<bool> toggleAutoSync() async {
    final prefs = await SharedPreferences.getInstance();
    _autoSyncEnabled = !_autoSyncEnabled;
    await prefs.setBool('step_auto_sync_enabled', _autoSyncEnabled);
    
    if (_autoSyncEnabled) {
      // TODO: Future Google Fit integration will go here
      print('Auto sync enabled - Google Fit integration will be added later');
      return true;
    } else {
      print('Auto sync disabled');
      return true;
    }
  }

  /// Manually save steps to database
  Future<bool> saveStepsForDate(DateTime date, int steps) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return false;

      final dateStr = date.toIso8601String().substring(0, 10);
      
      await Supabase.instance.client.from('health_metrics').upsert({
        'user_id': user.id,
        'metric_type': 'steps',
        'value': steps,
        'date': dateStr,
      });

      return true;
    } catch (e) {
      print('Error saving steps: $e');
      return false;
    }
  }

  /// Save today's steps
  Future<bool> saveTodaySteps(int steps) async {
    return await saveStepsForDate(DateTime.now(), steps);
  }

  /// Get steps for a specific date from database
  Future<int?> getStepsForDate(DateTime date) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;

      final dateStr = date.toIso8601String().substring(0, 10);
      
      final response = await Supabase.instance.client
          .from('health_metrics')
          .select('value')
          .eq('user_id', user.id)
          .eq('metric_type', 'steps')
          .eq('date', dateStr)
          .maybeSingle();

      if (response != null) {
        return (response['value'] as num?)?.round();
      }
      
      return null;
    } catch (e) {
      print('Error getting steps: $e');
      return null;
    }
  }

  /// Get today's steps from database
  Future<int?> getTodaySteps() async {
    return await getStepsForDate(DateTime.now());
  }

  /// Get weekly steps data
  Future<Map<String, int>> getWeeklySteps() async {
    Map<String, int> weekSteps = {};
    final today = DateTime.now();

    for (int i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final dateKey = date.toIso8601String().substring(0, 10);
      final steps = await getStepsForDate(date);
      
      if (steps != null) {
        weekSteps[dateKey] = steps;
      }
    }

    return weekSteps;
  }

  /// Import steps from external app (placeholder for future implementation)
  Future<String?> importStepsFromExternalApp() async {
    // This is a placeholder for future Google Fit/Health Connect integration
    // For now, return a message indicating manual entry is required
    return 'Google Fit integration coming soon! Please enter steps manually for now.';
  }

  /// Check if external health app is available (placeholder)
  Future<bool> isExternalHealthAppAvailable() async {
    // Placeholder - will check for Google Fit/Health Connect in future
    return false;
  }

  /// Get platform name for health integration
  String getHealthPlatformName() {
    return 'Manual Entry (Google Fit integration coming soon)';
  }
} 
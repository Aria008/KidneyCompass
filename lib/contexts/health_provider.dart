import 'package:flutter/material.dart';

class HealthProvider extends ChangeNotifier {
  List<Map<String, dynamic>> healthMetrics = [];
  List<Map<String, dynamic>> bloodPressureReadings = [];
  List<Map<String, dynamic>> moodEntries = [];
  bool isLoading = false;

  Future<void> addHealthMetric(String type, double value) async {
    healthMetrics.add({
      'type': type,
      'value': value,
      'timestamp': DateTime.now(),
    });
    notifyListeners();
  }

  Future<void> addBloodPressure(int systolic, int diastolic) async {
    bloodPressureReadings.add({
      'systolic': systolic,
      'diastolic': diastolic,
      'timestamp': DateTime.now(),
    });
    notifyListeners();
  }

  Future<void> addMoodEntry(int score, {String? note}) async {
    moodEntries.add({
      'score': score,
      'note': note,
      'timestamp': DateTime.now(),
    });
    notifyListeners();
  }

  Future<void> refreshData() async {
    // Add Supabase fetch logic here if needed
    notifyListeners();
  }
}

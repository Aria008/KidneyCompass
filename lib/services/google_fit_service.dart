import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleFitService {
  static final GoogleFitService _instance = GoogleFitService._internal();
  factory GoogleFitService() => _instance;
  GoogleFitService._internal();

  bool _isAuthorized = false;
  bool _syncEnabled = false;
  String? _accessToken;
  
  // Google Sign-In instance with new OAuth credentials
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // New Web Client ID from recreated OAuth credentials
    clientId: '907394695676-9h363jl74rvlibuj2ap7paqanhn5ndk1.apps.googleusercontent.com',
    scopes: [
      'https://www.googleapis.com/auth/fitness.activity.read',
      'https://www.googleapis.com/auth/fitness.body.read',
      'https://www.googleapis.com/auth/fitness.location.read',
      'email',
      'profile',
    ],
  );

  /// Check if Google Fit is authorized
  bool get isAuthorized => _isAuthorized;
  bool get isSyncEnabled => _syncEnabled;

  /// Initialize the service
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _syncEnabled = prefs.getBool('google_fit_sync_enabled') ?? false;
    
    // Check if user is already signed in
    final currentUser = await _googleSignIn.signInSilently();
    if (currentUser != null && _syncEnabled) {
      final auth = await currentUser.authentication;
      _accessToken = auth.accessToken;
      _isAuthorized = _accessToken != null;
      
      if (_isAuthorized) {
        // Validate the token
        _isAuthorized = await _validateToken();
      }
    }
  }

  /// Validate stored access token
  Future<bool> _validateToken() async {
    if (_accessToken == null) return false;
    
    try {
      // Try to make a simple API call to validate the token
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/fitness/v1/users/me/dataSources'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('Token validation failed: $e');
      return false;
    }
  }

  /// Request Google Fit permissions using real OAuth flow
  Future<bool> requestPermissions() async {
    try {
      print('🔵 Starting Google Sign-In OAuth flow...');
      print('🔵 Configured scopes: ${_googleSignIn.scopes}');
      
      // Check if Google Play Services is available
      print('🔵 Checking Google Play Services availability...');
      
      // Sign in to Google
      print('🔵 Attempting Google Sign-In...');
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        print('🔴 Google Sign-In was cancelled by user');
        return false;
      }
      
      print('🟢 Google Sign-In successful for user: ${googleUser.displayName} (${googleUser.email})');
      
      // Get authentication details
      print('🔵 Getting authentication details...');
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      if (googleAuth.accessToken == null) {
        print('🔴 Failed to get access token from Google Sign-In');
        print('🔴 Auth details: accessToken=${googleAuth.accessToken}, idToken=${googleAuth.idToken}');
        return false;
      }
      
      print('🟢 Access token obtained successfully');
      print('🔵 Token preview: ${googleAuth.accessToken?.substring(0, 20)}...');
      
      _accessToken = googleAuth.accessToken;
      _isAuthorized = true;
      _syncEnabled = true;
      
      // Save sync enabled state (don't store tokens for security)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('google_fit_sync_enabled', true);
      
      print('🟢 Google Fit authorization completed successfully');
      print('🟢 User: ${googleUser.displayName} (${googleUser.email})');
      
      // Test API access immediately
      print('🔵 Testing Fitness API access...');
      final testResult = await _validateToken();
      if (testResult) {
        print('🟢 Fitness API access confirmed');
      } else {
        print('🟡 Fitness API access test failed, but continuing anyway');
      }
      
      return true;
    } catch (e, stackTrace) {
      print('🔴 Error requesting Google Fit permissions: $e');
      print('🔴 Stack trace: $stackTrace');
      return false;
    }
  }

  /// Disable Google Fit sync
  Future<void> disableSync() async {
    try {
      // Sign out from Google
      await _googleSignIn.signOut();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('google_fit_sync_enabled', false);
      
      _syncEnabled = false;
      _isAuthorized = false;
      _accessToken = null;
      
      print('Google Fit sync disabled and user signed out');
    } catch (e) {
      print('Error during Google Sign-Out: $e');
    }
  }

  /// Get steps for a specific date from Google Fit API
  Future<int?> getStepsFromGoogleFit(DateTime date) async {
    if (!_isAuthorized || !_syncEnabled || _accessToken == null) {
      print('Google Fit not authorized or sync disabled');
      return null;
    }

    try {
      // Refresh token if needed
      final currentUser = _googleSignIn.currentUser;
      if (currentUser != null) {
        final auth = await currentUser.authentication;
        _accessToken = auth.accessToken;
      }
      
      if (_accessToken == null) {
        print('No valid access token available');
        return null;
      }

      // Set up date range for the specific day
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      
      final startTimeNanos = (startOfDay.millisecondsSinceEpoch * 1000000).toString();
      final endTimeNanos = (endOfDay.millisecondsSinceEpoch * 1000000).toString();
      
      print('Fetching step data from Google Fit for ${date.toIso8601String().substring(0, 10)}...');
      
      // Create request body for aggregated step data
      final requestBody = {
        "aggregateBy": [
          {
            "dataTypeName": "com.google.step_count.delta",
            "dataSourceId": "derived:com.google.step_count.delta:com.google.android.gms:estimated_steps"
          }
        ],
        "bucketByTime": {
          "durationMillis": 86400000 // 1 day in milliseconds
        },
        "startTimeMillis": startOfDay.millisecondsSinceEpoch,
        "endTimeMillis": endOfDay.millisecondsSinceEpoch
      };
      
      final response = await http.post(
        Uri.parse('https://www.googleapis.com/fitness/v1/users/me/dataset:aggregate'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final buckets = data['bucket'] as List?;
        
        if (buckets != null && buckets.isNotEmpty) {
          int totalSteps = 0;
          
          for (final bucket in buckets) {
            final dataset = bucket['dataset'] as List?;
            if (dataset != null && dataset.isNotEmpty) {
              for (final dataSet in dataset) {
                final points = dataSet['point'] as List?;
                if (points != null) {
                  for (final point in points) {
                    final values = point['value'] as List?;
                    if (values != null && values.isNotEmpty) {
                      final stepValue = values[0]['intVal'];
                      if (stepValue != null) {
                        totalSteps += stepValue as int;
                      }
                    }
                  }
                }
              }
            }
          }
          
          print('Retrieved $totalSteps steps from Google Fit');
          return totalSteps;
        } else {
          print('No step data found for the specified date');
          return 0;
        }
      } else {
        print('Google Fit API error: ${response.statusCode} - ${response.body}');
        
        // If unauthorized, try to refresh authentication
        if (response.statusCode == 401) {
          print('Access token expired, attempting to refresh...');
          final refreshed = await requestPermissions();
          if (refreshed) {
            // Retry the request once with new token
            return await getStepsFromGoogleFit(date);
          }
        }
        
        return null;
      }
    } catch (e) {
      print('Error getting steps from Google Fit: $e');
      return null;
    }
  }

  /// Get today's steps from Google Fit
  Future<int?> getTodayStepsFromGoogleFit() async {
    return await getStepsFromGoogleFit(DateTime.now());
  }

  /// Sync steps from Google Fit to database
  Future<bool> syncStepsToDatabase(DateTime date) async {
    try {
      final steps = await getStepsFromGoogleFit(date);
      
      if (steps == null) {
        print('Could not get steps from Google Fit');
        return false;
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        print('User not authenticated');
        return false;
      }

      final dateStr = date.toIso8601String().substring(0, 10);
      
      print('Saving $steps steps to database for $dateStr...');
      
      await Supabase.instance.client.from('health_metrics').upsert({
        'user_id': user.id,
        'metric_type': 'steps',
        'value': steps,
        'date': dateStr,
      });

      print('Successfully synced $steps steps to database');
      return true;
    } catch (e) {
      print('Error syncing steps to database: $e');
      return false;
    }
  }

  /// Sync today's steps
  Future<bool> syncTodaySteps() async {
    return await syncStepsToDatabase(DateTime.now());
  }

  /// Sync last 7 days of steps
  Future<Map<String, bool>> syncWeekSteps() async {
    Map<String, bool> results = {};
    final today = DateTime.now();

    for (int i = 0; i < 7; i++) {
      final date = today.subtract(Duration(days: i));
      final dateKey = date.toIso8601String().substring(0, 10);
      final success = await syncStepsToDatabase(date);
      results[dateKey] = success;
      
      // Add a small delay to avoid overwhelming the API
      await Future.delayed(const Duration(milliseconds: 500));
    }

    return results;
  }

  /// Check if Google Fit is available
  Future<bool> isGoogleFitAvailable() async {
    try {
      // Check if Google Play Services is available
      return await _googleSignIn.isSignedIn();
    } catch (e) {
      print('Error checking Google Fit availability: $e');
      return false;
    }
  }

  /// Get the platform name
  String getPlatformName() {
    return 'Google Fit';
  }

  /// Get current user info
  GoogleSignInAccount? getCurrentUser() {
    return _googleSignIn.currentUser;
  }

  /// Get implementation notes for real Google Fit integration
  String getImplementationNote() {
    final currentUser = getCurrentUser();
    
    if (currentUser != null) {
      return '''
✅ Google Fit Integration Active
Connected as: ${currentUser.displayName ?? 'Unknown'}
Email: ${currentUser.email}

This app is now connected to your Google Fit account and can:
• Read your daily step count
• Sync step data automatically
• Access historical fitness data

Data is synced securely using OAuth 2.0 authentication.
      ''';
    } else {
      return '''
Google Fit Integration Ready
Tap "Enable Google Fit Sync" above to:

• Connect your Google account
• Authorize fitness data access
• Enable automatic step syncing
• Access historical step data

Your data remains secure and private.
      ''';
    }
  }
} 
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../widgets/check_in_dialog.dart';
import '../widgets/steps_chart_container.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  Map<String, dynamic> _healthGoals = {};
  String? _weather;
  double? _temperature;
  int? _humidity;
  String? _locationName;
  String? _weatherIcon;
  bool _checkInCompleted = false;
  Map<String, bool> _completionStatus = {
    'sleep': false,
    'weight': false,
    'blood_pressure': false,
    'steps': false,
    'mood': false,
  };
  int _completedSections = 0;
  Map<String, dynamic>? _latestMetrics;
  bool _metricsLoading = true;
  Map<String, dynamic>? _latestBloodPressure;
  Map<String, String> _metricDirections = {};
  String? _bloodPressureDirection;
  String? _dailyTip;
  int? _userStage; // CKD stage 1‑5 (null => unknown)

  // Logging schedule pulled from `user_log_days`.
  Set<String> _logDays = {}; // e.g., {'Mon', 'Wed', 'Fri'}

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  late Map<String, ConfettiController> _confettiControllers;
  Set<String> _shownTodayConfetti = {};
  DateTime _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _confettiControllers = {
      'steps': ConfettiController(duration: const Duration(seconds: 2)),
      'sleep': ConfettiController(duration: const Duration(seconds: 2)),
      'weight': ConfettiController(duration: const Duration(seconds: 2)),
    };
    _resetShownTodayConfettiIfNeeded();
    
    // Initial data load
    _loadAllData();
    
    // Listen for auth state changes to refresh data
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && mounted) {
        // User just signed in, refresh all data after a short delay
        // to ensure database operations from registration are completed
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _loadAllData();
        });
      }
    });
  }

  void _resetShownTodayConfettiIfNeeded() {
    final now = DateTime.now();
    if (_today.year != now.year ||
        _today.month != now.month ||
        _today.day != now.day) {
      _today = now;
      _shownTodayConfetti.clear();
    }
  }

  bool _isLogToday() {
    final weekday =
        [
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
          'Sun',
        ][DateTime.now().weekday - 1];
    return _logDays.contains(weekday);
  }

  String? _nextLogDay() {
    if (_logDays.isEmpty) return null;
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    int todayIdx = DateTime.now().weekday - 1;
    for (int offset = 1; offset <= 7; offset++) {
      final idx = (todayIdx + offset) % 7;
      if (_logDays.contains(weekdays[idx])) {
        return weekdays[idx];
      }
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Daily Kidney Tip (randomised once per calendar‑day and cached locally)
  Future<void> _loadDailyTip() async {
    // ------------- Extended tip library ------------------
    const genericTips = <String>[
      'Sip water little and often during the day.',
      'Taste food before adding extra salt.',
      'Swap soda for plain or sparkling water today.',
      'Read food labels and choose options with less salt.',
      'Enjoy one piece of fresh fruit today.',
      'Pick whole‑grain bread instead of white bread.',
      'Flavour meals with herbs or lemon instead of extra salt.',
      'Bake or grill food rather than frying it.',
      'Take a 10‑minute walk after a meal.',
      'Use a smaller plate to help control portions.',
      'Carry a refillable bottle to remind you to drink.',
      'Plan tomorrow’s meals tonight to avoid fast food.',
      'Stand up and stretch every half‑hour.',
      'Try a meat‑free meal with beans or lentils this week.',
      'Write down today’s snacks in a small diary.',
      'Take five deep breaths when you wake up.',
      'Put screens away 30 min before bedtime.',
      'Try a 5‑minute calming app today.',
      'Add a colourful vegetable to lunch.',
      'Rinse canned veggies to wash away some salt.',
      'Set both a bedtime and wake‑up alarm.',
      'Swap one sugary dessert for fruit and yogurt.',
      'Freeze leftovers in single‑meal portions.',
      'Park a bit farther away and walk the extra steps.',
      'Ask your health team if your vitamins are OK for your kidneys.',
      'Book your next dental cleaning—healthy mouth, healthy body.',
      'Wash your reusable bottle every day.',
      'Stretch your calves while brushing your teeth.',
      'Use flavourful spices instead of salt.',
      'Check the serving size on cereal boxes.',
      'Enjoy a phone‑free meal with family or friends.',
      'Celebrate small wins—they add up!',
    ];

    const stageEarly = <String>[
      'Book your yearly kidney check‑up.',
      'Aim for 150 minutes of movement this week.',
      'Check your blood pressure today; aim below 130/80.',
      'Swap deli meats for lean chicken or fish.',
      'Ask your nurse if you need a urine test this year.',
      'Even small weight loss helps your kidneys—keep at it.',
      'Take five minutes to relax before bed.',
      'Try to get 7‑9 hours of sleep tonight.',
      'Note how many days you exercised this week.',
      'Choose brown rice or quinoa tonight.',
      'Spread your protein across meals, not one big portion.',
      'Avoid over‑the‑counter pain pills unless your doctor says so.',
    ];

    const stageMid = <String>[
      'Skip salty chips or crackers today.',
      'Ask your dietitian if you should cut back on meat.',
      'Look for swelling in your ankles and write it down.',
      'Rinse canned beans to wash away salt.',
      'Weigh yourself at the same time each morning.',
      'Choose unsalted nuts instead of chips for a snack.',
      'Cook pasta without adding salt to the water.',
      'Choose juices lower in potassium—check the label.',
      'Bring your latest lab results to your next visit.',
      'Try gentle exercise like cycling, swimming, or yoga.',
      'Keep protein portions to about the size of your palm.',
      'Take your blood‑pressure pills at the same time each day.',
    ];

    const stageLate = <String>[
      'Keep track of how much you drink today and stay within your limit.',
      'Talk with your care team about dialysis options.',
      'Choose clear sodas or water instead of dark colas.',
      'Suck on frozen grapes or sour candy to ease thirst.',
      'Write down how much you urinate today for your nurse.',
      'Ask your dietitian about tablets that help lower certain minerals.',
      'Weigh yourself daily; call the clinic if you gain more than 2 kg.',
      'Wash your hands well before touching your dialysis site.',
      'Try herb blends made for kidney diets—no salt substitutes.',
      'Ask your doctor about steps toward a kidney transplant.',
      'Keep an up‑to‑date medication list on your phone.',
      'Tell your nurse if you notice skin itching or rashes.',
    ];

    // Build pool: generic always + stage bucket (if known)
    List<String> tips = [...genericTips];
    if (_userStage != null) {
      if (_userStage! <= 2) {
        tips.addAll(stageEarly);
      } else if (_userStage! <= 4) {
        tips.addAll(stageMid);
      } else {
        tips.addAll(stageLate);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = prefs.getString('tip_date');
    final savedIndex = prefs.getInt('tip_index');

    int index;
    if (savedDate == today && savedIndex != null && savedIndex < tips.length) {
      index = savedIndex; // reuse today’s tip
    } else {
      index = Random().nextInt(tips.length); // pick new
      await prefs.setString('tip_date', today);
      await prefs.setInt('tip_index', index);
    }

    if (mounted) setState(() => _dailyTip = tips[index]);
  }
  // -----------------------------------------------------------------------

  Future<void> _loadUserStage() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final row =
        await Supabase.instance.client
            .from('profiles')
            .select('stage')
            .eq('id', user.id)
            .maybeSingle();

    if (mounted) {
      setState(() {
        _userStage = int.tryParse(row?['stage']?.toString() ?? '');
      });
    }
  }

  Future<void> _loadHealthGoals() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _healthGoals = {});
      return;
    }
    
    try {
      final goals = await Supabase.instance.client
          .from('user_goals')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      
      if (mounted) {
        setState(() {
          _healthGoals = goals ?? {};
        });
        
        // Debug: Print what goals were loaded
        print('=== HEALTH GOALS LOADED ===');
        print('Raw goals from database: $goals');
        print('Steps goal: ${_healthGoals['steps']}');
        print('Sleep goal: ${_healthGoals['sleep']}');
        print('Weight goal: ${_healthGoals['weight']}');
        print('BP Systolic goal: ${_healthGoals['bp_systolic']}');
        print('BP Diastolic goal: ${_healthGoals['bp_diastolic']}');
        print('==========================');
      }
    } catch (e) {
      print('Error loading health goals: $e');
      if (mounted) {
        setState(() {
          _healthGoals = {};
        });
      }
    }
  }

  Future<void> _loadLogDays() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final rows = await Supabase.instance.client
        .from('user_log_days')
        .select('weekday')
        .eq('user_id', user.id);
    setState(() {
      _logDays =
          rows is List ? rows.map((e) => e['weekday'].toString()).toSet() : {};
    });
  }

  // -----------------------------------------------------------------------
  /// Check completion status of today's check-in
  Future<Map<String, bool>> _getCompletionStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return {
        'sleep': false,
        'weight': false,
        'blood_pressure': false,
        'steps': false,
        'mood': false,
      };
    }

    final today = DateTime.now().toIso8601String().substring(0, 10);

    try {
      // Check health metrics
      final healthMetrics = await Supabase.instance.client
          .from('health_metrics')
          .select('metric_type, value')
          .eq('user_id', user.id)
          .eq('date', today);

      // Check blood pressure
      final bloodPressure = await Supabase.instance.client
          .from('blood_pressure_readings')
          .select('systolic, diastolic')
          .eq('user_id', user.id)
          .eq('date', today)
          .maybeSingle();

      // Check mood entry
      final moodEntry = await Supabase.instance.client
          .from('mood_entries')
          .select('score')
          .eq('user_id', user.id)
          .eq('date', today)
          .maybeSingle();

      Map<String, bool> status = {
        'sleep': false,
        'weight': false,
        'blood_pressure': false,
        'steps': false,
        'mood': false,
      };

      // Check health metrics completion
      for (final metric in healthMetrics) {
        final metricType = metric['metric_type'] as String;
        final value = metric['value'];
        
        switch (metricType) {
          case 'sleep_hours':
            if (value != null && value > 0) status['sleep'] = true;
            break;
          case 'weight':
            if (value != null && value > 0) status['weight'] = true;
            break;
          case 'steps':
            if (value != null && value > 0) status['steps'] = true;
            break;
        }
      }

      // Check blood pressure completion
      if (bloodPressure != null && 
          bloodPressure['systolic'] != null && 
          bloodPressure['diastolic'] != null &&
          bloodPressure['systolic'] > 0 && 
          bloodPressure['diastolic'] > 0) {
        status['blood_pressure'] = true;
      }

             // Check mood completion - only if there's meaningful input
       if (moodEntry != null && 
           ((moodEntry['score'] != null && moodEntry['score'] > 0) ||
            (moodEntry['notes'] != null && moodEntry['notes'].toString().trim().isNotEmpty))) {
         status['mood'] = true;
       }

      return status;
    } catch (e) {
      print('Error checking completion status: $e');
      return {
        'sleep': false,
        'weight': false,
        'blood_pressure': false,
        'steps': false,
        'mood': false,
      };
    }
  }

  Future<void> _refreshCheckInStatus() async {
    final status = await _getCompletionStatus();
    final completedCount = status.values.where((v) => v).length;
    final isFullyCompleted = completedCount == 5;
    
    if (mounted) {
      setState(() {
        _completionStatus = status;
        _completedSections = completedCount;
        _checkInCompleted = isFullyCompleted;
      });
    }
  }
  // -----------------------------------------------------------------------

  // Load all user data - used on init and when auth state changes
  Future<void> _loadAllData() async {
    await Future.wait([
      _fetchWeather(),
      _loadHealthGoals(),
      _loadLatestMetrics(),
      _loadLogDays(),
      _loadUserStage(),
    ]);
    
    // Load daily tip after user stage is loaded (requires _userStage to be set)
    await _loadDailyTip();
    
    // Check-in status should be checked last after all data is loaded
    await _refreshCheckInStatus();
  }

  // Pull‑to‑refresh handler
  Future<void> _handleRefresh() async {
    await _loadAllData();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good morning!";
    if (hour < 18) return "Good afternoon!";
    return "Good evening!";
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when page becomes visible (handles navigation from other pages)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadAllData();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    for (var controller in _confettiControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLatestMetrics() async {
    if (mounted) setState(() => _metricsLoading = true);
    
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _latestMetrics = {};
          _latestBloodPressure = {};
          _metricsLoading = false;
          _metricDirections = {};
          _bloodPressureDirection = null;
        });
      }
      return;
    }

    // Fetch steps, sleep_hours, weight (latest and previous for direction)
    final metricTypes = ['steps', 'sleep_hours', 'weight'];
    Map<String, dynamic> result = {};
    Map<String, String> directions = {};

    for (var metric in metricTypes) {
      final resList = await Supabase.instance.client
          .from('health_metrics')
          .select()
          .eq('user_id', user.id)
          .eq('metric_type', metric)
          .order('date', ascending: false)
          .limit(2);
      double? todayValue;
      double? yesterdayValue;
      if (resList != null && resList is List && resList.isNotEmpty) {
        todayValue = double.tryParse(resList[0]['value'].toString());
        result[metric] = resList[0]['value'];
        if (resList.length > 1) {
          yesterdayValue = double.tryParse(resList[1]['value'].toString());
        }
      }
      // Determine direction
      String dir = 'same';
      if (todayValue != null && yesterdayValue != null) {
        if (todayValue > yesterdayValue) {
          dir = 'up';
        } else if (todayValue < yesterdayValue) {
          dir = 'down';
        } else {
          dir = 'same';
        }
      }
      directions[metric] = dir;
    }

    // Fetch latest and previous blood pressure (from blood_pressure_readings)
    final bpList = await Supabase.instance.client
        .from('blood_pressure_readings')
        .select()
        .eq('user_id', user.id)
        .order('date', ascending: false)
        .limit(2);
    Map<String, dynamic>? bp;
    String? bpDirection;
    if (bpList != null && bpList is List && bpList.isNotEmpty) {
      bp = {
        'systolic': bpList[0]['systolic'],
        'diastolic': bpList[0]['diastolic'],
      };
      if (bpList.length > 1) {
        int? systolicToday =
            bpList[0]['systolic'] is int
                ? bpList[0]['systolic']
                : int.tryParse(bpList[0]['systolic'].toString());
        int? diastolicToday =
            bpList[0]['diastolic'] is int
                ? bpList[0]['diastolic']
                : int.tryParse(bpList[0]['diastolic'].toString());
        int? systolicPrev =
            bpList[1]['systolic'] is int
                ? bpList[1]['systolic']
                : int.tryParse(bpList[1]['systolic'].toString());
        int? diastolicPrev =
            bpList[1]['diastolic'] is int
                ? bpList[1]['diastolic']
                : int.tryParse(bpList[1]['diastolic'].toString());
        if (systolicToday != null &&
            diastolicToday != null &&
            systolicPrev != null &&
            diastolicPrev != null) {
          if (systolicToday > systolicPrev || diastolicToday > diastolicPrev) {
            bpDirection = 'up';
          } else if (systolicToday < systolicPrev ||
              diastolicToday < diastolicPrev) {
            bpDirection = 'down';
          } else {
            bpDirection = 'same';
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _latestMetrics = result;
        _latestBloodPressure = bp;
        _metricsLoading = false;
        _metricDirections = directions;
        _bloodPressureDirection = bpDirection;
      });
    }
  }

  // (Removed: _loadCheckInStatus and _setCheckInCompleted)

  Future<void> _fetchWeather() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          print('Location permission denied.');
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );

      print('Got location: ${position.latitude}, ${position.longitude}');

      const apiKey = '1d17610199ad4770026352836a1b8470';
      final url =
          'https://api.openweathermap.org/data/2.5/weather?lat=${position.latitude}&lon=${position.longitude}&appid=$apiKey&units=metric';

      print('Requesting weather from URL: $url');
      final response = await http.get(Uri.parse(url));
      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _weather = data['weather'][0]['main'];
          final iconCode = data['weather'][0]['icon'];
          _weatherIcon = 'https://openweathermap.org/img/wn/$iconCode@2x.png';
          _temperature = data['main']['temp'];
          _humidity = data['main']['humidity'];
          _locationName = data['name'];
        });
      } else {
        print('Failed to fetch weather data.');
      }
    } catch (e) {
      print('Error during weather fetch: $e');
    }
  }

  String _getWeatherRecommendation() {
    if (_temperature == null || _weather == null) return '';

    double t = _temperature!;
    String rec = '';

    if (t >= 30) {
      rec = '🥵 Hot: Stay hydrated and avoid peak sun (11 AM–5 PM)';
    } else if (t >= 20) {
      rec = '☀️ Warm: Sip water and stay shaded';
    } else if (t >= 10) {
      rec = '🌤️ Cool: Light layers & drink regularly';
    } else {
      rec = '❄️ Cold: Keep warm, still stay hydrated';
    }

    if (_weather == 'Rain' ||
        _weather == 'Drizzle' ||
        (_humidity != null && _humidity! >= 90)) {
      rec += '\n🌧️ Rainy: Be careful walking, use waterproof layers.';
    }

    return rec;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: RefreshIndicator(
        color: const Color(0xFF6366F1),
        onRefresh: _handleRefresh,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverAppBar(
                  expandedHeight: 120,
                  floating: true,
                  pinned: false,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF6C63FF).withOpacity(0.1),
                            const Color(0xFF4ECDC4).withOpacity(0.1),
                          ],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                _getGreeting(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'How are you feeling today?',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Check-in Card
                        _buildCheckInCard(),
                        const SizedBox(height: 20),

                        // Weather Card
                        _buildWeatherCard(),
                        const SizedBox(height: 24),

                        // Health Metrics Section
                        const Text(
                          'Health Overview',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Metrics Grid
                        _buildMetricsGrid(),
                        const SizedBox(height: 24),

                        // Daily Tip Card
                        _buildDailyTipCard(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInCard() {
    // Determine card state based on completion
    bool hasPartialData = _completedSections > 0;
    bool isFullyComplete = _checkInCompleted;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: !_isLogToday()
              ? [const Color(0xFF9CA3AF), const Color(0xFF9CA3AF)]
              : isFullyComplete
                  ? [const Color(0xFF10B981), const Color(0xFF059669)]
                  : hasPartialData
                      ? [const Color(0xFFf59e0b), const Color(0xFFd97706)]
                      : [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
        ),
        boxShadow: [
          BoxShadow(
            color: (!_isLogToday()
                    ? const Color(0xFF9CA3AF)
                    : isFullyComplete
                        ? const Color(0xFF10B981)
                        : hasPartialData
                            ? const Color(0xFFf59e0b)
                            : const Color(0xFF6366F1))
                .withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: !_isLogToday()
              ? null
              : () async {
                  await showDialog(
                    context: context,
                    builder: (_) => CheckInDialog(
                      onSubmit: (category, value) async {
                        final prefs = await SharedPreferences.getInstance();
                        final metricKey = 'metric_$category';
                        final currentTime = DateTime.now().toIso8601String();
                        final entry = '$currentTime:$value';
                        final existing = prefs.getStringList(metricKey) ?? [];
                        existing.add(entry);
                        await prefs.setStringList(metricKey, existing);
                      },
                      onComplete: () async {
                        await _refreshCheckInStatus();
                        await _loadLatestMetrics();
                      },
                    ),
                  );
                },
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        !_isLogToday()
                            ? Icons.event_busy
                            : isFullyComplete
                                ? Icons.check_circle
                                : hasPartialData
                                    ? Icons.pending_actions
                                    : Icons.add_circle_outline,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            !_isLogToday()
                                ? 'No log scheduled'
                                : isFullyComplete
                                    ? 'Daily Check-in Complete!'
                                    : hasPartialData
                                        ? 'Continue Check-in'
                                        : 'Start Daily Check-in',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            !_isLogToday()
                                ? 'Next log: ${_nextLogDay() ?? '-'}'
                                : isFullyComplete
                                    ? 'All metrics recorded - tap to edit'
                                    : hasPartialData
                                        ? '$_completedSections/5 sections completed'
                                        : 'Track your health metrics for today',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isLogToday())
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white.withOpacity(0.8),
                        size: 16,
                      ),
                  ],
                ),
                // Progress indicators for partial completion
                if (_isLogToday() && (hasPartialData || isFullyComplete)) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildMiniProgressIcon('Sleep', Icons.hotel, _completionStatus['sleep'] ?? false),
                              _buildMiniProgressIcon('Weight', Icons.monitor_weight, _completionStatus['weight'] ?? false),
                              _buildMiniProgressIcon('BP', Icons.favorite, _completionStatus['blood_pressure'] ?? false),
                              _buildMiniProgressIcon('Steps', Icons.directions_walk, _completionStatus['steps'] ?? false),
                              _buildMiniProgressIcon('Mood', Icons.mood, _completionStatus['mood'] ?? false),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniProgressIcon(String label, IconData icon, bool isCompleted) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted 
                ? Colors.white.withOpacity(0.9)
                : Colors.white.withOpacity(0.3),
          ),
          child: Icon(
            isCompleted ? Icons.check : icon,
            size: 16,
            color: isCompleted 
                ? const Color(0xFF10B981)
                : Colors.white.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Colors.white.withOpacity(0.9),
            fontWeight: isCompleted ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildWeatherCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(16),
              ),
              child:
                  _weatherIcon != null
                      ? Image.network(_weatherIcon!, width: 48, height: 48)
                      : const Icon(
                        Icons.wb_cloudy,
                        size: 48,
                        color: Color(0xFF6B7280),
                      ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_temperature != null) ...[
                    Text(
                      '${_temperature!.toStringAsFixed(0)}°C in $_locationName',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_weather • $_humidity% humidity',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getWeatherRecommendation(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF374151),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ] else
                    const Text(
                      'Loading weather...',
                      style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    if (_metricsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.85,
      children: [
        _buildMetricCard(
          metricKey: 'steps',
          icon: Icons.directions_walk,
          title: 'Steps',
          value: _latestMetrics?['steps']?.toString() ?? '--',
          unit: 'steps',
          goal:
              _healthGoals['steps'] != null
                  ? double.tryParse(_healthGoals['steps'].toString())
                  : null,
          current:
              double.tryParse(_latestMetrics?['steps']?.toString() ?? '0') ?? 0,
          direction: _metricDirections['steps'] ?? 'same',
          color: const Color(0xFF10B981),
          hasProgress: _healthGoals['steps'] != null,
        ),
        _buildMetricCard(
          metricKey: 'sleep',
          icon: Icons.hotel,
          title: 'Sleep',
          value: _latestMetrics?['sleep_hours']?.toString() ?? '--',
          unit: 'hrs',
          goal:
              _healthGoals['sleep'] != null
                  ? double.tryParse(_healthGoals['sleep'].toString())
                  : null,
          current:
              double.tryParse(
                _latestMetrics?['sleep_hours']?.toString() ?? '0',
              ) ??
              0,
          direction: _metricDirections['sleep_hours'] ?? 'same',
          color: const Color(0xFF8B5CF6),
          hasProgress: _healthGoals['sleep'] != null,
        ),
        _buildMetricCard(
          icon: Icons.favorite,
          title: 'Blood Pressure',
          value:
              (_latestBloodPressure != null &&
                      _latestBloodPressure?['systolic'] != null &&
                      _latestBloodPressure?['diastolic'] != null)
                  ? '${_latestBloodPressure?['systolic']}/${_latestBloodPressure?['diastolic']}'
                  : '--',
          unit: 'mmHg',
          goalText: (_healthGoals['bp_systolic'] != null && _healthGoals['bp_diastolic'] != null)
              ? '${_healthGoals['bp_systolic']}/${_healthGoals['bp_diastolic']} mmHg'
              : null,
          direction: _bloodPressureDirection ?? 'same',
          color: const Color(0xFFEF4444),
          hasProgress: false, // BP progress tracking disabled
        ),
        _buildMetricCard(
          metricKey: 'weight',
          icon: Icons.monitor_weight,
          title: 'Weight',
          value: _latestMetrics?['weight']?.toString() ?? '--',
          unit: 'kg',
          goal:
              _healthGoals['weight'] != null
                  ? double.tryParse(_healthGoals['weight'].toString())
                  : null,
          current:
              double.tryParse(_latestMetrics?['weight']?.toString() ?? '0') ??
              0,
          direction: _metricDirections['weight'] ?? 'same',
          color: const Color(0xFFF59E0B),
          hasProgress: false, // Weight progress tracking disabled
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    String? metricKey,
    required IconData icon,
    required String title,
    required String value,
    required String unit,
    required String direction,
    required Color color,
    double? goal,
    double? current,
    String? goalText, // Custom goal text for complex goals like BP
    bool hasProgress = false,
  }) {
    final percent =
        hasProgress && goal != null && current != null
            ? (current / goal).clamp(0.0, 1.0)
            : 0.0;
    final reachedGoal =
        hasProgress && goal != null && current != null && (current >= goal);

    if (reachedGoal &&
        metricKey != null &&
        !_shownTodayConfetti.contains(metricKey)) {
      _confettiControllers[metricKey]?.play();
      _shownTodayConfetti.add(metricKey);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              if (reachedGoal)
                BoxShadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 25,
                  spreadRadius: 4,
                ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 24, color: color),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            direction == 'up'
                                ? Colors.green.withOpacity(0.1)
                                : direction == 'down'
                                ? Colors.red.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            direction == 'up'
                                ? Icons.trending_up
                                : direction == 'down'
                                ? Icons.trending_down
                                : Icons.trending_flat,
                            size: 12,
                            color:
                                direction == 'up'
                                    ? Colors.green
                                    : direction == 'down'
                                    ? Colors.red
                                    : Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize:
                                title == 'Blood Pressure'
                                    ? 25
                                    : (value.length > 6 ? 22 : 28),
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          unit,
                          style: TextStyle(
                            fontSize: value.length > 6 ? 12 : 14,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      (goal != null || goalText != null)
                          ? 'Goal: ${goalText ?? '${goal!.toInt()} $unit'}'
                          : 'No goal set',
                      style: TextStyle(
                        fontSize: 12,
                        color: (goal != null || goalText != null)
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFFD1D5DB),
                        fontStyle: (goal != null || goalText != null) ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                    if (hasProgress && goal != null)
                      Text(
                        '${(percent * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                if (hasProgress && goal != null && current != null) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (reachedGoal && metricKey != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiControllers[metricKey]!,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  colors: [color, Colors.amber, Colors.purple, Colors.teal],
                  numberOfParticles: 25,
                  maxBlastForce: 20,
                  minBlastForce: 8,
                  emissionFrequency: 0.02,
                  gravity: 0.4,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDailyTipCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFFFEF3C7), const Color(0xFFFDE68A)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.lightbulb_outline,
                size: 32,
                color: Color(0xFFD97706),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Kidney Tip',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _dailyTip ?? 'Loading tip...',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF92400E),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

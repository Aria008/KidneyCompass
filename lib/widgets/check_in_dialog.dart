import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../contexts/auth_context.dart';
import '../services/google_fit_service.dart';

/// User goals data loaded from database
class UserGoals {
  final double steps;
  final double sleep; 
  final double weight;
  final double bpSystolic;
  final double bpDiastolic;

  UserGoals({
    required this.steps,
    required this.sleep,
    required this.weight,
    required this.bpSystolic,
    required this.bpDiastolic,
  });

  String get stepTarget => 'Target: ${steps.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} steps';
  String get sleepTarget => 'Target: ${sleep.toStringAsFixed(1)} hours';
  String get bpTarget => 'Target: below ${bpSystolic.toInt()}/${bpDiastolic.toInt()} mmHg';
}

class CheckInDialog extends StatefulWidget {
  final Function(String category, dynamic value) onSubmit;
  final VoidCallback? onComplete;

  const CheckInDialog({super.key, required this.onSubmit, this.onComplete});

  @override
  State<CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<CheckInDialog>
    with TickerProviderStateMixin {
  int step = 0;
  final stepsController = TextEditingController();
  double sleepHours = 0;
  int sleepQuality = 0;
  final weightController = TextEditingController();
  final systolicController = TextEditingController();
  final diastolicController = TextEditingController();
  List<int> moodRatings = List.filled(5, 0);
  final notesController = TextEditingController();

  UserGoals? userGoals;
  bool _isLoadingGoals = true;
  Map<String, bool> completionStatus = {
    'sleep': false,
    'weight': false,
    'blood_pressure': false,
    'steps': false,
    'mood': false,
  };
  
  // Track which sections the user has actually interacted with
  Map<String, bool> sectionTouched = {
    'sleep': false,
    'weight': false,
    'blood_pressure': false,
    'steps': false,
    'mood': false,
  };

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Google Fit service instance
  final GoogleFitService _googleFitService = GoogleFitService();
  bool _isLoadingSteps = false;

  // App color scheme constants
  static const Color primaryBlue = Color(0xFF6366F1);
  static const Color primaryPurple = Color(0xFF8B5CF6);
  static const Color successGreen = Color(0xFF10B981);
  static const Color lightBackground = Color(0xFFF8F9FA);
  static const Color cardBackground = Colors.white;
  static const Color textPrimary = Color(0xFF232D35);
  static const Color textSecondary = Color(0xFF6B7280);

  /// Setup text field listeners to track user interactions
  void _setupTextFieldListeners() {
    stepsController.addListener(() {
      setState(() {
        sectionTouched['steps'] = stepsController.text.trim().isNotEmpty;
      });
    });
    
    weightController.addListener(() {
      setState(() {
        sectionTouched['weight'] = weightController.text.trim().isNotEmpty;
      });
    });
    
    systolicController.addListener(() {
      setState(() {
        bool hasBPInput = systolicController.text.trim().isNotEmpty || diastolicController.text.trim().isNotEmpty;
        sectionTouched['blood_pressure'] = hasBPInput;
      });
    });
    
    diastolicController.addListener(() {
      setState(() {
        bool hasBPInput = systolicController.text.trim().isNotEmpty || diastolicController.text.trim().isNotEmpty;
        sectionTouched['blood_pressure'] = hasBPInput;
      });
    });
    
    notesController.addListener(() {
      setState(() {
        bool hasMoodInput = notesController.text.trim().isNotEmpty || moodRatings.any((rating) => rating > 0);
        sectionTouched['mood'] = hasMoodInput;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.3, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
    
    // Add listeners to text controllers to track user interaction
    _setupTextFieldListeners();
    
    // Load user goals, existing check-in data, completion status, and synced steps data
    _loadUserGoals();
    _loadExistingCheckInData();
    _loadCompletionStatus();
    _loadSyncedStepsData();
  }

  /// Load user goals from database
  Future<void> _loadUserGoals() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await Supabase.instance.client
          .from('user_goals')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          userGoals = UserGoals(
            steps: double.tryParse(data['steps']?.toString() ?? '') ?? 8000,
            sleep: double.tryParse(data['sleep']?.toString() ?? '') ?? 8,
            weight: double.tryParse(data['weight']?.toString() ?? '') ?? 70,
            bpSystolic: double.tryParse(data['bp_systolic']?.toString() ?? '') ?? 130,
            bpDiastolic: double.tryParse(data['bp_diastolic']?.toString() ?? '') ?? 80,
          );
          _isLoadingGoals = false;
        });
      } else {
        // Set default goals if no data found
        if (mounted) {
          setState(() {
            userGoals = UserGoals(
              steps: 8000,
              sleep: 8,
              weight: 70,
              bpSystolic: 130,
              bpDiastolic: 80,
            );
            _isLoadingGoals = false;
          });
        }
      }
    } catch (e) {
      print('Error loading user goals: $e');
      if (mounted) {
        setState(() {
          // Set default goals on error
          userGoals = UserGoals(
            steps: 8000,
            sleep: 8,
            weight: 70,
            bpSystolic: 130,
            bpDiastolic: 80,
          );
          _isLoadingGoals = false;
        });
      }
    }
  }

  /// Load existing check-in data for today
  Future<void> _loadExistingCheckInData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final today = DateTime.now().toIso8601String().substring(0, 10);

    try {
      // Load health metrics for today
      final healthMetrics = await Supabase.instance.client
          .from('health_metrics')
          .select()
          .eq('user_id', user.id)
          .eq('date', today);

      // Load blood pressure for today
      final bloodPressure = await Supabase.instance.client
          .from('blood_pressure_readings')
          .select()
          .eq('user_id', user.id)
          .eq('date', today)
          .maybeSingle();

      // Load mood entry for today
      final moodEntry = await Supabase.instance.client
          .from('mood_entries')
          .select()
          .eq('user_id', user.id)
          .eq('date', today)
          .maybeSingle();

      if (mounted) {
        setState(() {
          // Pre-populate health metrics
          for (final metric in healthMetrics) {
            final metricType = metric['metric_type'] as String;
            final value = metric['value'];
            
            switch (metricType) {
              case 'steps':
                if (value != null) {
                  stepsController.text = value.toString();
                  sectionTouched['steps'] = true;
                }
                break;
              case 'sleep_hours':
                if (value != null && value > 0) {
                  sleepHours = double.tryParse(value.toString()) ?? 0.0;
                  sectionTouched['sleep'] = true;
                }
                break;
              case 'sleep_quality':
                if (value != null && value > 0) {
                  sleepQuality = int.tryParse(value.toString()) ?? 0;
                  sectionTouched['sleep'] = true;
                }
                break;
              case 'weight':
                if (value != null) {
                  weightController.text = value.toString();
                  sectionTouched['weight'] = true;
                }
                break;
            }
          }

          // Pre-populate blood pressure
          if (bloodPressure != null) {
            if (bloodPressure['systolic'] != null && bloodPressure['systolic'] > 0) {
              systolicController.text = bloodPressure['systolic'].toString();
              sectionTouched['blood_pressure'] = true;
            }
            if (bloodPressure['diastolic'] != null && bloodPressure['diastolic'] > 0) {
              diastolicController.text = bloodPressure['diastolic'].toString();
              sectionTouched['blood_pressure'] = true;
            }
          }

          // Pre-populate mood data
          if (moodEntry != null) {
            if (moodEntry['notes'] != null && moodEntry['notes'].toString().trim().isNotEmpty) {
              notesController.text = moodEntry['notes'] as String;
              sectionTouched['mood'] = true;
            }
            // Convert percentage score back to individual ratings
            // The score is stored as percentage (0-100), convert back to sum of ratings (0-25)
            if (moodEntry['score'] != null && moodEntry['score'] > 0) {
              final percentScore = moodEntry['score'] as int;
              final rawScore = ((percentScore / 100) * 25).round();
              // Distribute the score evenly across the 5 questions (this is an approximation)
              final avgRating = (rawScore / 5).round();
              moodRatings = List.filled(5, avgRating.clamp(0, 5));
              sectionTouched['mood'] = true;
            }
          }
        });
      }
    } catch (e) {
      print('Error loading existing check-in data: $e');
      // Don't show error to user, just continue with empty fields
    }
  }

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

  /// Load completion status and update UI
  Future<void> _loadCompletionStatus() async {
    final status = await _getCompletionStatus();
    if (mounted) {
      setState(() {
        completionStatus = status;
      });
    }
  }

  /// Load today's steps from Google Fit if sync is enabled
  Future<void> _loadSyncedStepsData() async {
    setState(() {
      _isLoadingSteps = true;
    });

    try {
      // Initialize Google Fit service
      await _googleFitService.initialize();

      // Check if sync is enabled
      if (_googleFitService.isSyncEnabled) {
        print('🔵 Google Fit sync is enabled, fetching today\'s steps...');
        
        // Get today's steps from Google Fit
        final todaySteps = await _googleFitService.getTodayStepsFromGoogleFit();
        
        if (todaySteps != null && todaySteps > 0) {
          // Only auto-fill if there's no existing step data
          if (stepsController.text.isEmpty) {
            setState(() {
              stepsController.text = todaySteps.toString();
            });
            print('✅ Loaded ${todaySteps} steps from Google Fit');
          } else {
            print('ℹ️ Existing step data found, skipping Google Fit auto-fill');
          }
        } else {
          print('ℹ️ No step data available from Google Fit for today');
        }
      } else {
        print('ℹ️ Google Fit sync is not enabled');
      }
    } catch (e) {
      print('❌ Error loading Google Fit step data: $e');
      // Don't show error to user, just continue with empty field
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSteps = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    stepsController.dispose();
    weightController.dispose();
    systolicController.dispose();
    diastolicController.dispose();
    notesController.dispose();
    super.dispose();
  }

  void nextStep() {
    setState(() {
      step++;
      _animationController.reset();
      _animationController.forward();
    });
  }

  void previousStep() {
    setState(() {
      if (step > 0) {
        step--;
        _animationController.reset();
        _animationController.forward();
      }
    });
  }

  void saveProgress({bool isComplete = false}) async {
    final user = Supabase.instance.client.auth.currentUser;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    try {
      // Prepare metrics - only save meaningful values
      final metricTypes = ['steps', 'sleep_hours', 'sleep_quality', 'weight'];
      
      for (final metricType in metricTypes) {
        // Always delete existing record first
        await Supabase.instance.client.from('health_metrics').delete().match({
          'user_id': user?.id ?? '',
          'metric_type': metricType,
          'date': today,
        });
        
        // Only insert if there's meaningful data
        dynamic value;
        bool shouldInsert = false;
        
        switch (metricType) {
          case 'steps':
            if (stepsController.text.trim().isNotEmpty) {
              value = int.tryParse(stepsController.text.trim()) ?? 0;
              shouldInsert = value > 0;
            }
            break;
          case 'sleep_hours':
            value = sleepHours;
            shouldInsert = sleepHours > 0 || sleepQuality > 0; // Save if either sleep metric has value
            break;
          case 'sleep_quality':
            value = sleepQuality;
            shouldInsert = sleepHours > 0 || sleepQuality > 0; // Save if either sleep metric has value
            break;
          case 'weight':
            if (weightController.text.trim().isNotEmpty) {
              value = double.tryParse(weightController.text.trim()) ?? 0;
              shouldInsert = value > 0;
            }
            break;
        }
        
        if (shouldInsert) {
          await Supabase.instance.client.from('health_metrics').insert({
            'user_id': user?.id ?? '',
            'metric_type': metricType,
            'value': value,
            'date': today,
          });
        }
      }

      // Save or update blood pressure in blood_pressure_readings
      // Always delete existing record first
      await Supabase.instance.client
          .from('blood_pressure_readings')
          .delete()
          .match({'user_id': user?.id ?? '', 'date': today});
      
      // Only insert new record if both fields have valid values > 0
      if (systolicController.text.trim().isNotEmpty &&
          diastolicController.text.trim().isNotEmpty) {
        final systolic = int.tryParse(systolicController.text.trim()) ?? 0;
        final diastolic = int.tryParse(diastolicController.text.trim()) ?? 0;
        
        if (systolic > 0 && diastolic > 0) {
          await Supabase.instance.client.from('blood_pressure_readings').insert({
            'user_id': user?.id ?? '',
            'systolic': systolic,
            'diastolic': diastolic,
            'date': today,
          });
        }
      }

      // Save or update mood_entries only if user has provided meaningful input
      int rawScore = moodRatings.fold(0, (a, b) => a + b);
      bool hasMoodInput = rawScore > 0 || notesController.text.trim().isNotEmpty;
      
      if (hasMoodInput) {
        int percentScore =
            ((rawScore / 25) * 100).round(); // WHO-5: percent of 25

        await Supabase.instance.client.from('mood_entries').delete().match({
          'user_id': user?.id ?? '',
          'date': today,
        });

        await Supabase.instance.client.from('mood_entries').insert({
          'user_id': user?.id ?? '',
          'score': percentScore,
          'notes': notesController.text,
          'date': today,
        });
      }

      // Refresh completion status after saving
      await _loadCompletionStatus();
      
      if (widget.onComplete != null) {
        widget.onComplete!();
      }
      
      if (isComplete || mounted) {
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isComplete ? "Daily check-in completed!" : "Progress saved!"),
              backgroundColor: isComplete ? successGreen : primaryBlue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        
        // Only close dialog if it's a complete check-in
        if (isComplete && mounted) {
          Navigator.pop(context, true); // signal completion to parent
        }
      }
    } catch (e) {
      // Optionally show error via SnackBar
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error saving check-in: $e")));
      }
    }
  }

  Widget _buildProgressIndicator() {
    final totalSteps = 5;
    final stepNames = ['Sleep', 'Weight', 'BP', 'Steps', 'Mood'];
    final completionKeys = ['sleep', 'weight', 'blood_pressure', 'steps', 'mood'];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(totalSteps, (index) {
              final isCompleted = _isStepCompleted(completionKeys[index]);
              final isCurrent = index == step;
              
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isCompleted 
                            ? const LinearGradient(colors: [successGreen, Color(0xFF059669)])
                            : isCurrent
                                ? const LinearGradient(colors: [primaryBlue, primaryPurple])
                                : null,
                        color: isCompleted || isCurrent ? null : Colors.grey.shade300,
                        border: Border.all(
                          color: isCurrent ? primaryBlue : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: isCompleted 
                            ? const Icon(Icons.check, color: Colors.white, size: 16)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: isCurrent ? Colors.white : textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stepNames[index],
                      style: TextStyle(
                        color: isCompleted ? successGreen : isCurrent ? primaryBlue : textSecondary,
                        fontSize: 10,
                        fontWeight: isCompleted || isCurrent ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            'Step ${step + 1} of $totalSteps',
            style: const TextStyle(
              color: primaryBlue,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          // Completion summary
          Text(
            '${completionKeys.where((key) => _isStepCompleted(key)).length}/5 sections completed',
            style: TextStyle(
              color: textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cardBackground,
        boxShadow: [
          BoxShadow(
            color: textPrimary.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: primaryBlue.withOpacity(0.1), width: 1),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(
            color: primaryBlue,
            fontWeight: FontWeight.w500,
          ),
          hintStyle: TextStyle(color: textSecondary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomSlider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required Function(double) onChanged,
    required String unit,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 20,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: cardBackground,
            boxShadow: [
              BoxShadow(
                color: textPrimary.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: primaryBlue.withOpacity(0.1), width: 1),
          ),
          child: Column(
            children: [
              Text(
                '${value.toStringAsFixed(1)} $unit',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: primaryBlue,
                ),
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: primaryBlue,
                  inactiveTrackColor: Colors.grey.shade300,
                  thumbColor: primaryBlue,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 10,
                  ),
                  overlayColor: primaryBlue.withOpacity(0.2),
                  trackHeight: 5,
                ),
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSleepQualitySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Sleep Quality (0 = very poor, 10 = excellent):",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: primaryBlue,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: List.generate(11, (index) {
            return ChoiceChip(
              label: Text(
                index.toString(),
                style: const TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              selected: sleepQuality == index,
              selectedColor: primaryPurple.withOpacity(0.2),
              backgroundColor: cardBackground,
              side: BorderSide(
                color: sleepQuality == index ? primaryPurple : Colors.grey.shade300,
                width: 1,
              ),
              onSelected: (_) => setState(() {
                sleepQuality = index;
                sectionTouched['sleep'] = (sleepHours > 0 || index > 0);
              }),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildMoodQuestionnaire() {
    final moodStatements = [
      "I have felt cheerful in good spirits.",
      "I have felt calm and relaxed.",
      "I have felt active and vigorous.",
      "I woke up feeling fresh and rested.",
      "My daily life has been filled with things that interest me.",
    ];
    int rawScore = moodRatings.fold(0, (a, b) => a + b);
    double percentScore = rawScore * 4.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(moodStatements.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  moodStatements[index],
                  style: const TextStyle(
                    color: primaryBlue,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: List.generate(6, (ratingIndex) {
                    return ChoiceChip(
                      label: Text(
                        ratingIndex.toString(),
                        style: const TextStyle(
                          fontSize: 11,
                          color: textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      selected: moodRatings[index] == ratingIndex,
                      selectedColor: primaryPurple.withOpacity(0.2),
                      backgroundColor: cardBackground,
                      side: BorderSide(
                        color: moodRatings[index] == ratingIndex ? primaryPurple : Colors.grey.shade300,
                        width: 1,
                      ),
                      shape: const CircleBorder(),
                      labelPadding: const EdgeInsets.all(2),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (bool selected) {
                        setState(() {
                          moodRatings[index] = selected ? ratingIndex : 0;
                          bool hasMoodInput = moodRatings.any((rating) => rating > 0) || notesController.text.trim().isNotEmpty;
                          sectionTouched['mood'] = hasMoodInput;
                        });
                      },
                    );
                  }),
                ),
              ],
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 8),
          child: Text(
            "Score: $rawScore / 25   (${percentScore.round()}%)",
            style: const TextStyle(
              color: primaryBlue,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  /// Check if a specific step is completed
  bool _isStepCompleted(String stepKey) {
    switch (stepKey) {
      case 'sleep':
        return sectionTouched['sleep'] == true && (sleepHours > 0 || sleepQuality > 0);
      case 'weight':
        return weightController.text.trim().isNotEmpty && 
               double.tryParse(weightController.text.trim()) != null &&
               double.tryParse(weightController.text.trim())! > 0;
      case 'blood_pressure':
        return systolicController.text.trim().isNotEmpty && 
               diastolicController.text.trim().isNotEmpty &&
               int.tryParse(systolicController.text.trim()) != null &&
               int.tryParse(diastolicController.text.trim()) != null &&
               int.tryParse(systolicController.text.trim())! > 0 &&
               int.tryParse(diastolicController.text.trim())! > 0;
      case 'steps':
        return stepsController.text.trim().isNotEmpty &&
               int.tryParse(stepsController.text.trim()) != null &&
               int.tryParse(stepsController.text.trim())! > 0;
      case 'mood':
        return (moodRatings.any((rating) => rating > 0) || 
                notesController.text.trim().isNotEmpty);
      default:
        return false;
    }
  }

  /// Check if all sections are completed for current input
  bool _isAllCompleted() {
    // Check current form values for completion
    bool sleepComplete = sectionTouched['sleep'] == true && (sleepHours > 0 || sleepQuality > 0);
    bool weightComplete = weightController.text.trim().isNotEmpty && 
                         double.tryParse(weightController.text.trim()) != null &&
                         double.tryParse(weightController.text.trim())! > 0;
    bool bpComplete = systolicController.text.trim().isNotEmpty && 
                     diastolicController.text.trim().isNotEmpty &&
                     int.tryParse(systolicController.text.trim()) != null &&
                     int.tryParse(diastolicController.text.trim()) != null &&
                     int.tryParse(systolicController.text.trim())! > 0 &&
                     int.tryParse(diastolicController.text.trim())! > 0;
    bool stepsComplete = stepsController.text.trim().isNotEmpty &&
                        int.tryParse(stepsController.text.trim()) != null &&
                        int.tryParse(stepsController.text.trim())! > 0;
    bool moodComplete = (moodRatings.any((rating) => rating > 0) || 
                        notesController.text.trim().isNotEmpty);
    
    return sleepComplete && weightComplete && bpComplete && stepsComplete && moodComplete;
  }

  Widget _buildStepContent() {
    switch (step) {
      case 0:
        return Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.hotel, size: 28, color: primaryBlue),
                    SizedBox(width: 12),
                    Text(
                      "Sleep Duration",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildCustomSlider(
                  value: sleepHours,
                  min: 0,
                  max: 12,
                  divisions: 24,
                  label: 'Sleep Hours',
                  onChanged: (val) => setState(() {
                    sleepHours = val;
                    sectionTouched['sleep'] = (val > 0 || sleepQuality > 0);
                  }),
                  unit: 'hrs',
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: cardBackground,
                    border: Border.all(
                      color: primaryBlue.withOpacity(0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: textPrimary.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flag, color: primaryBlue, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        userGoals?.sleepTarget ?? 'Loading...',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildSleepQualitySelector(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      case 1:
        return Column(
          children: [
            const Row(
              children: [
                Icon(Icons.monitor_weight, size: 32, color: primaryBlue),
                SizedBox(width: 12),
                Text(
                  "Weight",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildCustomTextField(
              controller: weightController,
              label: 'Weight',
              hint: 'What is your weight today?',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: cardBackground,
                border: Border.all(
                  color: primaryBlue.withOpacity(0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: textPrimary.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: primaryBlue, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Record any changes in weight',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case 2:
        return Column(
          children: [
            const Row(
              children: [
                Icon(Icons.favorite, size: 32, color: primaryBlue),
                SizedBox(width: 12),
                Text(
                  "Blood Pressure",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildCustomTextField(
                    controller: systolicController,
                    label: 'Systolic',
                    hint: '120',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [primaryBlue, primaryPurple],
                    ),
                  ),
                  child: const Text(
                    '/',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildCustomTextField(
                    controller: diastolicController,
                    label: 'Diastolic',
                    hint: '80',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: cardBackground,
                border: Border.all(
                  color: primaryBlue.withOpacity(0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: textPrimary.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag, color: primaryBlue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    userGoals?.bpTarget ?? 'Loading...',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case 3:
        return Column(
          children: [
            Row(
              children: [
                const Icon(Icons.directions_walk, size: 32, color: primaryBlue),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "Today's Steps",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ),
                if (_isLoadingSteps) ...[
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryBlue,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            _buildCustomTextField(
              controller: stepsController,
              label: 'Steps',
              hint: _isLoadingSteps 
                  ? 'Loading from Google Fit...' 
                  : 'How many steps did you take today?',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            // Show sync confirmation if Google Fit data was loaded
            if (stepsController.text.isNotEmpty && _googleFitService.isSyncEnabled && !_isLoadingSteps) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: successGreen.withOpacity(0.1),
                  border: Border.all(
                    color: successGreen.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sync, color: successGreen, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Auto-filled from Google Fit',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: successGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: cardBackground,
                border: Border.all(
                  color: primaryBlue.withOpacity(0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: textPrimary.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag, color: primaryBlue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    userGoals?.stepTarget ?? 'Loading...',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
            // Show Google Fit sync reminder if not enabled
            if (!_googleFitService.isSyncEnabled && !_isLoadingSteps) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: textSecondary.withOpacity(0.1),
                  border: Border.all(
                    color: textSecondary.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: textSecondary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Enable Google Fit sync in Profile to auto-fill step data',
                        style: TextStyle(
                          fontSize: 13,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      case 4:
        // Mood questionnaire with notes combined
        return Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.mood,
                    size: 28,
                    color: primaryBlue,
                  ),
                  SizedBox(width: 12),
                  Text(
                    "Mood & Notes",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // WHO-5 Mood questionnaire
                      const Text(
                        "WHO-5 Well-Being Index:",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildMoodQuestionnaire(),
                      const SizedBox(height: 20),
                      // Notes section
                      const Text(
                        "Daily Notes:",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: cardBackground,
                          boxShadow: [
                            BoxShadow(
                              color: textPrimary.withOpacity(0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                          border: Border.all(color: primaryBlue.withOpacity(0.1), width: 1),
                        ),
                        child: TextField(
                          controller: notesController,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Write any notes for today...',
                            hintStyle: TextStyle(color: textSecondary),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      default:
        return Container();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        constraints: const BoxConstraints(
          maxHeight: 650,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: cardBackground,
          boxShadow: [
            BoxShadow(
              color: textPrimary.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildProgressIndicator(),
              Flexible(
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: _buildStepContent(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Column(
                children: [
                  // Navigation row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (step > 0)
                        TextButton.icon(
                          onPressed: previousStep,
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Back'),
                          style: TextButton.styleFrom(
                            foregroundColor: textSecondary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        )
                      else
                        const SizedBox(),
                      if (step < 4)
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [primaryBlue, primaryPurple],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: primaryBlue.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: nextStep,
                            icon: const Icon(Icons.arrow_forward, size: 18),
                            label: const Text('Next'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Action buttons row
                  Row(
                    children: [
                      // Save Progress button
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [primaryBlue.withOpacity(0.1), primaryPurple.withOpacity(0.1)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: primaryBlue.withOpacity(0.3)),
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () => saveProgress(isComplete: false),
                            icon: const Icon(Icons.save, size: 18),
                            label: const Text('Save Progress'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: primaryBlue,
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Complete button (only if all sections are done)
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isAllCompleted() 
                                  ? [successGreen, primaryBlue]
                                  : [Colors.grey.shade300, Colors.grey.shade400],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: _isAllCompleted() ? [
                              BoxShadow(
                                color: successGreen.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ] : [],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _isAllCompleted() ? () => saveProgress(isComplete: true) : null,
                            icon: const Icon(Icons.check_circle, size: 18),
                            label: const Text('Complete'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: _isAllCompleted() ? Colors.white : Colors.grey.shade600,
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

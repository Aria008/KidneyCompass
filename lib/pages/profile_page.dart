import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/google_fit_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final TextEditingController stepsController = TextEditingController();
  final TextEditingController sleepController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  final TextEditingController systolicController = TextEditingController();
  final TextEditingController diastolicController = TextEditingController();

  // --- Log-frequency state ---
  int _logFrequency = 3;
  final List<String> _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  final Set<String> _selectedDays = {'Mon', 'Wed', 'Fri'};

  // Google Fit sync state
  bool _googleFitSyncEnabled = false;
  bool _googleFitSyncLoading = false;
  final GoogleFitService _googleFitService = GoogleFitService();

  // CKD Stage state
  int? _currentCkdStage;

  // CKD stage-specific recommendations (same as register page)
  final Map<String, Map<String, String>> _ckdRecommendations = {
    'Stage 1': {
      'steps': 'Recommended: 8,000 – 10,000 steps',
      'sleep': 'Recommended: 7–9 hours',
      'bp': 'Target: below 130/80 mmHg',
    },
    'Stage 2': {
      'steps': 'Recommended: 6,000 – 8,000 steps',
      'sleep': 'Recommended: 7–9 hours',
      'bp': 'Target: below 130/80 mmHg',
    },
    'Stage 3': {
      'steps': 'Recommended: 5,000 – 7,000 steps',
      'sleep': 'Recommended: 7–8 hours',
      'bp': 'Target: below 125/75 mmHg',
    },
    'Stage 4': {
      'steps': 'Recommended: 3,000 – 5,000 steps',
      'sleep': 'Recommended: 7–8 hours',
      'bp': 'Target: below 120/70 mmHg',
    },
    'Stage 5': {
      'steps': 'Recommended: 2,000 – 4,000 steps',
      'sleep': 'Recommended: 7–8 hours',
      'bp': 'Target: below 120/70 mmHg',
    },
  };

  // Helper method to get current CKD stage as string for recommendations lookup
  String _getCurrentCkdStageString() {
    return 'Stage ${_currentCkdStage ?? 1}';
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
    _loadUserGoals();
    _loadLogDays();
    _loadCkdStage();
    _checkGoogleFitSyncStatus();
  }

  Future<void> _checkGoogleFitSyncStatus() async {
    await _googleFitService.initialize();
    setState(() {
      _googleFitSyncEnabled = _googleFitService.isSyncEnabled;
    });
  }

  Future<void> _toggleGoogleFitSync() async {
    if (_googleFitSyncLoading) return;

    setState(() {
      _googleFitSyncLoading = true;
    });

    try {
      if (!_googleFitSyncEnabled) {
        // Enable Google Fit sync
        final hasPermission = await _googleFitService.requestPermissions();

        if (hasPermission) {
          setState(() {
            _googleFitSyncEnabled = true;
          });

          // Try to sync today's steps immediately
          await _syncTodaySteps();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Google Fit sync enabled! Steps will be synced automatically.',
              ),
              backgroundColor: Color(0xFF87A164),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Google Fit permissions required for step syncing.',
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // Disable Google Fit sync
        await _googleFitService.disableSync();

        setState(() {
          _googleFitSyncEnabled = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Google Fit sync disabled. You can still enter steps manually.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        _googleFitSyncLoading = false;
      });
    }
  }

  Future<void> _syncTodaySteps() async {
    if (!_googleFitSyncEnabled) return;

    try {
      final success = await _googleFitService.syncTodaySteps();

      if (success) {
        final todaySteps = await _googleFitService.getTodayStepsFromGoogleFit();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced ${todaySteps ?? 0} steps from ${_googleFitService.getPlatformName()}',
            ),
            backgroundColor: const Color(0xFF87A164),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to sync steps from Google Fit'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('Error syncing steps: $e');
    }
  }

  void _showHealthGoalsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFF6366F1),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Edit Health Goals',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                // Scrollable content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildGoalCardWithoutSave(
                          icon: Icons.directions_walk,
                          label: 'Daily Steps',
                          controller: stepsController,
                          accentColor: const Color(0xFF3B82F6),
                          unit: 'steps',
                          recommendationKey: 'steps',
                        ),
                        _buildGoalCardWithoutSave(
                          icon: Icons.bedtime,
                          label: 'Sleep Target',
                          controller: sleepController,
                          accentColor: const Color(0xFF8B5CF6),
                          unit: 'hours',
                          recommendationKey: 'sleep',
                        ),
                        _buildGoalCardWithoutSave(
                          icon: Icons.monitor_weight,
                          label: 'Weight Target',
                          controller: weightController,
                          accentColor: const Color(0xFF10B981),
                          unit: 'kg',
                          note:
                              'Consult your doctor for personalized weight targets',
                        ),
                        _buildBloodPressureCardWithoutSave(),
                      ],
                    ),
                  ),
                ),
                // Save button at bottom
                Container(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _saveAllGoals(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save All Goals',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCkdStageDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        int selectedStage = _currentCkdStage ?? 1;

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: StatefulBuilder(
            builder:
                (ctx, setModal) => Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.health_and_safety,
                              color: Color(0xFF10B981),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              'Update CKD Stage',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Current stage display
                      const Text(
                        'Current Stage:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF10B981).withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          'CKD Stage ${_currentCkdStage ?? 'Unknown'}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Stage selector
                      const Text(
                        'Select New Stage:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: selectedStage,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down),
                            items: List.generate(5, (index) {
                              final stage = index + 1;
                              return DropdownMenuItem<int>(
                                value: stage,
                                child: Text(
                                  'Stage $stage',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }),
                            onChanged: (value) {
                              if (value != null) {
                                setModal(() {
                                  selectedStage = value;
                                });
                              }
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Warning message
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange.shade600,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Important Notice',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Changing your CKD stage will update the recommended values for your health goals. You may want to review and adjust your goals after this change.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.orange.shade700,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                await _updateCkdStage(selectedStage);
                                Navigator.of(ctx).pop();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Update Stage',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
          ),
        );
      },
    );
  }

  void _showLogDaysDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: StatefulBuilder(
            builder:
                (ctx, setModal) => Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Edit Logging Schedule',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButton<int>(
                        key: ValueKey(_logFrequency),
                        value: _logFrequency,
                        items: List.generate(
                          7,
                          (i) => DropdownMenuItem<int>(
                            key: ValueKey('freq_${i + 1}'),
                            value: i + 1,
                            child: Text(
                              '${i + 1} time${i == 0 ? '' : 's'} / week',
                            ),
                          ),
                        ),
                        onChanged: (v) {
                          if (v == null) return;
                          setModal(() {
                            _logFrequency = v;
                            while (_selectedDays.length > v) {
                              _selectedDays.remove(_selectedDays.last);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children:
                            _weekdays.map((d) {
                              final sel = _selectedDays.contains(d);
                              final disabled =
                                  _selectedDays.length >= _logFrequency && !sel;
                              return ChoiceChip(
                                label: Text(d),
                                selected: sel,
                                onSelected:
                                    disabled
                                        ? null
                                        : (val) {
                                          setModal(() {
                                            val
                                                ? _selectedDays.add(d)
                                                : _selectedDays.remove(d);
                                          });
                                        },
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          if (_selectedDays.length != _logFrequency) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Select exact number of days'),
                              ),
                            );
                            return;
                          }
                          final user =
                              Supabase.instance.client.auth.currentUser;
                          if (user != null) {
                            final rows =
                                _selectedDays
                                    .map(
                                      (d) => {'user_id': user.id, 'weekday': d},
                                    )
                                    .toList();
                            await Supabase.instance.client
                                .from('user_log_days')
                                .delete()
                                .eq('user_id', user.id);
                            await Supabase.instance.client
                                .from('user_log_days')
                                .upsert(rows);
                          }
                          Navigator.of(ctx).pop();
                          await _loadLogDays();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Logging schedule saved!'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
        );
      },
    );
  }

  Future<void> _loadUserGoals() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final data =
        await Supabase.instance.client
            .from('user_goals')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();
    if (data != null) {
      stepsController.text = (data['steps'] ?? '').toString();
      sleepController.text = (data['sleep'] ?? '').toString();
      weightController.text = (data['weight'] ?? '').toString();
      systolicController.text = (data['bp_systolic'] ?? '').toString();
      diastolicController.text = (data['bp_diastolic'] ?? '').toString();
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
      _selectedDays
        ..clear()
        ..addAll(rows.map((e) => e['weekday'].toString()));
      // Ensure _logFrequency is always between 1 and 7
      _logFrequency = _selectedDays.length == 0 ? 3 : _selectedDays.length;
      _logFrequency = _logFrequency.clamp(1, 7);
    });
  }

  Future<void> _saveUserGoal({
    required String field,
    required dynamic value,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await Supabase.instance.client.from('user_goals').upsert({
      'user_id': user.id,
      field: value,
    }, onConflict: 'user_id');
  }

  Future<void> _loadCkdStage() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final profile =
          await Supabase.instance.client
              .from('profiles')
              .select('stage')
              .eq('id', user.id)
              .maybeSingle();

      if (profile != null && mounted) {
        setState(() {
          _currentCkdStage = profile['stage'] as int?;
        });
      }
    } catch (e) {
      print('Error loading CKD stage: $e');
    }
  }

  Future<void> _updateCkdStage(int newStage) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'stage': newStage})
          .eq('id', user.id);

      if (mounted) {
        setState(() {
          _currentCkdStage = newStage;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CKD Stage updated to Stage $newStage'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating CKD stage: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _exportHealthData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Use a local variable to track dialog
    bool isDialogShowing = false;

    try {
      // Show loading indicator
      isDialogShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (dialogContext) => const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF6366F1),
                        ),
                      ),
                      SizedBox(height: 16),
                      Text('Generating PDF...'),
                    ],
                  ),
                ),
              ),
            ),
      );

      // Fetch distinct dates from health_metrics (last 14 dates with data)
      final healthDatesResponse = await Supabase.instance.client
          .from('health_metrics')
          .select('date')
          .eq('user_id', user.id)
          .order('date', ascending: false);

      // Get unique dates
      final uniqueDates = <String>{};
      for (var entry in healthDatesResponse) {
        uniqueDates.add(entry['date']);
        if (uniqueDates.length >= 14) break;
      }

      // Fetch all health metrics for these dates
      final healthMetricsData = await Supabase.instance.client
          .from('health_metrics')
          .select()
          .eq('user_id', user.id)
          .inFilter('date', uniqueDates.toList())
          .order('date', ascending: false);

      // Fetch blood pressure readings for these dates
      final bpData = await Supabase.instance.client
          .from('blood_pressure_readings')
          .select()
          .eq('user_id', user.id)
          .inFilter('date', uniqueDates.toList())
          .order('date', ascending: false);

      // Fetch mood entries for these dates
      final moodData = await Supabase.instance.client
          .from('mood_entries')
          .select()
          .eq('user_id', user.id)
          .inFilter('date', uniqueDates.toList())
          .order('date', ascending: false);

      // Organize health metrics by date and metric type
      final Map<String, Map<String, dynamic>> organizedHealthData = {};
      for (var metric in healthMetricsData) {
        final date = metric['date'];
        if (date != null) {
          if (!organizedHealthData.containsKey(date)) {
            organizedHealthData[date] = {'date': date};
          }
          final metricType = metric['metric_type'];
          if (metricType != null) {
            organizedHealthData[date]![metricType] = metric['value'];
          }
        }
      }

      // Add BP data to organized data
      for (var bp in bpData) {
        final date = bp['date'];
        if (date != null) {
          if (!organizedHealthData.containsKey(date)) {
            organizedHealthData[date] = {'date': date};
          }
          organizedHealthData[date]!['bp_systolic'] = bp['systolic'];
          organizedHealthData[date]!['bp_diastolic'] = bp['diastolic'];
        }
      }

      // Convert to list and sort by date
      final healthData =
          organizedHealthData.values.toList()
            ..sort((a, b) => b['date'].compareTo(a['date']));

      // Get user profile for name and CKD stage
      final profile =
          await Supabase.instance.client
              .from('profiles')
              .select()
              .eq('id', user.id)
              .maybeSingle();

      // Check if there's any data to export
      if (healthMetricsData.isEmpty && bpData.isEmpty && moodData.isEmpty) {
        if (isDialogShowing && mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          isDialogShowing = false;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No data available to export'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Determine date range
      String dateRange = 'No data available';
      final allDates = <DateTime>[];

      for (var entry in healthMetricsData) {
        if (entry['date'] != null) {
          allDates.add(DateTime.parse(entry['date']));
        }
      }
      for (var entry in bpData) {
        if (entry['date'] != null) {
          allDates.add(DateTime.parse(entry['date']));
        }
      }
      for (var entry in moodData) {
        if (entry['date'] != null) {
          allDates.add(DateTime.parse(entry['date']));
        }
      }

      if (allDates.isNotEmpty) {
        allDates.sort();
        final startDate = allDates.first;
        final endDate = allDates.last;
        dateRange = '${_formatDate(startDate)} - ${_formatDate(endDate)}';
      }

      // Generate PDF
      final pdf = pw.Document();

      // ---- Quick stats (averages over the pulled entries) ----
      double? _toDouble(dynamic v) {
        if (v == null) return null;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString());
      }

      double? _avg(Iterable<double?> values) {
        final list = values.whereType<double>().toList();
        if (list.isEmpty) return null;
        final s = list.reduce((a, b) => a + b);
        return s / list.length;
      }

      final stepsVals = healthMetricsData
          .where((e) => e['metric_type'] == 'steps')
          .map((e) => _toDouble(e['value']));
      final sleepVals = healthMetricsData
          .where((e) => e['metric_type'] == 'sleep_hours')
          .map((e) => _toDouble(e['value']));
      final weightVals = healthMetricsData
          .where((e) => e['metric_type'] == 'weight')
          .map((e) => _toDouble(e['value']));
      final bpSysVals = bpData.map((e) => _toDouble(e['systolic']));
      final bpDiaVals = bpData.map((e) => _toDouble(e['diastolic']));
      final moodVals = moodData.map((e) => _toDouble(e['score']));

      final stepsAvg = _avg(stepsVals);
      final sleepAvg = _avg(sleepVals);
      final weightAvg = _avg(weightVals);
      final bpSysAvg = _avg(bpSysVals);
      final bpDiaAvg = _avg(bpDiaVals);
      final moodAvg = _avg(moodVals);

      final accent = PdfColors.indigo600;
      final headerBg = PdfColors.grey100;
      final tableHeader = PdfColors.grey800;

      // --- Helpers for KPI row (declared BEFORE use) ---
      pw.Widget _divider() => pw.Container(
        width: 1,
        height: 28,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10),
        color: PdfColors.grey300,
      );

      pw.Widget _kpi(String label, String value) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ],
        ),
      );

      pdf.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 28),
          pageFormat: PdfPageFormat.a4,
          footer:
              (context) => pw.Container(
                alignment: pw.Alignment.centerRight,
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
          build:
              (pw.Context context) => [
                // ===== Header =====
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: headerBg,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'KidneyCompass Health Report',
                              style: pw.TextStyle(
                                fontSize: 20,
                                fontWeight: pw.FontWeight.bold,
                                color: accent,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                            pw.Text(
                              'Patient: ${profile?['name'] ?? 'Unknown'}',
                              style: const pw.TextStyle(
                                fontSize: 12,
                                color: PdfColors.grey800,
                              ),
                            ),
                            pw.Text(
                              'CKD Stage: ${profile?['stage'] ?? 'Unknown'}',
                              style: const pw.TextStyle(
                                fontSize: 12,
                                color: PdfColors.grey800,
                              ),
                            ),
                            pw.Text(
                              'Date Range: $dateRange',
                              style: const pw.TextStyle(
                                fontSize: 12,
                                color: PdfColors.grey800,
                              ),
                            ),
                            pw.Text(
                              'Generated: ${_formatDate(DateTime.now())}',
                              style: const pw.TextStyle(
                                fontSize: 12,
                                color: PdfColors.grey800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 16),

                // ===== Overview (compact KPI row) =====
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    children: [
                      _kpi(
                        'Avg Steps',
                        stepsAvg == null ? '-' : stepsAvg!.toStringAsFixed(0),
                      ),
                      _divider(),
                      _kpi(
                        'Avg Sleep (hr/s)',
                        sleepAvg == null ? '-' : sleepAvg!.toStringAsFixed(1),
                      ),
                      _divider(),
                      _kpi(
                        'Avg Weight (kg)',
                        weightAvg == null ? '-' : weightAvg!.toStringAsFixed(1),
                      ),
                      _divider(),
                      _kpi(
                        'Avg BP',
                        (bpSysAvg == null || bpDiaAvg == null)
                            ? '-'
                            : '${bpSysAvg!.toStringAsFixed(0)}/${bpDiaAvg!.toStringAsFixed(0)}',
                      ),
                      _divider(),
                      _kpi(
                        'Avg Mood (%)',
                        moodAvg == null ? '-' : moodAvg!.toStringAsFixed(0),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 16),

                // ===== Health Metrics Table =====
                if (healthData.isNotEmpty) ...[
                  pw.Text(
                    'Health Metrics (Last ${healthData.length} entries by date)',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: tableHeader,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Table.fromTextArray(
                    headers: const [
                      'Date',
                      'Steps',
                      'Sleep (hr/s)',
                      'Weight (kg)',
                      'BP',
                    ],
                    data:
                        healthData.map((entry) {
                          final date =
                              entry['date'] != null
                                  ? _formatDate(DateTime.parse(entry['date']))
                                  : 'N/A';
                          final steps = entry['steps']?.toString() ?? '-';
                          final sleep = entry['sleep_hours']?.toString() ?? '-';
                          final weight = entry['weight']?.toString() ?? '-';
                          final bp =
                              (entry['bp_systolic'] != null &&
                                      entry['bp_diastolic'] != null)
                                  ? '${entry['bp_systolic']}/${entry['bp_diastolic']}'
                                  : '-';
                          return [date, steps, sleep, weight, bp];
                        }).toList(),
                    headerStyle: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.indigo700,
                    ),
                    cellHeight: 20,
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerRight,
                      2: pw.Alignment.centerRight,
                      3: pw.Alignment.centerRight,
                      4: pw.Alignment.center,
                    },
                    oddRowDecoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                    ),
                    border: pw.TableBorder.all(
                      color: PdfColors.grey300,
                      width: 0.5,
                    ),
                  ),
                  pw.SizedBox(height: 16),
                ],

                // ===== Mood Table =====
                if (moodData.isNotEmpty) ...[
                  pw.Text(
                    'Mood Entries (Last ${moodData.length} entries)',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: tableHeader,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Table.fromTextArray(
                    headers: const ['Date', 'Score (%)', 'Notes'],
                    data:
                        moodData.map((entry) {
                          final date =
                              entry['date'] != null
                                  ? _formatDate(DateTime.parse(entry['date']))
                                  : 'N/A';
                          final score = entry['score']?.toString() ?? '-';
                          final notes = entry['notes']?.toString() ?? '';
                          return [date, score, notes];
                        }).toList(),
                    headerStyle: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.indigo700,
                    ),
                    cellHeight: 20,
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerRight,
                      2: pw.Alignment.centerLeft,
                    },
                    oddRowDecoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                    ),
                    border: pw.TableBorder.all(
                      color: PdfColors.grey300,
                      width: 0.5,
                    ),
                  ),
                ],

                // ===== Footer Note =====
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(
                    'This report summarizes the last 14 available entries. Share with your healthcare provider for ongoing care.',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
              ],
        ),
      );

      // Generate PDF bytes
      final pdfBytes = await pdf.save();

      // Close loading dialog
      if (isDialogShowing && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        isDialogShowing = false;
      }

      // Small delay to ensure dialog is closed
      await Future.delayed(const Duration(milliseconds: 100));

      // Save to Downloads folder
      if (mounted) {
        String? directoryPath;

        if (Platform.isAndroid) {
          // For Android, save to Downloads folder
          directoryPath = '/storage/emulated/0/Download';

          // Fallback to external storage directory if Downloads not accessible
          final directory = Directory(directoryPath);
          if (!await directory.exists()) {
            final externalDir = await getExternalStorageDirectory();
            directoryPath = externalDir?.path;
          }
        } else {
          // For other platforms
          final directory = await getApplicationDocumentsDirectory();
          directoryPath = directory.path;
        }

        if (directoryPath != null) {
          final fileName =
              'health_data_${DateTime.now().millisecondsSinceEpoch}.pdf';
          final filePath = '$directoryPath/$fileName';
          final file = File(filePath);

          await file.writeAsBytes(pdfBytes);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF saved to Downloads: $fileName'),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Open',
                textColor: Colors.white,
                onPressed: () async {
                  await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('Export error: $e');

      // Close loading dialog if still showing
      if (isDialogShowing && mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (navError) {
          print('Error closing dialog: $navError');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting data: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  void dispose() {
    _animationController.dispose();
    stepsController.dispose();
    sleepController.dispose();
    weightController.dispose();
    systolicController.dispose();
    diastolicController.dispose();
    super.dispose();
  }

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    context.go('/login');
  }

  Widget _buildGoalCard({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required Color accentColor,
    String? note,
    String? unit,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      suffixText: unit,
                      suffixStyle: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: accentColor,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await _saveUserGoal(
                      field:
                          label == 'Daily Steps'
                              ? 'steps'
                              : label == 'Sleep Target'
                              ? 'sleep'
                              : label == 'Weight Target'
                              ? 'weight'
                              : '',
                      value: int.tryParse(controller.text) ?? 0,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$label goal saved!'),
                        backgroundColor: accentColor,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                note,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGoalCardWithoutSave({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required Color accentColor,
    String? note,
    String? unit,
    String? recommendationKey,
  }) {
    // Get CKD stage-specific recommendation if recommendationKey is provided
    String? stageSpecificNote = note;
    if (recommendationKey != null &&
        _ckdRecommendations.containsKey(_getCurrentCkdStageString())) {
      stageSpecificNote =
          _ckdRecommendations[_getCurrentCkdStageString()]![recommendationKey];
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                suffixText: unit,
                suffixStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ),
          ),
          if (stageSpecificNote != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                stageSpecificNote,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBloodPressureCardWithoutSave() {
    const accentColor = Color(0xFFE91E63);

    // Get CKD stage-specific BP recommendation
    String bpNote = 'Target: below 130/80 mmHg'; // default
    if (_ckdRecommendations.containsKey(_getCurrentCkdStageString())) {
      bpNote = _ckdRecommendations[_getCurrentCkdStageString()]!['bp']!;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.favorite, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Blood Pressure Target',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextField(
                    controller: systolicController,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      hintText: 'Systolic',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '/',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextField(
                    controller: diastolicController,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      hintText: 'Diastolic',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              bpNote,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBloodPressureCard() {
    const accentColor = Color(0xFFE91E63);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.favorite, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Blood Pressure Target',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextField(
                    controller: systolicController,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      hintText: 'Systolic',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '/',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: TextField(
                    controller: diastolicController,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      hintText: 'Diastolic',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: accentColor,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await _saveUserGoal(
                      field: 'bp_systolic',
                      value: int.tryParse(systolicController.text) ?? 0,
                    );
                    await _saveUserGoal(
                      field: 'bp_diastolic',
                      value: int.tryParse(diastolicController.text) ?? 0,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Blood pressure target saved!'),
                        backgroundColor: accentColor,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Target for CKD: Below 130/80 mmHg',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAllGoals(BuildContext context) async {
    // Validation
    List<String> errors = [];

    final steps = int.tryParse(stepsController.text.trim());
    final sleep = int.tryParse(sleepController.text.trim());
    final weight = double.tryParse(weightController.text.trim());
    final systolic = int.tryParse(systolicController.text.trim());
    final diastolic = int.tryParse(diastolicController.text.trim());
    if (steps == null || steps <= 0) {
      errors.add('Daily Steps must be a valid number greater than 0');
    }

    if (sleep == null || sleep <= 0) {
      errors.add('Sleep Target must be a valid number greater than 0');
    }

    if (weight == null || weight <= 0) {
      errors.add('Weight Target must be a valid number greater than 0');
    }

    if (systolic == null || systolic <= 0) {
      errors.add(
        'Systolic blood pressure must be a valid number greater than 0',
      );
    }

    if (diastolic == null || diastolic <= 0) {
      errors.add(
        'Diastolic blood pressure must be a valid number greater than 0',
      );
    }

    // Show errors if any
    if (errors.isNotEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text(
              'Invalid Input',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please fix the following errors:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                ...errors.map(
                  (error) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: Colors.red)),
                        Expanded(
                          child: Text(
                            error,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      );
      return;
    }

    // If validation passes, save the goals
    try {
      await _saveUserGoal(field: 'steps', value: steps);
      await _saveUserGoal(field: 'sleep', value: sleep);
      await _saveUserGoal(field: 'weight', value: weight);
      await _saveUserGoal(field: 'bp_systolic', value: systolic);
      await _saveUserGoal(field: 'bp_diastolic', value: diastolic);

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All health goals saved successfully!'),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error saving goals. Please try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<Map<String, int>> _fetchStreaksAndCheckins() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return {'currentStreak': 0, 'bestStreak': 0, 'totalCheckins': 0};
    }

    // Fetch all dates from mood_entries
    final moodDatesResponse = await Supabase.instance.client
        .from('mood_entries')
        .select('date')
        .eq('user_id', user.id);

    // Fetch all dates from health_metrics
    final healthDatesResponse = await Supabase.instance.client
        .from('health_metrics')
        .select('date')
        .eq('user_id', user.id);

    // Merge all dates into a Set (removes duplicates), convert to LOCAL date only
    final Set<DateTime> allDates = {};

    for (var entry in moodDatesResponse) {
      final dateStr = entry['date'];
      if (dateStr != null) {
        final d = DateTime.parse(dateStr).toLocal();
        allDates.add(DateTime(d.year, d.month, d.day));
      }
    }

    for (var entry in healthDatesResponse) {
      final dateStr = entry['date'];
      if (dateStr != null) {
        final d = DateTime.parse(dateStr).toLocal();
        allDates.add(DateTime(d.year, d.month, d.day));
      }
    }

    if (allDates.isEmpty) {
      return {'currentStreak': 0, 'bestStreak': 0, 'totalCheckins': 0};
    }

    final sortedDates = allDates.toList()..sort();

    // Remove duplicates just in case
    final uniqueDates = <DateTime>[];
    for (final d in sortedDates) {
      if (uniqueDates.isEmpty || uniqueDates.last != d) uniqueDates.add(d);
    }

    // Calculate streaks
    int bestStreak = 1;
    int tempStreak = 1;
    for (int i = 1; i < uniqueDates.length; i++) {
      final prev = uniqueDates[i - 1];
      final curr = uniqueDates[i];
      if (curr.difference(prev).inDays == 1) {
        tempStreak++;
        if (tempStreak > bestStreak) bestStreak = tempStreak;
      } else {
        tempStreak = 1;
      }
    }
    bestStreak = bestStreak > tempStreak ? bestStreak : tempStreak;

    // Current streak: consecutive days up to today (in local time)
    final today = DateTime.now();
    int streak = 0;
    for (int i = uniqueDates.length - 1; i >= 0; i--) {
      final d = uniqueDates[i];
      final diff = today.difference(d).inDays;
      if (diff == 0 || (diff == streak)) {
        streak++;
      } else if (diff > streak) {
        break;
      }
    }
    int currentStreak = streak;

    return {
      'currentStreak': currentStreak,
      'bestStreak': bestStreak,
      'totalCheckins': uniqueDates.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return FutureBuilder(
      future:
          Supabase.instance.client
              .from('profiles')
              .select()
              .eq('id', user!.id)
              .maybeSingle(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
          );
        }

        final profile = snapshot.data;

        return Scaffold(
          backgroundColor: const Color(0xFFFAFAFA),
          body: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 120,
                    floating: false,
                    pinned: true,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      title: const Text(
                        'My Profile',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      background: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Profile Header
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF6366F1),
                                        Color(0xFF8B5CF6),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        profile?['name'] ?? 'Unknown',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          onTap: _showCkdStageDialog,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFF10B981,
                                              ).withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: const Color(
                                                  0xFF10B981,
                                                ).withOpacity(0.3),
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'CKD Stage ${_currentCkdStage ?? profile?['stage'] ?? 'Unknown'}',
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: Color(0xFF10B981),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                const Icon(
                                                  Icons.edit,
                                                  size: 14,
                                                  color: Color(0xFF10B981),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Material(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _signOut(context),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      child: Icon(
                                        Icons.logout,
                                        color: Colors.red[600],
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Achievements Section
                          const Text(
                            '🏆 Achievements',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FutureBuilder<Map<String, int>>(
                            future: _fetchStreaksAndCheckins(),
                            builder: (context, streakSnapshot) {
                              final data = streakSnapshot.data;
                              final loading = !streakSnapshot.hasData;
                              return Row(
                                children: [
                                  _buildAchievementCard(
                                    'Current Streak',
                                    loading
                                        ? '...'
                                        : '${data?['currentStreak'] ?? 0} days',
                                    Icons.local_fire_department,
                                    const Color(0xFFFF6B35),
                                  ),
                                  const SizedBox(width: 12),
                                  _buildAchievementCard(
                                    'Best Streak',
                                    loading
                                        ? '...'
                                        : '${data?['bestStreak'] ?? 0} days',
                                    Icons.emoji_events,
                                    const Color(0xFFFFD700),
                                  ),
                                  const SizedBox(width: 12),
                                  _buildAchievementCard(
                                    'Total Check-ins',
                                    loading
                                        ? '...'
                                        : '${data?['totalCheckins'] ?? 0}',
                                    Icons.check_circle,
                                    const Color(0xFF10B981),
                                  ),
                                ],
                              );
                            },
                          ),

                          const SizedBox(height: 32),

                          // Health Sync Section
                          const Text(
                            'Health Sync',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF87A164,
                                          ).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.sync,
                                          color: Color(0xFF87A164),
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Sync Steps from Google Fit',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _googleFitSyncEnabled
                                                  ? 'Steps will automatically sync from Google Fit'
                                                  : 'Enable to sync steps from Google Fit',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Switch(
                                        value: _googleFitSyncEnabled,
                                        onChanged:
                                            _googleFitSyncLoading
                                                ? null
                                                : (_) => _toggleGoogleFitSync(),
                                        activeColor: const Color(0xFF87A164),
                                      ),
                                    ],
                                  ),
                                  if (_googleFitSyncEnabled) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF87A164,
                                        ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(
                                            0xFF87A164,
                                          ).withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.info_outline,
                                            color: Color(0xFF87A164),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Sync Today\'s Steps',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF87A164),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Manually sync your current step count',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          ElevatedButton(
                                            onPressed:
                                                _googleFitSyncLoading
                                                    ? null
                                                    : _syncTodaySteps,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFF87A164,
                                              ),
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            child:
                                                _googleFitSyncLoading
                                                    ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.white,
                                                          ),
                                                    )
                                                    : const Text(
                                                      'Sync Now',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Health Goals Section
                          // Health Goals Section
                          const Text(
                            'Health Goals',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _showHealthGoalsDialog,
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.edit,
                                        color: Color(0xFF6366F1),
                                        size: 24,
                                      ),
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          'Edit Health Goals',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        color: Colors.grey,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Logging Schedule
                          const SizedBox(height: 24),
                          const Text(
                            'Logging Schedule',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _showLogDaysDialog,
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.event_repeat,
                                        color: Color(0xFF3B82F6),
                                        size: 24,
                                      ),
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          'Edit Log Schedule',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        color: Colors.grey,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Data Options
                          const Text(
                            'Data Options',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: _exportHealthData,
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        child: const Column(
                                          children: [
                                            Icon(
                                              Icons.download,
                                              color: Color(0xFF6366F1),
                                              size: 24,
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              'Export Data',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {},
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        child: const Column(
                                          children: [
                                            Icon(
                                              Icons.share,
                                              color: Color(0xFF10B981),
                                              size: 24,
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              'Share with Doctor',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

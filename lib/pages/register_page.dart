import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();

  // ─── 1. Controllers (place at top of State class) ────────────────────────────
  final stepsController = TextEditingController();
  final sleepController = TextEditingController();
  final weightGoalController =
      TextEditingController(); // Renamed to avoid conflict
  final systolicController = TextEditingController();
  final diastolicController = TextEditingController();

  String _ckdStage = 'Stage 1';
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  // --- Logging schedule ---
  int _logFrequency = 3; // default 3 times per week
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

  // CKD stage-specific recommendations
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

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDays.length != _logFrequency) {
      setState(
        () =>
            _error = 'Please select exactly $_logFrequency day(s) for logging.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (response.user == null) {
        setState(() => _error = 'Registration failed. Please try again.');
      } else {
        final user = response.user;
        if (user != null) {
          await Supabase.instance.client.from('profiles').upsert({
            'id': user.id,
            'name': _usernameController.text.trim(),
            'stage':
                int.tryParse(_ckdStage.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1,
            'phone': _phoneController.text.trim(),
            'age': int.tryParse(_ageController.text.trim()),
            'weight': double.tryParse(_weightController.text.trim()),
          });
          // Save chosen logging days
          final dayRows =
              _selectedDays
                  .map(
                    (d) => {
                      'user_id': user.id,
                      'weekday': d, // e.g., 'Mon'
                    },
                  )
                  .toList();

          try {
            // Upsert rows; onConflict ensures (user_id,weekday) uniqueness
            await Supabase.instance.client
                .from('user_log_days')
                .upsert(dayRows, onConflict: 'user_id,weekday');
          } catch (e) {
            // If RLS still blocks, user can adjust days later in Profile
            print(
              'Warning: Could not save logging days during registration: $e',
            );
          }

          // -------- Save initial health goals --------
          try {
            final user = response.user!;

            // Collect all goals into a single map
            Map<String, dynamic> goalsToSave = {'user_id': user.id};

            if (stepsController.text.isNotEmpty) {
              final steps = int.tryParse(stepsController.text);
              if (steps != null) {
                goalsToSave['steps'] = steps;
                print('Adding steps goal: $steps');
              }
            }

            if (sleepController.text.isNotEmpty) {
              final sleep = double.tryParse(sleepController.text);
              if (sleep != null) {
                goalsToSave['sleep'] = sleep;
                print('Adding sleep goal: $sleep');
              }
            }

            if (weightGoalController.text.isNotEmpty) {
              final weight = double.tryParse(weightGoalController.text);
              if (weight != null) {
                goalsToSave['weight'] = weight;
                print('Adding weight goal: $weight');
              }
            }

            if (systolicController.text.isNotEmpty) {
              final systolic = int.tryParse(systolicController.text);
              if (systolic != null) {
                goalsToSave['bp_systolic'] = systolic;
                print('Adding systolic goal: $systolic');
              }
            }

            if (diastolicController.text.isNotEmpty) {
              final diastolic = int.tryParse(diastolicController.text);
              if (diastolic != null) {
                goalsToSave['bp_diastolic'] = diastolic;
                print('Adding diastolic goal: $diastolic');
              }
            }

            // Save all goals in a single operation if any goals were set
            if (goalsToSave.length > 1) { // More than just user_id
              print('Saving all goals together: $goalsToSave');
              await Supabase.instance.client.from('user_goals').upsert(
                goalsToSave,
                onConflict: 'user_id',
              );
              print('All health goals saved successfully during registration');
            } else {
              print('No health goals to save during registration');
            }
          } catch (e) {
            print('Error saving health goals during registration: $e');
            // Don't fail registration if goals can't be saved
          }

          context.go('/login');
        }
      }
    } catch (e) {
      setState(() => _error = 'Error: ${e.toString()}');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveUserGoal({
    required String field,
    required dynamic value,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    print('Saving goal: $field = $value for user ${user.id}');

    await Supabase.instance.client.from('user_goals').upsert(
      {
        'user_id': user.id,
        field: value, // This creates a dynamic key-value pair
      },
      onConflict: 'user_id', // This is crucial for one-row-per-user pattern
    );
    
    print('Goal saved successfully: $field = $value');
  }

  // ─── 3. Dialog helper ────────────────────────────────────────────────────────
  void _showHealthGoalsDialog() {
    showDialog(
      context: context,
      builder:
          (ctx) => Dialog(
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
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(12),
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
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  // Scrollable body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _goalCard(
                            icon: Icons.directions_walk,
                            label: 'Daily Steps',
                            controller: stepsController,
                            color: const Color(0xFF3B82F6),
                            unit: 'steps',
                            recommendationKey: 'steps',
                          ),
                          _goalCard(
                            icon: Icons.bedtime,
                            label: 'Sleep Target',
                            controller: sleepController,
                            color: const Color(0xFF8B5CF6),
                            unit: 'hours',
                            recommendationKey: 'sleep',
                          ),
                          _goalCard(
                            icon: Icons.monitor_weight,
                            label: 'Weight Target',
                            controller: weightGoalController,
                            color: const Color(0xFF10B981),
                            unit: 'kg',
                            // Note: Weight recommendations are typically individualized, so no recommendationKey
                          ),
                          _bpGoalCard(), // systolic/diastolic pair
                        ],
                      ),
                    ),
                  ),
                  // Footer save-all
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          // During registration, we just validate and close the dialog
                          // Goals will be saved when the user actually registers
                          print('Goals set in dialog:');
                          print('  Steps: ${stepsController.text}');
                          print('  Sleep: ${sleepController.text}');
                          print('  Weight: ${weightGoalController.text}');
                          print('  Systolic: ${systolicController.text}');
                          print('  Diastolic: ${diastolicController.text}');
                          
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Goals saved! They will be set when you complete registration.',
                              ),
                              backgroundColor: Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: const Text(
                          'Save All Goals',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  // ─── 4. Single-goal card widget ─────────────────────────────────────────────
  Widget _goalCard({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required Color color,
    String? unit,
    String? recommendationKey,
  }) {
    // Get recommendation based on CKD stage
    String? note;
    if (recommendationKey != null &&
        _ckdRecommendations.containsKey(_ckdStage)) {
      note = _ckdRecommendations[_ckdStage]![recommendationKey];
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
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
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
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixText: unit,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                note,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 5. Special card for Blood-Pressure pair ─────────────────────────────────
  Widget _bpGoalCard() {
    const color = Color(0xFFE91E63);

    // Get BP recommendation based on CKD stage
    String bpNote = 'Target: below 130/80 mmHg'; // default
    if (_ckdRecommendations.containsKey(_ckdStage)) {
      bpNote = _ckdRecommendations[_ckdStage]!['bp']!;
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
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.favorite, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Blood-Pressure Target',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: systolicController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Systolic',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('/', style: TextStyle(fontSize: 18)),
              ),
              Expanded(
                child: TextField(
                  controller: diastolicController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Diastolic',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              bpNote,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('=== REGISTER PAGE BUILD ===');
    print('Register page is being built/rendered');
    print('===========================');
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Text(
                    'Create Account',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.green, width: 2),
                      ),
                    ),
                    validator:
                        (val) =>
                            val == null || !val.contains('@')
                                ? 'Enter a valid email'
                                : null,
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed:
                            () =>
                                setState(() => _showPassword = !_showPassword),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator:
                        (val) =>
                            val == null || val.length < 6
                                ? 'At least 6 characters'
                                : null,
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: !_showConfirmPassword,
                    decoration: InputDecoration(
                      hintText: 'Confirm Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showConfirmPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed:
                            () => setState(
                              () =>
                                  _showConfirmPassword = !_showConfirmPassword,
                            ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator:
                        (val) =>
                            val != _passwordController.text
                                ? 'Passwords must match'
                                : null,
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      hintText: 'Full Name',
                      prefixIcon: Icon(Icons.person_outline),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator:
                        (val) =>
                            val == null || val.isEmpty
                                ? 'Enter Full name'
                                : null,
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator:
                        (val) =>
                            val == null || val.length < 7
                                ? 'Enter a valid phone'
                                : null,
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Age',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator:
                        (val) =>
                            val == null || val.isEmpty
                                ? 'Enter your age'
                                : null,
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _weightController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Weight (in kg)',
                      prefixIcon: Icon(Icons.monitor_weight_outlined),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator:
                        (val) =>
                            val == null || val.isEmpty
                                ? 'Enter your weight'
                                : null,
                  ),

                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    key: ValueKey(_ckdStage),
                    value: _ckdStage,
                    decoration: InputDecoration(
                      hintText: 'CKD Stage',
                      prefixIcon: Icon(Icons.health_and_safety_outlined),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items:
                        ['Stage 1', 'Stage 2', 'Stage 3', 'Stage 4', 'Stage 5']
                            .map(
                              (s) => DropdownMenuItem<String>(
                                key: ValueKey('stage_$s'),
                                value: s,
                                child: Text(s),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _ckdStage = v!),
                  ),

                  // ---------- Logging frequency ----------
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    key: ValueKey(_logFrequency),
                    value: _logFrequency,
                    decoration: InputDecoration(
                      hintText: 'Logs per week',
                      prefixIcon: Icon(Icons.event_repeat_outlined),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: List.generate(
                      7,
                      (i) => DropdownMenuItem<int>(
                        key: ValueKey('log_freq_${i + 1}'),
                        value: i + 1,
                        child: Text(
                          '${i + 1} time${i == 0 ? '' : 's'} per week',
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _logFrequency = v;
                        // Ensure selectedDays length <= frequency
                        while (_selectedDays.length > _logFrequency) {
                          _selectedDays.remove(_selectedDays.last);
                        }
                      });
                    },
                  ),

                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pick $_logFrequency day(s):',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children:
                        _weekdays.map((day) {
                          final selected = _selectedDays.contains(day);
                          final disabled =
                              _selectedDays.length >= _logFrequency &&
                              !selected;
                          return ChoiceChip(
                            label: Text(day),
                            selected: selected,
                            onSelected:
                                disabled
                                    ? null
                                    : (val) {
                                      setState(() {
                                        if (val) {
                                          _selectedDays.add(day);
                                        } else {
                                          _selectedDays.remove(day);
                                        }
                                      });
                                    },
                          );
                        }).toList(),
                  ),

                  const SizedBox(height: 20),

                  // ─── 2. Tile in the build() tree ─────────────────────────────────────────────
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
                        onTap: _showHealthGoalsDialog, // ← opens the dialog
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
                                  'Add Health Goals',
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

                  const SizedBox(height: 20),

                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF87A164),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      child:
                          _loading
                              ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text('Register'),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Already have an account? Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _confirmPasswordController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    stepsController.dispose();
    sleepController.dispose();
    weightGoalController.dispose();
    systolicController.dispose();
    diastolicController.dispose();
    super.dispose();
  }
}

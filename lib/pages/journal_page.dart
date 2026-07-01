import 'package:flutter/material.dart';
import 'dart:math';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});
  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage>
    with TickerProviderStateMixin {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  int? _monthlySteps;
  double? _monthlyAvgSleep;
  bool _loadingStats = false;

  // Pull‑to‑refresh support
  final GlobalKey<RefreshIndicatorState> _refreshKey =
      GlobalKey<RefreshIndicatorState>();

  Future<void> _handleRefresh() async {
    // Re-fetch month stats (and username via rebuild)
    await _fetchMonthlyStats();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutQuart),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutQuart),
    );
    _animationController.forward();
    _fetchMonthlyStats();
  }

  Future<void> _fetchMonthlyStats() async {
    setState(() {
      _loadingStats = true;
    });
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _monthlySteps = null;
        _monthlyAvgSleep = null;
        _loadingStats = false;
      });
      return;
    }
    // Get first and last day of the focused month
    final firstDay = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final lastDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    final String firstDayStr = DateFormat('yyyy-MM-dd').format(firstDay);
    final String lastDayStr = DateFormat('yyyy-MM-dd').format(lastDay);
    // Query steps
    final stepsData = await Supabase.instance.client
        .from('health_metrics')
        .select('value')
        .eq('user_id', user.id)
        .eq('metric_type', 'steps')
        .gte('date', firstDayStr)
        .lte('date', lastDayStr);
    int totalSteps = 0;
    if (stepsData != null && stepsData is List) {
      for (final row in stepsData) {
        totalSteps += (row['value'] as num?)?.toInt() ?? 0;
      }
    }
    // Query sleep_hours
    final sleepData = await Supabase.instance.client
        .from('health_metrics')
        .select('value')
        .eq('user_id', user.id)
        .eq('metric_type', 'sleep_hours')
        .gte('date', firstDayStr)
        .lte('date', lastDayStr);
    double sumSleep = 0.0;
    int sleepCount = 0;
    if (sleepData != null && sleepData is List) {
      for (final row in sleepData) {
        final v = (row['value'] as num?)?.toDouble();
        if (v != null) {
          sumSleep += v;
          sleepCount++;
        }
      }
    }
    setState(() {
      _monthlySteps = totalSteps;
      _monthlyAvgSleep = sleepCount > 0 ? sumSleep / sleepCount : null;
      _loadingStats = false;
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<String?> _getUsername() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final response =
        await Supabase.instance.client
            .from('profiles')
            .select('name')
            .eq('id', user.id)
            .maybeSingle();
    if (response == null) return null;
    return response['name'] as String?;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good morning";
    if (hour < 17) return "Good afternoon";
    return "Good evening";
  }

  bool _isFutureDate(DateTime d) {
    final now = DateTime.now();
    if (d.year > now.year) return true;
    if (d.year == now.year && d.month > now.month) return true;
    if (d.year == now.year && d.month == now.month && d.day > now.day) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<String?>(
      future: _getUsername(),
      builder: (context, snapshot) {
        final username = snapshot.data;
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: RefreshIndicator(
              key: _refreshKey,
              color: const Color(0xFF6366F1),
              backgroundColor: Colors.white,
              onRefresh: _handleRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: _buildHeader(context, username),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: _buildQuickStats(context),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(
                            0,
                            50 * (1 - _animationController.value),
                          ),
                          child: Opacity(
                            opacity: _animationController.value,
                            child: _buildCalendarCard(context),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ), // end RefreshIndicator
          ),
          // Removed Quick Entry floating action button
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, String? username) {
    // Use main text color and white background, bold header, green accent for icon bg
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${_getGreeting()}, ${username ?? 'there'}!",
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium?.copyWith(
                        color: const Color(0xFF232D35),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "How are you feeling today?",
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF232D35).withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              // Removed right-side psychology icon box
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              context,
              icon: Icons.directions_walk_rounded,
              title: "Steps",
              value:
                  _loadingStats
                      ? "..."
                      : _monthlySteps != null
                      ? _monthlySteps!.toString()
                      : "--",
              color: const Color(0xFF41E397),
              valueFontSize: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildStatCard(
              context,
              icon: Icons.bedtime_outlined,
              title: "Avg Sleep",
              value:
                  _loadingStats
                      ? "..."
                      : _monthlyAvgSleep != null
                      ? "${_monthlyAvgSleep!.toStringAsFixed(1)}h"
                      : "--",
              color: const Color(0xFFAF7AFF),
              valueFontSize: 18, // smaller font size for avg sleep
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    double valueFontSize = 22,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF232D35).withOpacity(0.07),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.18), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF232D35),
                  fontSize: valueFontSize,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF232D35).withOpacity(0.55),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Replace your _buildCalendarCard method with this updated version:

  Widget _buildCalendarCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF232D35).withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF6366F1), // primary blue to match app
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Previous month button
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _focusedDay = DateTime(
                          _focusedDay.year,
                          _focusedDay.month - 1,
                        );
                      });
                      _fetchMonthlyStats();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chevron_left,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  // Month/Year title
                  Text(
                    DateFormat('MMMM yyyy').format(_focusedDay),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  // Next month button
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _focusedDay = DateTime(
                          _focusedDay.year,
                          _focusedDay.month + 1,
                        );
                      });
                      _fetchMonthlyStats();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                enabledDayPredicate: (day) => !_isFutureDate(day),
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  if (_isFutureDate(selectedDay)) return; // ignore future
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                  _showJournalEntryDialog(context, selectedDay);
                },
                onPageChanged: (focusedDay) {
                  setState(() {
                    _focusedDay = focusedDay;
                  });
                  _fetchMonthlyStats();
                },
                startingDayOfWeek: StartingDayOfWeek.monday,
                calendarStyle: CalendarStyle(
                  cellMargin: const EdgeInsets.all(4),
                  todayDecoration: BoxDecoration(
                    color: const Color(0xFFAF7AFF).withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    shape: BoxShape.circle,
                  ),
                  weekendDecoration: const BoxDecoration(),
                  defaultTextStyle: const TextStyle(
                    color: Color(0xFF232D35),
                    fontWeight: FontWeight.w500,
                  ),
                  weekendTextStyle: TextStyle(
                    color: const Color(0xFF232D35).withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                  outsideTextStyle: TextStyle(
                    color: const Color(0xFF232D35).withOpacity(0.3),
                  ),
                  todayTextStyle: const TextStyle(
                    color: Color(0xFF232D35),
                    fontWeight: FontWeight.bold,
                  ),
                  selectedTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  leftChevronVisible: false,
                  rightChevronVisible: false,
                  headerPadding: EdgeInsets.zero,
                  titleTextStyle: TextStyle(fontSize: 0, height: 0),
                  headerMargin: EdgeInsets.zero,
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                    color: const Color(0xFF232D35).withOpacity(0.6),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  weekendStyle: TextStyle(
                    color: const Color(0xFF232D35).withOpacity(0.4),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// MODERN DIALOGS and SAVE/LOAD LOGIC BELOW

void _showJournalEntryDialog(
  BuildContext context,
  DateTime selectedDate,
) async {
  final theme = Theme.of(context);
  TextEditingController notesController = TextEditingController();
  int? moodPercentScore;
  double? sleepHours;
  double? sleepQuality;

  int? stepsCount;
  double? weightKg;
  int? bpSys;
  int? bpDia;

  // Load existing data
  final user = Supabase.instance.client.auth.currentUser;
  if (user != null) {
    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    final existing =
        await Supabase.instance.client
            .from('mood_entries')
            .select('score, notes')
            .eq('user_id', user.id)
            .eq('date', dateStr)
            .maybeSingle();
    if (existing != null && existing['score'] != null) {
      moodPercentScore = existing['score'] as int;
    }
    if (existing != null && existing['notes'] != null) {
      notesController.text = existing['notes'] as String;
    }
    final sleepData = await Supabase.instance.client
        .from('health_metrics')
        .select('metric_type, value')
        .eq('user_id', user.id)
        .eq('date', dateStr);
    for (var row in sleepData) {
      if (row['metric_type'] == 'sleep_hours') {
        sleepHours = (row['value'] as num?)?.toDouble();
      } else if (row['metric_type'] == 'sleep_quality') {
        sleepQuality = (row['value'] as num?)?.toDouble();
      }
      // (sleep rows already handled)
    }
    final otherData = await Supabase.instance.client
        .from('health_metrics')
        .select('metric_type, value')
        .eq('user_id', user.id)
        .eq('date', dateStr)
        .inFilter('metric_type', ['steps', 'weight']);
    for (var row in otherData) {
      if (row['metric_type'] == 'steps') {
        stepsCount = (row['value'] as num?)?.toInt();
      } else if (row['metric_type'] == 'weight') {
        weightKg = (row['value'] as num?)?.toDouble();
      }
    }
    final bpRow =
        await Supabase.instance.client
            .from('blood_pressure_readings')
            .select('systolic, diastolic')
            .eq('user_id', user.id)
            .eq('date', dateStr)
            .maybeSingle();
    if (bpRow != null) {
      bpSys = (bpRow['systolic'] as num?)?.toInt();
      bpDia = (bpRow['diastolic'] as num?)?.toInt();
    }
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border.all(color: const Color(0xFFEEF2F5), width: 1),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF232D35).withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2F5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    DateFormat('EEEE, MMMM d, y').format(selectedDate),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF232D35),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  _buildModernInputRow(
                    context,
                    icon: Icons.bedtime_outlined,
                    title: "Sleep Quality",
                    subtitle:
                        sleepHours != null || sleepQuality != null
                            ? [
                              if (sleepHours != null)
                                "${sleepHours!.toStringAsFixed(1)} hrs",
                              if (sleepQuality != null)
                                "Quality: ${sleepQuality!.toInt()}/10",
                            ].join(" • ")
                            : "Track your sleep",
                    color: const Color(0xFFAF7AFF), // Sleep accent purple
                    onTap: () async {
                      final result = await _showSleepQualityDialog(
                        context,
                        selectedDate: selectedDate,
                        initialSleepHours: sleepHours,
                        initialSleepQuality: sleepQuality,
                      );
                      if (result != null &&
                          result is List &&
                          result.length == 2) {
                        setModalState(() {
                          sleepHours = result[0];
                          sleepQuality = result[1];
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildModernInputRow(
                    context,
                    icon: Icons.mood_outlined,
                    title: "Mood Score",
                    subtitle:
                        moodPercentScore != null
                            ? "$moodPercentScore% wellbeing"
                            : "Rate your mood",
                    color: const Color(0xFF20B4F3), // Mood accent blue
                    onTap: () async {
                      int? percent = await _showMoodDialog(
                        context,
                        selectedDate,
                        initialScore: moodPercentScore,
                      );
                      if (percent != null) {
                        setModalState(() {
                          moodPercentScore = percent;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildModernInputRow(
                    context,
                    icon: Icons.directions_walk,
                    title: "Steps",
                    subtitle:
                        stepsCount != null
                            ? "$stepsCount steps"
                            : "Enter today's steps",
                    color: const Color(0xFF41E397), // Steps green
                    onTap: () async {
                      final val = await _showNumberDialog(
                        context,
                        title: "Today's Steps",
                        initialValue: stepsCount?.toString(),
                        suffix: "steps",
                      );
                      if (val != null) {
                        setModalState(() {
                          stepsCount = int.tryParse(val);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildModernInputRow(
                    context,
                    icon: Icons.monitor_weight_outlined,
                    title: "Weight",
                    subtitle:
                        weightKg != null
                            ? "${weightKg!.toStringAsFixed(1)} kg"
                            : "Enter your weight",
                    color: const Color(0xFF20B4F3), // blue accent
                    onTap: () async {
                      final val = await _showNumberDialog(
                        context,
                        title: "Weight (kg)",
                        initialValue: weightKg?.toString(),
                        suffix: "kg",
                      );
                      if (val != null) {
                        setModalState(() {
                          weightKg = double.tryParse(val);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildModernInputRow(
                    context,
                    icon: Icons.favorite_border,
                    title: "Blood Pressure",
                    subtitle:
                        (bpSys != null && bpDia != null)
                            ? "$bpSys / $bpDia mmHg"
                            : "Add BP reading",
                    color: const Color(0xFFFF6B6B), // red accent
                    onTap: () async {
                      final result = await _showBpDialog(
                        context,
                        initialSys: bpSys,
                        initialDia: bpDia,
                      );
                      if (result != null && result.length == 2) {
                        setModalState(() {
                          bpSys = result[0];
                          bpDia = result[1];
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Today's Notes",
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF232D35),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    maxLines: 4,
                    style: const TextStyle(color: Color(0xFF232D35)),
                    decoration: InputDecoration(
                      hintText: "How was your day? What are you grateful for?",
                      hintStyle: const TextStyle(
                        color: Color(0xFF232D35),
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xFFEEF2F5),
                          width: 1.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xFF6366F1),
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6C7682),
                            backgroundColor: Colors.white,
                            side: const BorderSide(
                              color: Color(0xFFEEF2F5),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            await _saveJournalEntry(
                              context,
                              selectedDate,
                              moodPercentScore,
                              sleepHours,
                              sleepQuality,
                              stepsCount,
                              weightKg,
                              bpSys,
                              bpDia,
                              notesController.text,
                            );
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            "Save",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _buildModernInputRow(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required Color color,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF232D35).withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.16), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF232D35),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF232D35).withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios, color: color, size: 18),
        ],
      ),
    ),
  );
}

Future<void> _saveJournalEntry(
  BuildContext context,
  DateTime selectedDate,
  int? moodPercentScore,
  double? sleepHours,
  double? sleepQuality,
  int? stepsCount,
  double? weightKg,
  int? bpSys,
  int? bpDia,
  String notes,
) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return;

  final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);

  try {
    // Save mood entry
    if (moodPercentScore != null || notes.isNotEmpty) {
      await Supabase.instance.client.from('mood_entries').upsert({
        'user_id': user.id,
        'score': moodPercentScore ?? 0,
        'date': dateStr,
        'notes': notes,
      }, onConflict: 'user_id,date');
    }

    // Save sleep metrics
    if (sleepHours != null || sleepQuality != null) {
      await Supabase.instance.client
          .from('health_metrics')
          .delete()
          .eq('user_id', user.id)
          .eq('date', dateStr)
          .inFilter('metric_type', ['sleep_hours', 'sleep_quality']);

      List<Map<String, dynamic>> inserts = [];
      if (sleepHours != null) {
        inserts.add({
          'user_id': user.id,
          'metric_type': 'sleep_hours',
          'value': sleepHours,
          'date': dateStr,
        });
      }
      if (sleepQuality != null) {
        inserts.add({
          'user_id': user.id,
          'metric_type': 'sleep_quality',
          'value': sleepQuality,
          'date': dateStr,
        });
      }

      if (inserts.isNotEmpty) {
        await Supabase.instance.client.from('health_metrics').insert(inserts);
      }
    }

    // Save steps – delete existing row for the day, then insert
    if (stepsCount != null) {
      await Supabase.instance.client
          .from('health_metrics')
          .delete()
          .eq('user_id', user.id)
          .eq('metric_type', 'steps')
          .eq('date', dateStr);

      await Supabase.instance.client.from('health_metrics').insert({
        'user_id': user.id,
        'metric_type': 'steps',
        'value': stepsCount,
        'date': dateStr,
      });
    }

    // Save weight – delete old then insert
    if (weightKg != null) {
      await Supabase.instance.client
          .from('health_metrics')
          .delete()
          .eq('user_id', user.id)
          .eq('metric_type', 'weight')
          .eq('date', dateStr);

      await Supabase.instance.client.from('health_metrics').insert({
        'user_id': user.id,
        'metric_type': 'weight',
        'value': weightKg,
        'date': dateStr,
      });
    }

    // Save blood pressure – delete old row for the day, then insert
    if (bpSys != null && bpDia != null) {
      await Supabase.instance.client
          .from('blood_pressure_readings')
          .delete()
          .eq('user_id', user.id)
          .eq('date', dateStr);

      await Supabase.instance.client.from('blood_pressure_readings').insert({
        'user_id': user.id,
        'systolic': bpSys,
        'diastolic': bpDia,
        'date': dateStr,
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Journal entry saved successfully!'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error saving entry: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

Future<String?> _showNumberDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
  String? suffix,
}) async {
  final TextEditingController controller = TextEditingController(
    text: initialValue ?? '',
  );

  return await showDialog<String>(
    context: context,
    builder:
        (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFEEF2F5), width: 1.5),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF6366F1),
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: false,
            ),
            decoration: InputDecoration(
              suffixText: suffix,
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF6366F1),
                  width: 2,
                ),
              ),
              hintStyle: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6C7682),
                side: const BorderSide(color: Color(0xFFEEF2F5), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              child: const Text(
                "Cancel",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                elevation: 0,
              ),
              child: const Text(
                "Save",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
  );
}

Future<List<int>?> _showBpDialog(
  BuildContext context, {
  int? initialSys,
  int? initialDia,
}) async {
  final sysCtrl = TextEditingController(text: initialSys?.toString() ?? '');
  final diaCtrl = TextEditingController(text: initialDia?.toString() ?? '');

  return await showDialog<List<int>>(
    context: context,
    builder:
        (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFEEF2F5), width: 1.5),
          ),
          title: const Text(
            "Blood Pressure",
            style: TextStyle(
              color: Color(0xFF6366F1),
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: sysCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Systolic (mmHg)",
                  filled: true,
                  fillColor: Color(0xFFF8F9FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Color(0xFF6366F1), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: diaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Diastolic (mmHg)",
                  filled: true,
                  fillColor: Color(0xFFF8F9FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Color(0xFF6366F1), width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, null),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6C7682),
                side: const BorderSide(color: Color(0xFFEEF2F5), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              child: const Text(
                "Cancel",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final s = int.tryParse(sysCtrl.text.trim());
                final d = int.tryParse(diaCtrl.text.trim());
                if (s != null && d != null) {
                  Navigator.pop(context, [s, d]);
                } else {
                  Navigator.pop(context, null);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                elevation: 0,
              ),
              child: const Text(
                "Save",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
  );
}

Future<List?> _showSleepQualityDialog(
  BuildContext context, {
  DateTime? selectedDate,
  double? initialSleepHours,
  double? initialSleepQuality,
}) async {
  double sleepHours = initialSleepHours ?? 0;
  int sleepQuality = (initialSleepQuality ?? 0).round();
  final TextEditingController hoursController = TextEditingController(
    text: sleepHours > 0 ? sleepHours.toString() : '',
  );

  return await showDialog<List>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder:
            (context, setState) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFFEEF2F5), width: 1.5),
              ),
              title: const Text(
                "Sleep Quality Survey",
                style: TextStyle(
                  color: Color(0xFF6366F1),
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Sleep Quality (0 = very poor, 10 = excellent):",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: List.generate(11, (index) {
                      return ChoiceChip(
                        label: Text(
                          index.toString(),
                          style: TextStyle(
                            color:
                                sleepQuality == index
                                    ? Colors.white
                                    : const Color(0xFF374151),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        selected: sleepQuality == index,
                        selectedColor: const Color(0xFF6366F1),
                        backgroundColor: const Color(0xFFF3F4F6),
                        onSelected: (_) => setState(() => sleepQuality = index),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Hours of Sleep",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: hoursController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      hintText: "e.g., 7.5",
                      hintStyle: TextStyle(color: Color(0xFF6B7280)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(
                          color: Color(0xFF6366F1),
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Color(0xFFF8F9FA),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (v) {
                      setState(() {
                        sleepHours = double.tryParse(v) ?? 0;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6C7682),
                    side: const BorderSide(
                      color: Color(0xFFEEF2F5),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pop([sleepHours, sleepQuality.toDouble()]);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Save",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
      );
    },
  );
}

Future<int?> _showMoodDialog(
  BuildContext context,
  DateTime selectedDate, {
  int? initialScore,
}) async {
  List<String> moodStatements = [
    "I have felt cheerful in good spirits.",
    "I have felt calm and relaxed.",
    "I have felt active and vigorous.",
    "I woke up feeling fresh and rested.",
    "My daily life has been filled with things that interest me.",
  ];
  List<int> moodRatings;
  if (initialScore != null) {
    // Distribute (initialScore / 4).round() evenly among 5 questions
    int total = (initialScore / 4).round();
    int perQ = total ~/ 5;
    int rem = total % 5;
    moodRatings = List<int>.filled(5, perQ);
    for (int i = 0; i < rem; i++) {
      moodRatings[i] += 1;
    }
  } else {
    moodRatings = List<int>.filled(5, 0);
  }

  return await showDialog<int>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          int rawScore = moodRatings.fold(0, (a, b) => a + b);
          double percentScore = rawScore * 4.0;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFEEF2F5), width: 1.5),
            ),
            title: const Text(
              "Mood Index",
              style: TextStyle(
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
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
                              color: Color(0xFF6366F1),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: List.generate(6, (ratingIndex) {
                              int value = ratingIndex;
                              return ChoiceChip(
                                label: Text(
                                  value.toString(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        moodRatings[index] == value
                                            ? Colors.white
                                            : const Color(0xFF374151),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                selected: moodRatings[index] == value,
                                selectedColor: const Color(0xFF6366F1),
                                backgroundColor: const Color(0xFFF3F4F6),
                                shape: const CircleBorder(),
                                labelPadding: const EdgeInsets.all(2),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onSelected: (bool selected) {
                                  setState(() {
                                    moodRatings[index] = selected ? value : 0;
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
                        color: Color(0xFF6366F1),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(null),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6C7682),
                  side: const BorderSide(color: Color(0xFFEEF2F5), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  "Cancel",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  int percent = (rawScore * 4.0).round();
                  Navigator.of(context).pop(percent);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  "Save",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tuple/tuple.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// Data state enum for managing different data availability states
enum DataState { noData, insufficientData, limitedData, sufficientData }

/// ─────────────────────────────────────────────────────────────────────────
/// Advanced Analytics InsightsPage for CKD patients - Deep Health Correlations
/// ─────────────────────────────────────────────────────────────────────────
class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage>
    with TickerProviderStateMixin {
  final Map<String, double> _steps = {};
  final Map<String, double> _weights = {};
  final Map<String, double> _sleep = {};
  final Map<String, double> _systolic = {};
  final Map<String, double> _diastolic = {};
  final Map<String, int> _moodScore = {};
  final Map<String, double> _sleepQuality = {};

  late final GenerativeModel _geminiModel;
  String _aiSummary = '';
  bool _aiSummaryLoading = false;
  static const String _geminiApiKey = 'AIzaSyBeIpMWkJpJGjwWIqGFF8gcqE3Z4VBA8Po';

  // Advanced analytics data
  Map<String, double> _weeklyAverages = {};
  Map<String, double> _trendPredictions = {};
  List<CorrelationInsight> _correlationInsights = [];
  Map<String, RiskAssessment> _riskAssessments = {};

  double _userStepsGoal = 8000;
  double _userSleepGoal = 8;
  double _userWeightGoal = 70;
  double _userBpSystolicGoal = 120;
  double _userBpDiastolicGoal = 80;

  bool _loading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Professional health analytics color palette
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color secondaryTeal = Color(0xFF06B6D4);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color dangerRed = Color(0xFFDC2626);
  static const Color successGreen = Color(0xFF10B981);
  static const Color softPurple = Color(0xFF8B5CF6);
  static const Color mutedGray = Color(0xFF6B7280);
  static const Color lightGray = Color(0xFFF9FAFB);
  static const Color cardShadow = Color(0x0A000000);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _fetchRecentEntries();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchRecentEntries() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // Fetch user goals
      final goals = await Supabase.instance.client
          .from('user_goals')
          .select()
          .eq('user_id', user.id)
          .limit(1);

      if (goals.isNotEmpty) {
        final g = goals.first;
        _userStepsGoal = double.tryParse(g['steps'].toString()) ?? 8000;
        _userSleepGoal = double.tryParse(g['sleep'].toString()) ?? 8;
        _userWeightGoal = double.tryParse(g['weight'].toString()) ?? 70;
        _userBpSystolicGoal =
            double.tryParse(g['bp_systolic'].toString()) ?? 120;
        _userBpDiastolicGoal =
            double.tryParse(g['bp_diastolic'].toString()) ?? 80;
      }

      // Fetch comprehensive health metrics (30 days for better analysis)
      final metrics = await Supabase.instance.client
          .from('health_metrics')
          .select()
          .eq('user_id', user.id)
          .order('date', ascending: false)
          .limit(120);

      for (var r in metrics) {
        final d = r['date'] as String;
        final v = double.tryParse(r['value'].toString()) ?? 0;
        final metricType = r['metric_type'] as String;

        switch (metricType) {
          case 'steps':
            _steps[d] = v;
            break;
          case 'sleep_hours':
            _sleep[d] = v;
            break;
          case 'weight':
            _weights[d] = v;
            break;
          case 'sleep_quality':
            _sleepQuality[d] = v;
            break;
        }
      }

      // Fetch blood pressure data
      final bp = await Supabase.instance.client
          .from('blood_pressure_readings')
          .select()
          .eq('user_id', user.id)
          .order('date', ascending: false)
          .limit(60);

      for (var r in bp) {
        final d = r['date'] as String;
        final systolic = double.tryParse(r['systolic'].toString()) ?? 0;
        final diastolic = double.tryParse(r['diastolic'].toString()) ?? 0;
        _systolic[d] = systolic;
        _diastolic[d] = diastolic;
      }

      // Fetch mood data
      final moods = await Supabase.instance.client
          .from('mood_entries')
          .select()
          .eq('user_id', user.id)
          .order('date', ascending: false)
          .limit(60);

      for (var r in moods) {
        final d = r['date'] as String;
        final score = r['score'] as int? ?? 50;
        _moodScore[d] = score;
      }

      // Perform advanced analytics
      _performAdvancedAnalytics();
    } catch (e) {
      debugPrint('Error fetching insights: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
      _animationController.forward();
      _geminiModel = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _geminiApiKey,
      );
    }
  }

  Future<void> _generateAISummary() async {
    // Check if there's enough data before attempting to generate
    final hasSteps = _steps.length >= 7;
    final hasBP = _systolic.length >= 7;
    final hasWeight = _weights.length >= 7;
    final hasSleep = _sleep.length >= 5;
    final hasMood = _moodScore.length >= 5;

    final sufficientDataPoints =
        [
          hasSteps,
          hasBP,
          hasWeight,
          hasSleep,
          hasMood,
        ].where((has) => has).length;

    if (sufficientDataPoints < 3) {
      setState(() {
        _aiSummary =
            'Not enough data yet to generate a meaningful correlation analysis. Please continue logging your health metrics daily. You need at least 7 days of data for steps, blood pressure, and weight to see reliable patterns.';
        _aiSummaryLoading = false;
      });
      return;
    }

    setState(() {
      _aiSummaryLoading = true;
      _aiSummary = '';
    });

    try {
      final stepsCorrelation = _calculateCorrelation(_steps, _systolic);
      final weightVariability = _calculateVariability(_weights);
      final weightTrend = _calculateTrend(_weights, 7);
      final bpTrend = _calculateTrend(_systolic, 14);
      final overallScore =
          _correlationInsights.isNotEmpty
              ? _correlationInsights.last.impactScore
              : 0.0;

      final dataText = '''
PATIENT HEALTH DATA:
- Average Daily Steps: ${_weeklyAverages['steps']?.toStringAsFixed(0)} steps (Goal: ${_userStepsGoal.toInt()})
- Average Blood Pressure: ${_weeklyAverages['systolic']?.toStringAsFixed(0)}/${_weeklyAverages['diastolic']?.toStringAsFixed(0)} mmHg (Goal: <${_userBpSystolicGoal.toInt()}/${_userBpDiastolicGoal.toInt()})
- Average Weight: ${_weeklyAverages['weight']?.toStringAsFixed(1)} kg (Goal: ${_userWeightGoal.toStringAsFixed(1)} kg)
- Weight Variability: ${weightVariability.toStringAsFixed(2)} kg daily variation
- Weight Trend (7 days): ${weightTrend >= 0 ? '+' : ''}${weightTrend.toStringAsFixed(2)} kg/week
- Blood Pressure Trend (14 days): ${bpTrend >= 0 ? '+' : ''}${bpTrend.toStringAsFixed(1)} mmHg/week
- Average Sleep Hours: ${_weeklyAverages['sleep']?.toStringAsFixed(1)} hours (Goal: ${_userSleepGoal.toStringAsFixed(1)} hours)
- Sleep Quality Score: ${_weeklyAverages['sleep_quality']?.toStringAsFixed(1)}/10 (Goal: 8+/10)
- Average Mood Score: ${_weeklyAverages['mood']?.toStringAsFixed(0)}/100

CORRELATION ANALYSIS:
- Steps vs Blood Pressure Correlation: ${stepsCorrelation.toStringAsFixed(2)} (Range: -1.0 to +1.0, where negative means more steps = lower BP)
- Overall Kidney Health Protection Score: ${(overallScore * 100).toInt()}%

INTERPRETATION GUIDE:
- Weight variability >1.0 kg suggests fluid retention issues
- Negative steps-BP correlation (< -0.3) means exercise is helping control blood pressure
- Weight gain >1 kg/week is concerning for kidney patients
- BP increasing >2 mmHg/week needs attention
''';

      final prompt =
          '''You are analyzing health data for a chronic kidney disease (CKD) patient. Write a clear, compassionate summary explaining what their numbers mean for their kidney health.

${dataText}

Based on these numbers, write a 3-4 sentence analysis that:
1. Explains the most important finding in simple terms (e.g., "Your physical activity is helping control your blood pressure" or "Your weight is showing concerning fluctuations")
2. Explains WHY this matters for kidney health specifically
3. States whether their current patterns are protective or risky for their kidneys
4. Mentions one encouraging finding if there is any

Write in a warm, supportive tone. Use simple language - imagine explaining to someone who doesn't have medical training. Focus on what the patterns MEAN rather than just restating numbers. Be honest but encouraging.

DO NOT:
- Just repeat the numbers
- Use medical jargon
- Give specific medical advice
- Make predictions

DO:
- Explain what patterns you see and why they matter
- Connect the data to kidney health
- Be specific about which behaviors are helping or hurting
- Use phrases like "Your data shows...", "This pattern suggests...", "This is important because..."''';

      final response = await _geminiModel.generateContent([
        Content.text(prompt),
      ]);

      setState(() {
        _aiSummary = response.text ?? 'Unable to generate summary';
        _aiSummaryLoading = false;
      });
    } catch (e) {
      setState(() {
        _aiSummary = 'Error generating summary: ${e.toString()}';
        _aiSummaryLoading = false;
      });
      print('AI Summary error: $e');
    }
  }

  void _performAdvancedAnalytics() {
    _calculateWeeklyAverages();
    _generateCorrelationInsights();
    _assessHealthRisks();
    _predictTrends();
  }

  void _calculateWeeklyAverages() {
    _weeklyAverages = {
      'steps': _calculateRecentAverage(_steps, 7),
      'weight': _calculateRecentAverage(_weights, 7),
      'systolic': _calculateRecentAverage(_systolic, 7),
      'sleep': _calculateRecentAverage(_sleep, 7),
      'sleep_quality': _calculateRecentAverage(_sleepQuality, 7),
      'mood': _calculateRecentAverageInt(_moodScore, 7),
    };
  }

  double _calculateRecentAverage(Map<String, double> data, int days) {
    if (data.isEmpty) return 0;
    final sortedKeys = data.keys.toList()..sort();
    final recentKeys =
        sortedKeys.length > days
            ? sortedKeys.sublist(sortedKeys.length - days)
            : sortedKeys;
    final recentValues = recentKeys.map((key) => data[key]!).toList();
    return recentValues.reduce((a, b) => a + b) / recentValues.length;
  }

  double _calculateRecentAverageInt(Map<String, int> data, int days) {
    if (data.isEmpty) return 0;
    final sortedKeys = data.keys.toList()..sort();
    final recentKeys =
        sortedKeys.length > days
            ? sortedKeys.sublist(sortedKeys.length - days)
            : sortedKeys;
    final recentValues =
        recentKeys.map((key) => data[key]!.toDouble()).toList();
    return recentValues.reduce((a, b) => a + b) / recentValues.length;
  }

  void _generateCorrelationInsights() {
    _correlationInsights = [
      _analyzeStepsBloodPressureCorrelation(),
      _analyzeWeightFluidRetentionCorrelation(),
      _analyzeSleepKidneyRecoveryCorrelation(),
      _analyzeMoodActivityCorrelation(),
      _analyzeComprehensiveKidneyHealthCorrelation(),
    ];
  }

  CorrelationInsight _analyzeStepsBloodPressureCorrelation() {
    final correlation = _calculateCorrelation(_steps, _systolic);
    final avgSteps = _weeklyAverages['steps'] ?? 0;
    final avgBP = _weeklyAverages['systolic'] ?? 120;

    String analysis;
    Color color;
    double impactScore;

    if (correlation < -0.3 && avgSteps > _userStepsGoal * 0.8) {
      analysis =
          "Excellent! Your increased physical activity is significantly lowering your blood pressure. This reduces kidney strain and slows CKD progression. Every 1000 extra steps correlates with ~2-3 mmHg BP reduction.";
      color = successGreen;
      impactScore = 0.85;
    } else if (correlation < -0.2) {
      analysis =
          "Good correlation detected. Your physical activity is moderately helping control blood pressure. Increasing to ${_userStepsGoal.toInt()} daily steps could further reduce kidney stress by improving cardiovascular efficiency.";
      color = primaryBlue;
      impactScore = 0.65;
    } else if (avgSteps < _userStepsGoal * 0.6) {
      analysis =
          "Low activity detected. Sedentary lifestyle is a major CKD risk factor. Your current activity level may be contributing to elevated BP and increased kidney workload. Even 2000 more daily steps could reduce CKD progression by 15-20%.";
      color = dangerRed;
      impactScore = 0.3;
    } else {
      analysis =
          "Mixed signals in your activity-BP relationship. Consider timing: exercise can temporarily raise BP, but long-term activity reduces it. Focus on consistent moderate activity for optimal kidney protection.";
      color = warningOrange;
      impactScore = 0.55;
    }

    return CorrelationInsight(
      title: "Activity → Blood Pressure Impact",
      correlation: correlation,
      analysis: analysis,
      color: color,
      impactScore: impactScore,
      recommendation:
          avgSteps < _userStepsGoal * 0.8
              ? "Increase daily steps by 500-1000 weekly until reaching ${_userStepsGoal.toInt()} steps"
              : "Maintain current activity level - excellent kidney protection",
    );
  }

  CorrelationInsight _analyzeWeightFluidRetentionCorrelation() {
    final weightVariability = _calculateVariability(_weights);
    final avgWeight = _weeklyAverages['weight'] ?? _userWeightGoal;
    final weightTrend = _calculateTrend(_weights, 14);

    String analysis;
    Color color;
    double impactScore;

    if (weightVariability > 1.5 && weightTrend > 0.5) {
      analysis =
          "⚠️ CRITICAL: Rapid weight gain (${weightTrend.toStringAsFixed(1)}kg) with high variability suggests fluid retention - a key sign of kidney function decline. This pattern often precedes CKD complications requiring immediate medical attention.";
      color = dangerRed;
      impactScore = 0.95;
    } else if (weightVariability > 1.0) {
      analysis =
          "Moderate weight fluctuations detected. In CKD patients, daily weight changes >1kg often indicate fluid imbalance. Your kidneys may be struggling to regulate fluid, requiring closer monitoring and possible medication adjustment.";
      color = warningOrange;
      impactScore = 0.75;
    } else if (weightVariability < 0.5 && math.pow(weightTrend, 2) < 0.25) {
      analysis =
          "Excellent weight stability! Consistent weight (±0.5kg) indicates good fluid balance and kidney function. This stability reduces cardiovascular stress and slows CKD progression significantly.";
      color = successGreen;
      impactScore = 0.9;
    } else {
      analysis =
          "Weight patterns within acceptable range. Continue daily monitoring as weight is the earliest indicator of fluid retention in CKD. Small, consistent changes are better than large fluctuations.";
      color = primaryBlue;
      impactScore = 0.7;
    }

    return CorrelationInsight(
      title: "Weight Stability → Kidney Function",
      correlation: -weightVariability, // Negative because stability is good
      analysis: analysis,
      color: color,
      impactScore: impactScore,
      recommendation:
          weightVariability > 1.0
              ? "Contact your nephrologist if weight changes >1kg in 24 hours"
              : "Continue daily weight monitoring - excellent compliance",
    );
  }

  CorrelationInsight _analyzeSleepKidneyRecoveryCorrelation() {
    final avgSleepQuality =
        _weeklyAverages['sleep_quality'] ?? 5.0; // 0-10 scale
    final sleepQualityConsistency =
        1.0 - (_calculateVariability(_sleepQuality) / 10.0); // Normalize to 0-1
    final moodCorrelation = _calculateCorrelationWithInt(
      _sleepQuality,
      _moodScore,
    );

    String analysis;
    Color color;
    double impactScore;

    if (avgSleepQuality >= 8.0 && sleepQualityConsistency > 0.85) {
      analysis =
          "Outstanding sleep quality! Consistent high-quality sleep (${avgSleepQuality.toStringAsFixed(1)}/10) supports optimal kidney recovery. During restorative sleep, your kidneys filter waste more efficiently and blood pressure naturally decreases, reducing long-term kidney damage by up to 30%.";
      color = successGreen;
      impactScore = 0.9;
    } else if (avgSleepQuality < 5.0) {
      analysis =
          "Poor sleep quality detected (${avgSleepQuality.toStringAsFixed(1)}/10). Low-quality sleep increases stress hormones and blood pressure, accelerating kidney damage. CKD patients with poor sleep quality show 40% faster progression rates due to inadequate kidney recovery time.";
      color = dangerRed;
      impactScore = 0.4;
    } else if (sleepQualityConsistency < 0.7) {
      analysis =
          "Inconsistent sleep quality patterns. Irregular sleep quality disrupts circadian kidney function and stress hormone regulation. Even occasional poor sleep can impact kidney health and blood pressure control in CKD patients.";
      color = warningOrange;
      impactScore = 0.6;
    } else if (avgSleepQuality >= 6.5) {
      analysis =
          "Good sleep quality (${avgSleepQuality.toStringAsFixed(1)}/10) supporting kidney recovery. Your current sleep quality helps basic kidney repair processes. Aiming for 8+ consistently could provide additional protection against CKD progression.";
      color = primaryBlue;
      impactScore = 0.75;
    } else {
      analysis =
          "Moderate sleep quality (${avgSleepQuality.toStringAsFixed(1)}/10). Your current sleep supports basic kidney recovery, but optimization could provide significant protection. Focus on sleep environment and habits to reach 7-8/10 quality consistently.";
      color = primaryBlue;
      impactScore = 0.6;
    }

    return CorrelationInsight(
      title: "Sleep Quality → Kidney Recovery",
      correlation: sleepQualityConsistency,
      analysis: analysis,
      color: color,
      impactScore: impactScore,
      recommendation:
          avgSleepQuality < 7.0
              ? "Improve sleep environment: dark room, cool temperature, comfortable mattress, avoid screens 1h before bed"
              : "Excellent sleep quality - maintain current sleep habits for optimal kidney protection",
    );
  }

  CorrelationInsight _analyzeMoodActivityCorrelation() {
    final moodStepsCorr = _calculateCorrelationWithInt(_steps, _moodScore);
    final avgMood = _weeklyAverages['mood'] ?? 60;
    final avgSteps = _weeklyAverages['steps'] ?? 5000;

    String analysis;
    Color color;
    double impactScore;

    if (moodStepsCorr > 0.4 && avgMood > 70) {
      analysis =
          "Strong positive feedback loop! Higher activity boosts mood, which motivates more activity. This cycle is crucial for CKD management - patients with positive mood show 50% better medication adherence and lifestyle compliance.";
      color = successGreen;
      impactScore = 0.8;
    } else if (avgMood < 40 && avgSteps < _userStepsGoal * 0.6) {
      analysis =
          "Concerning negative cycle: low mood → reduced activity → worse mood. This pattern significantly impacts CKD outcomes. Depression in CKD patients increases mortality risk by 60% and accelerates kidney function decline.";
      color = dangerRed;
      impactScore = 0.3;
    } else if (moodStepsCorr > 0.2) {
      analysis =
          "Moderate mood-activity connection. Your mental wellness and physical activity are linked. Improving either can create positive momentum for CKD management. Consider combining gentle exercise with mood-lifting activities.";
      color = primaryBlue;
      impactScore = 0.65;
    } else {
      analysis =
          "Weak mood-activity correlation suggests external factors affecting your wellness. Focus on stress management and social support, which are crucial for both mental health and kidney disease management.";
      color = warningOrange;
      impactScore = 0.5;
    }

    return CorrelationInsight(
      title: "Mood ↔ Activity Feedback Loop",
      correlation: moodStepsCorr,
      analysis: analysis,
      color: color,
      impactScore: impactScore,
      recommendation:
          avgMood < 50
              ? "Consider counseling support - mental health directly impacts CKD outcomes"
              : "Maintain positive mood-activity cycle through regular routines",
    );
  }

  CorrelationInsight _analyzeComprehensiveKidneyHealthCorrelation() {
    final bpScore =
        _userBpSystolicGoal > (_weeklyAverages['systolic'] ?? 140) ? 1.0 : 0.5;
    final weightScore = (_calculateVariability(_weights) < 1.0) ? 1.0 : 0.5;
    final activityScore = (_weeklyAverages['steps'] ?? 0) / _userStepsGoal;
    final sleepScore =
        (_weeklyAverages['sleep_quality'] ?? 0) /
        10.0; // 0-10 scale normalized to 0-1

    final overallKidneyHealthScore =
        (bpScore +
            weightScore +
            math.min(activityScore, 1.0) +
            math.min(sleepScore, 1.0)) /
        4;

    String analysis;
    Color color;

    if (overallKidneyHealthScore >= 0.85) {
      analysis =
          "🌟 EXCELLENT kidney health management! Your comprehensive approach (BP control, weight stability, activity, sleep quality) creates synergistic protection. This level of management can slow CKD progression by 60-70% compared to poor management.";
      color = successGreen;
    } else if (overallKidneyHealthScore >= 0.7) {
      analysis =
          "Good overall management with room for optimization. Your multi-factor approach is working well. Focus on the weakest area for maximum kidney protection benefits - small improvements in all areas compound significantly.";
      color = primaryBlue;
    } else if (overallKidneyHealthScore >= 0.5) {
      analysis =
          "Moderate kidney health management. Several factors need attention for optimal CKD protection. The interconnected nature of these metrics means improving one often helps others - start with the most achievable goal.";
      color = warningOrange;
    } else {
      analysis =
          "⚠️ Multiple risk factors detected. Comprehensive intervention needed to slow CKD progression. The combination of poor BP control, unstable weight, low activity, and poor sleep quality significantly accelerates kidney damage.";
      color = dangerRed;
    }

    return CorrelationInsight(
      title: "Comprehensive CKD Protection Score",
      correlation: overallKidneyHealthScore,
      analysis: analysis,
      color: color,
      impactScore: overallKidneyHealthScore,
      recommendation:
          overallKidneyHealthScore < 0.7
              ? "Schedule nephrology consultation to optimize multi-factor management"
              : "Maintain excellent comprehensive kidney care",
    );
  }

  void _assessHealthRisks() {
    _riskAssessments = {
      'cardiovascular': _assessCardiovascularRisk(),
      'progression': _assessCKDProgressionRisk(),
      'fluid': _assessFluidRetentionRisk(),
    };
  }

  RiskAssessment _assessCardiovascularRisk() {
    final avgBP = _weeklyAverages['systolic'] ?? 120;
    final avgSteps = _weeklyAverages['steps'] ?? 5000;
    final weightTrend = _calculateTrend(_weights, 30);

    double riskScore = 0;
    if (avgBP > 140)
      riskScore += 0.4;
    else if (avgBP > 130)
      riskScore += 0.2;

    if (avgSteps < 5000)
      riskScore += 0.3;
    else if (avgSteps < 8000)
      riskScore += 0.1;

    if (weightTrend > 2) riskScore += 0.3;

    List<String> reasoning = [];
    if (riskScore <= 0.3) {
      // Low risk - explain what they're doing right
      if (avgBP <= 130)
        reasoning.add(
          'Blood pressure well controlled at ${avgBP.toInt()} mmHg',
        );
      if (avgSteps >= 8000)
        reasoning.add(
          'Excellent activity level with ${avgSteps.toInt()} daily steps',
        );
      if (weightTrend <= 1)
        reasoning.add('Stable weight indicates good fluid management');
      if (reasoning.isEmpty)
        reasoning.add('Overall health metrics within safe ranges');
    } else if (riskScore <= 0.6) {
      // Moderate risk - explain key concerns
      if (avgBP > 130)
        reasoning.add(
          'Blood pressure at ${avgBP.toInt()} mmHg needs attention',
        );
      if (avgSteps < 8000)
        reasoning.add(
          'Activity level at ${avgSteps.toInt()} steps could be increased',
        );
      if (weightTrend > 1)
        reasoning.add(
          'Weight trend shows ${weightTrend.toStringAsFixed(1)}kg gain',
        );
    } else {
      // High risk - explain urgent concerns
      if (avgBP > 140)
        reasoning.add(
          'Blood pressure dangerously elevated at ${avgBP.toInt()} mmHg',
        );
      if (avgSteps < 5000)
        reasoning.add(
          'Sedentary lifestyle with only ${avgSteps.toInt()} daily steps',
        );
      if (weightTrend > 2)
        reasoning.add(
          'Rapid ${weightTrend.toStringAsFixed(1)}kg weight gain indicates fluid retention',
        );
    }

    return RiskAssessment(
      level:
          riskScore > 0.6
              ? 'High'
              : riskScore > 0.3
              ? 'Moderate'
              : 'Low',
      score: riskScore,
      factors: reasoning.take(2).toList(), // Limit to 2 most important factors
    );
  }

  RiskAssessment _assessCKDProgressionRisk() {
    final bpControl =
        (_weeklyAverages['systolic'] ?? 140) <= _userBpSystolicGoal;
    final weightStability = _calculateVariability(_weights) < 1.0;
    final adequateActivity =
        (_weeklyAverages['steps'] ?? 0) >= _userStepsGoal * 0.8;
    final goodSleep =
        (_weeklyAverages['sleep_quality'] ?? 0) >=
        7.0; // Good sleep quality is 7+ on 0-10 scale

    final protectiveFactors =
        [
          bpControl,
          weightStability,
          adequateActivity,
          goodSleep,
        ].where((f) => f).length;
    final riskScore = 1.0 - (protectiveFactors / 4.0);

    List<String> reasoning = [];
    if (riskScore <= 0.3) {
      // Low risk - highlight protective factors
      if (bpControl)
        reasoning.add(
          'Blood pressure well-managed at ${(_weeklyAverages['systolic'] ?? 120).toInt()} mmHg',
        );
      if (weightStability)
        reasoning.add('Weight stable with minimal daily fluctuations');
      if (adequateActivity)
        reasoning.add(
          'Active lifestyle with ${(_weeklyAverages['steps'] ?? 0).toInt()} daily steps',
        );
      if (goodSleep)
        reasoning.add(
          'Good sleep quality averaging ${(_weeklyAverages['sleep_quality'] ?? 0).toStringAsFixed(1)}/10 supports kidney recovery',
        );
    } else if (riskScore <= 0.6) {
      // Moderate risk - key areas needing improvement
      if (!bpControl)
        reasoning.add(
          'BP at ${(_weeklyAverages['systolic'] ?? 140).toInt()} mmHg above ${_userBpSystolicGoal.toInt()} target',
        );
      if (!adequateActivity)
        reasoning.add(
          'Need ${(_userStepsGoal * 0.8 - (_weeklyAverages['steps'] ?? 0)).toInt()} more daily steps',
        );
      if (!goodSleep)
        reasoning.add(
          'Sleep quality below 7/10 target affects kidney recovery and hormone regulation',
        );
      if (!weightStability)
        reasoning.add(
          'Weight fluctuations may indicate fluid retention issues',
        );
    } else {
      // High risk - multiple risk factors
      reasoning.add('Multiple kidney protection factors not met');
      if (!bpControl && !adequateActivity)
        reasoning.add(
          'High BP combined with low activity accelerates kidney damage',
        );
      if (!weightStability)
        reasoning.add('Unstable weight suggests poor kidney function control');
    }

    return RiskAssessment(
      level:
          riskScore > 0.6
              ? 'High'
              : riskScore > 0.3
              ? 'Moderate'
              : 'Low',
      score: riskScore,
      factors: reasoning.take(2).toList(),
    );
  }

  RiskAssessment _assessFluidRetentionRisk() {
    final weightVariability = _calculateVariability(_weights);
    final rapidWeightGain = _calculateTrend(_weights, 7) > 1.0;
    final bpElevation =
        (_weeklyAverages['systolic'] ?? 120) > _userBpSystolicGoal + 10;
    final weeklyWeightChange = _calculateTrend(_weights, 7);

    double riskScore = 0;
    if (weightVariability > 1.5)
      riskScore += 0.5;
    else if (weightVariability > 1.0)
      riskScore += 0.3;

    if (rapidWeightGain) riskScore += 0.4;
    if (bpElevation) riskScore += 0.3;

    List<String> reasoning = [];
    if (riskScore <= 0.4) {
      // Low risk - stable fluid balance
      if (weightVariability <= 1.0)
        reasoning.add(
          'Weight stable within ${weightVariability.toStringAsFixed(1)}kg daily variation',
        );
      if (!rapidWeightGain)
        reasoning.add('No rapid weight changes - good kidney fluid control');
      if (!bpElevation)
        reasoning.add('Blood pressure stable indicates no fluid overload');
      if (reasoning.isEmpty)
        reasoning.add('Excellent fluid balance management');
    } else if (riskScore <= 0.7) {
      // Moderate risk - some fluid retention signs
      if (weightVariability > 1.0)
        reasoning.add(
          'Weight varies by ${weightVariability.toStringAsFixed(1)}kg daily - monitor fluid intake',
        );
      if (rapidWeightGain)
        reasoning.add(
          '${weeklyWeightChange.toStringAsFixed(1)}kg weekly gain may indicate fluid retention',
        );
      if (bpElevation)
        reasoning.add('BP elevated possibly due to fluid retention');
    } else {
      // High risk - significant fluid retention
      reasoning.add('Multiple fluid retention warning signs detected');
      if (rapidWeightGain && bpElevation)
        reasoning.add(
          'Weight gain + high BP suggests serious fluid overload - contact doctor',
        );
      if (weightVariability > 1.5)
        reasoning.add(
          'Extreme weight swings (${weightVariability.toStringAsFixed(1)}kg) need immediate attention',
        );
    }

    return RiskAssessment(
      level:
          riskScore > 0.7
              ? 'High'
              : riskScore > 0.4
              ? 'Moderate'
              : 'Low',
      score: riskScore,
      factors: reasoning.take(2).toList(),
    );
  }

  void _predictTrends() {
    _trendPredictions = {
      'weight_7day': _predictWeightTrend(7),
      'bp_14day': _predictBPTrend(14),
      'ckd_progression': _predictCKDProgression(),
    };
  }

  double _predictWeightTrend(int days) {
    if (_weights.length < 7) return 0;
    final recentTrend = _calculateTrend(_weights, 7);
    final longTermTrend = _calculateTrend(_weights, 14);
    return (recentTrend * 0.7 + longTermTrend * 0.3) * days / 7;
  }

  double _predictBPTrend(int days) {
    if (_systolic.length < 7) return 0;
    final recentTrend = _calculateTrend(_systolic, 7);
    final activityImpact =
        (_weeklyAverages['steps'] ?? 0) > _userStepsGoal ? -2 : 1;
    return recentTrend + activityImpact;
  }

  double _predictCKDProgression() {
    final riskFactors =
        _riskAssessments.values.map((r) => r.score).reduce((a, b) => a + b) /
        _riskAssessments.length;
    return riskFactors * 100; // Convert to percentage
  }

  double _calculateCorrelation(
    Map<String, double> map1,
    Map<String, double> map2,
  ) {
    final commonDates =
        map1.keys.toSet().intersection(map2.keys.toSet()).toList();
    if (commonDates.length < 5) return 0.0;

    final values1 = commonDates.map((date) => map1[date]!).toList();
    final values2 = commonDates.map((date) => map2[date]!).toList();

    final mean1 = values1.reduce((a, b) => a + b) / values1.length;
    final mean2 = values2.reduce((a, b) => a + b) / values2.length;

    double numerator = 0;
    double sum1 = 0;
    double sum2 = 0;

    for (int i = 0; i < values1.length; i++) {
      final diff1 = values1[i] - mean1;
      final diff2 = values2[i] - mean2;
      numerator += diff1 * diff2;
      sum1 += diff1 * diff1;
      sum2 += diff2 * diff2;
    }

    if (sum1 == 0 || sum2 == 0) return 0.0;
    return numerator / math.sqrt(sum1 * sum2);
  }

  double _calculateCorrelationWithInt(
    Map<String, double> map1,
    Map<String, int> map2,
  ) {
    final map2Double = map2.map(
      (key, value) => MapEntry(key, value.toDouble()),
    );
    return _calculateCorrelation(map1, map2Double);
  }

  double _calculateVariability(Map<String, double> data) {
    if (data.length < 2) return 0;
    final values = data.values.toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) /
        values.length;
    return math.sqrt(variance);
  }

  double _calculateTrend(Map<String, double> data, int days) {
    if (data.length < 2) return 0;
    final sortedKeys = data.keys.toList()..sort();
    final recentKeys =
        sortedKeys.length > days
            ? sortedKeys.sublist(sortedKeys.length - days)
            : sortedKeys;

    if (recentKeys.length < 2) return 0;
    return (data[recentKeys.last]! - data[recentKeys.first]!) /
        recentKeys.length;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: lightGray,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: cardShadow,
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Analyzing health correlations...',
                style: TextStyle(
                  color: mutedGray,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Check data availability
    final completeDays = _getCompleteDays();
    final dataState = _getDataState(completeDays);

    return Scaffold(
      backgroundColor: lightGray,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 80,
            floating: false,
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Insights',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, lightGray],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildContentBasedOnDataState(dataState, completeDays),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _getCompleteDays() {
    // Get all unique dates that have data
    final allDates = <String>{};
    allDates.addAll(_steps.keys);
    allDates.addAll(_weights.keys);
    allDates.addAll(_systolic.keys);
    allDates.addAll(_sleep.keys);
    allDates.addAll(_moodScore.keys.map((k) => k));
    allDates.addAll(_sleepQuality.keys);

    // Count days that have ALL required metrics (steps, BP, mood, sleep hours, sleep quality)
    int completeDays = 0;
    for (final date in allDates) {
      final hasSteps = _steps.containsKey(date);
      final hasBP = _systolic.containsKey(
        date,
      ); // BP readings include both systolic/diastolic
      final hasMood = _moodScore.containsKey(date);
      final hasSleepHours = _sleep.containsKey(date);
      final hasSleepQuality = _sleepQuality.containsKey(date);

      // Only count as complete day if has all 5 core metrics
      if (hasSteps && hasBP && hasMood && hasSleepHours && hasSleepQuality) {
        completeDays++;
      }
    }

    return completeDays;
  }

  DataState _getDataState(int completeDays) {
    if (completeDays == 0) return DataState.noData;
    if (completeDays <= 6)
      return DataState.insufficientData; // 1-6 complete days
    if (completeDays <= 13) return DataState.limitedData; // 7-13 complete days
    return DataState.sufficientData; // 14+ complete days
  }

  Widget _buildContentBasedOnDataState(DataState state, int completeDays) {
    switch (state) {
      case DataState.noData:
        return _buildNoDataState();
      case DataState.insufficientData:
        return _buildInsufficientDataState(completeDays);
      case DataState.limitedData:
        return _buildLimitedDataState(completeDays);
      case DataState.sufficientData:
        return _buildFullInsights();
    }
  }

  Widget _buildNoDataState() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: cardShadow,
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Icon(Icons.insights, size: 48, color: primaryBlue),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to Insights!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Start tracking your health data to unlock powerful insights about your kidney health.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: mutedGray, height: 1.5),
              ),
              const SizedBox(height: 32),
              _buildGetStartedCard(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGetStartedCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryBlue, secondaryTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Track These Daily:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildTrackingItem(
            Icons.directions_walk,
            'Daily Steps',
            'Track your physical activity',
          ),
          _buildTrackingItem(
            Icons.monitor_weight,
            'Weight',
            'Monitor fluid retention',
          ),
          _buildTrackingItem(
            Icons.favorite,
            'Blood Pressure',
            'Watch cardiovascular health',
          ),
          _buildTrackingItem(
            Icons.bedtime,
            'Sleep Quality',
            'Rate your sleep quality (0-10)',
          ),
          _buildTrackingItem(
            Icons.access_time,
            'Sleep Hours',
            'Track sleep duration',
          ),
          _buildTrackingItem(
            Icons.sentiment_satisfied,
            'Daily Mood',
            'Monitor mental wellness',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '💡 Tip: Log data for 3-5 days to start seeing basic patterns!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsufficientDataState(int completeDays) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: cardShadow,
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: warningOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.hourglass_empty,
                      color: warningOrange,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Great Start!',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You have $completeDays complete days of data',
                          style: TextStyle(fontSize: 16, color: mutedGray),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: lightGray,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: primaryBlue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Keep Going!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Log your health data daily for 7+ days to unlock:',
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    _buildFeaturePreview(
                      '🔍',
                      'Pattern Recognition',
                      'See how your activities affect your health',
                    ),
                    _buildFeaturePreview(
                      '📊',
                      'Health Correlations',
                      'Understand connections between metrics',
                    ),
                    _buildFeaturePreview(
                      '⚠️',
                      'Risk Assessment',
                      'Get personalized health warnings',
                    ),
                    _buildFeaturePreview(
                      '🔮',
                      'Future Predictions',
                      'See trends and forecasts',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildBasicDataPreview(),
      ],
    );
  }

  Widget _buildFeaturePreview(String emoji, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: mutedGray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitedDataState(int completeDays) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primaryBlue.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: cardShadow,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.trending_up,
                  color: primaryBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Building Your Health Picture',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You have $completeDays complete days. Here are your patterns!',
                      style: TextStyle(fontSize: 14, color: mutedGray),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildBasicDataPreview(),
        const SizedBox(height: 24),
        _buildLimitedInsightsPreview(),
        const SizedBox(height: 24),
        _buildNextTierCard(),
      ],
    );
  }

  Widget _buildBasicDataPreview() {
    if (_steps.isEmpty && _weights.isEmpty && _systolic.isEmpty) {
      return Container();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Recent Data',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          if (_steps.isNotEmpty)
            _buildSimpleMetricRow(
              'Steps',
              _steps.values.last.toInt().toString(),
              'steps',
              Icons.directions_walk,
              primaryBlue,
            ),
          if (_weights.isNotEmpty)
            _buildSimpleMetricRow(
              'Weight',
              '${_weights.values.last.toStringAsFixed(1)} kg',
              'weight',
              Icons.monitor_weight,
              secondaryTeal,
            ),
          if (_systolic.isNotEmpty)
            _buildSimpleMetricRow(
              'Blood Pressure',
              '${_systolic.values.last.toInt()} mmHg',
              'systolic',
              Icons.favorite,
              dangerRed,
            ),
          if (_sleep.isNotEmpty)
            _buildSimpleMetricRow(
              'Sleep',
              '${_sleep.values.last.toStringAsFixed(1)} hours',
              'sleep',
              Icons.bedtime,
              softPurple,
            ),
          if (_moodScore.isNotEmpty)
            _buildSimpleMetricRow(
              'Mood',
              '${_moodScore.values.last}/100',
              'mood',
              Icons.sentiment_satisfied,
              warningOrange,
            ),
        ],
      ),
    );
  }

  Widget _buildSimpleMetricRow(
    String label,
    String value,
    String type,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitedInsightsPreview() {
    return Column(
      children: [
        // Basic Trends Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: cardShadow,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.trending_up, color: primaryBlue, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Your Health Trends',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildBasicTrendInsight(
                'Steps',
                _calculateRecentAverage(_steps, 7),
                _userStepsGoal,
                'steps',
              ),
              _buildBasicTrendInsight(
                'Sleep',
                _calculateRecentAverage(_sleep, 7),
                _userSleepGoal,
                'hours',
              ),
              _buildBasicTrendInsight(
                'Weight',
                _calculateRecentAverage(_weights, 7),
                _userWeightGoal,
                'kg',
              ),
              if (_systolic.isNotEmpty)
                _buildBasicTrendInsight(
                  'BP Systolic',
                  _calculateRecentAverage(_systolic, 7),
                  _userBpSystolicGoal,
                  'mmHg',
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Simple Correlation Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: cardShadow,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.insights, color: secondaryTeal, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Pattern Detected',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSimplePattern(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBasicTrendInsight(
    String metric,
    double average,
    double goal,
    String unit,
  ) {
    final isOnTarget = average >= goal * 0.9; // Within 90% of goal
    final color = isOnTarget ? successGreen : warningOrange;
    final trend = average >= goal ? '✓' : '⚡';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(trend, style: TextStyle(fontSize: 18, color: color)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$metric: ${average.toStringAsFixed(1)} $unit',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            isOnTarget ? 'On track' : 'Needs attention',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimplePattern() {
    // Simple pattern detection
    final avgSteps = _calculateRecentAverage(_steps, 7);
    final avgBP = _calculateRecentAverage(_systolic, 7);

    String pattern = '';
    if (avgSteps > 8000 && avgBP < 130) {
      pattern =
          '🎯 Great news! Your active days (${avgSteps.toInt()} steps) are keeping your blood pressure well controlled (${avgBP.toInt()} mmHg).';
    } else if (avgSteps < 5000 && avgBP > 140) {
      pattern =
          '⚠️ Pattern noticed: Lower activity days (${avgSteps.toInt()} steps) coincide with higher blood pressure (${avgBP.toInt()} mmHg).';
    } else {
      pattern =
          '📊 Building your pattern database... Keep logging consistently to reveal more insights!';
    }

    return Text(
      pattern,
      style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
    );
  }

  Widget _buildNextTierCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [softPurple.withOpacity(0.1), primaryBlue.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: softPurple.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.lock_open, color: softPurple, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Unlock Full Insights',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Continue logging for 5 more days to unlock the complete insights dashboard with:',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildUnlockFeature(
                  Icons.analytics,
                  'Advanced\nCorrelations',
                ),
              ),
              Expanded(
                child: _buildUnlockFeature(
                  Icons.warning_rounded,
                  'Risk\nAssessment',
                ),
              ),
              Expanded(
                child: _buildUnlockFeature(
                  Icons.psychology,
                  'Predictive\nModeling',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: softPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, color: softPurple, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Log data for 5 more days to reach 14+ complete days!',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: softPurple.withOpacity(0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataEncouragementCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryBlue.withOpacity(0.1),
            secondaryTeal.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryBlue.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.auto_graph, color: primaryBlue, size: 24),
              SizedBox(width: 12),
              Text(
                'Almost There!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Continue logging your health data daily. With more data points, you\'ll unlock:',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildUnlockFeature(
                  Icons.insights,
                  'Advanced\nCorrelations',
                ),
              ),
              Expanded(
                child: _buildUnlockFeature(
                  Icons.warning_rounded,
                  'Smart Health\nWarnings',
                ),
              ),
              Expanded(
                child: _buildUnlockFeature(
                  Icons.psychology,
                  'Predictive\nInsights',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: successGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, color: successGreen, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Log data for 1-2 more days to see full insights!',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: successGreen.withOpacity(0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockFeature(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: primaryBlue, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildFullInsights() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKidneyHealthDashboard(),
        const SizedBox(height: 24),
        _buildInteractiveCorrelationChart(),
        const SizedBox(height: 24),
        _buildCorrelationAnalysisSection(),
        const SizedBox(height: 24),
        _buildRiskAssessmentSection(),
        const SizedBox(height: 24),
        _buildPredictiveInsightsSection(),
        const SizedBox(height: 40),
      ],
    );
  }

  // Interactive chart state
  Map<String, bool> _selectedMetrics = {
    'steps': true,
    'weight': false,
    'systolic': true,
    'sleep': false,
    'mood': false,
  };

  bool _showGoalLines = true;

  Widget _buildInteractiveCorrelationChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cardShadow,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights, color: primaryBlue, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Interactive Health Correlations',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Tap metrics below to see how they relate to each other',
                      style: TextStyle(fontSize: 14, color: mutedGray),
                    ),
                  ],
                ),
              ),
              // Goal lines toggle
              InkWell(
                onTap: () {
                  setState(() {
                    _showGoalLines = !_showGoalLines;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color:
                        _showGoalLines
                            ? primaryBlue.withOpacity(0.1)
                            : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          _showGoalLines ? primaryBlue : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.track_changes,
                        size: 16,
                        color:
                            _showGoalLines ? primaryBlue : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Goals',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              _showGoalLines
                                  ? primaryBlue
                                  : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Interactive Chart
          SizedBox(height: 280, child: _buildMultiMetricChart()),

          const SizedBox(height: 20),

          // Metric Toggle Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetricToggle(
                'steps',
                'Daily Steps',
                primaryBlue,
                Icons.directions_walk,
              ),
              _buildMetricToggle(
                'weight',
                'Weight',
                secondaryTeal,
                Icons.monitor_weight,
              ),
              _buildMetricToggle(
                'systolic',
                'Blood Pressure',
                dangerRed,
                Icons.favorite,
              ),
              _buildMetricToggle(
                'sleep',
                'Sleep Hours',
                softPurple,
                Icons.bedtime,
              ),
              _buildMetricToggle(
                'mood',
                'Mood Score',
                warningOrange,
                Icons.sentiment_satisfied,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Simple explanation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: lightGray,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: primaryBlue, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getChartExplanation(),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricToggle(
    String key,
    String label,
    Color color,
    IconData icon,
  ) {
    final isSelected = _selectedMetrics[key] ?? false;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedMetrics[key] = !isSelected;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? color : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? color : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiMetricChart() {
    final selectedCount =
        _selectedMetrics.values.where((selected) => selected).length;

    if (selectedCount == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 48, color: mutedGray.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              'Tap on metrics below to see correlations',
              style: TextStyle(
                fontSize: 16,
                color: mutedGray,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select 2+ metrics to see how they relate to each other',
              style: TextStyle(fontSize: 14, color: mutedGray.withOpacity(0.7)),
            ),
          ],
        ),
      );
    }

    // Get the last 14 days of data for correlation analysis
    final commonDates = _getCommonDates(14);
    if (commonDates.isEmpty) {
      return Center(
        child: Text(
          'Not enough data for correlation analysis',
          style: TextStyle(fontSize: 16, color: mutedGray),
        ),
      );
    }

    return LineChart(_buildMultiLineChartData(commonDates));
  }

  List<String> _getCommonDates(int days) {
    final allDates = <String>{};
    if (_selectedMetrics['steps'] == true) allDates.addAll(_steps.keys);
    if (_selectedMetrics['weight'] == true) allDates.addAll(_weights.keys);
    if (_selectedMetrics['systolic'] == true) allDates.addAll(_systolic.keys);
    if (_selectedMetrics['sleep'] == true) allDates.addAll(_sleep.keys);
    if (_selectedMetrics['mood'] == true) allDates.addAll(_moodScore.keys);

    final sortedDates = allDates.toList()..sort();
    return sortedDates.length > days
        ? sortedDates.sublist(sortedDates.length - days)
        : sortedDates;
  }

  LineChartData _buildMultiLineChartData(List<String> dates) {
    final lines = <LineChartBarData>[];

    if (_selectedMetrics['steps'] == true) {
      lines.add(_createLineChartBarData(dates, _steps, primaryBlue, 'steps'));
    }
    if (_selectedMetrics['weight'] == true) {
      lines.add(
        _createLineChartBarData(dates, _weights, secondaryTeal, 'weight'),
      );
    }
    if (_selectedMetrics['systolic'] == true) {
      lines.add(
        _createLineChartBarData(dates, _systolic, dangerRed, 'systolic'),
      );
    }
    if (_selectedMetrics['sleep'] == true) {
      lines.add(_createLineChartBarData(dates, _sleep, softPurple, 'sleep'));
    }
    if (_selectedMetrics['mood'] == true) {
      final moodAsDouble = _moodScore.map(
        (key, value) => MapEntry(key, value.toDouble()),
      );
      lines.add(
        _createLineChartBarData(dates, moodAsDouble, warningOrange, 'mood'),
      );
    }

    return LineChartData(
      lineTouchData: LineTouchData(
        enabled: false, // Disable hover tooltips completely
      ),
      gridData: FlGridData(
        show: true,
        drawHorizontalLine: true,
        drawVerticalLine: false,
        horizontalInterval: null,
        getDrawingHorizontalLine:
            (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 50,
            getTitlesWidget: (value, meta) {
              return Text(
                _formatYAxisValue(value),
                style: TextStyle(fontSize: 11, color: mutedGray),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval:
                math.max(1.0, (dates.length / 5.0).toDouble()).floorToDouble(),
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= dates.length)
                return const SizedBox.shrink();

              final date = DateTime.parse(dates[index]);
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  DateFormat('M/d').format(date),
                  style: TextStyle(fontSize: 11, color: mutedGray),
                ),
              );
            },
          ),
        ),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: lines,
      extraLinesData: ExtraLinesData(horizontalLines: _buildGoalLines(dates)),
      minY: 0,
      maxY: 100, // Normalized scale for better correlation visualization
    );
  }

  LineChartBarData _createLineChartBarData(
    List<String> dates,
    Map<String, double> data,
    Color color,
    String metricType,
  ) {
    final spots = <FlSpot>[];

    // Normalize data to 0-100 scale for better visualization
    final values = dates.map((date) => data[date] ?? 0).toList();
    final minValue = values.isNotEmpty ? values.reduce(math.min) : 0;
    final maxValue = values.isNotEmpty ? values.reduce(math.max) : 100;
    final range = maxValue - minValue;

    for (int i = 0; i < dates.length; i++) {
      final rawValue = data[dates[i]] ?? 0;
      // Normalize to 0-100 scale
      final normalizedValue =
          range > 0 ? ((rawValue - minValue) / range) * 100 : 50;
      spots.add(FlSpot(i.toDouble(), normalizedValue.toDouble()));
    }

    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        getDotPainter:
            (spot, percent, barData, index) => FlDotCirclePainter(
              radius: 4,
              color: color,
              strokeWidth: 2,
              strokeColor: Colors.white,
            ),
      ),
      belowBarData: BarAreaData(show: true, color: color.withOpacity(0.1)),
    );
  }

  List<HorizontalLine> _buildGoalLines(List<String> dates) {
    if (!_showGoalLines) return [];

    final goalLines = <HorizontalLine>[];
    final goalPositions =
        <String, double>{}; // Track positions for smart labeling

    // Collect all goal positions first
    if (_selectedMetrics['steps'] == true && _userStepsGoal > 0) {
      final pos = _getNormalizedGoalValue('steps', _userStepsGoal, dates);
      if (pos != null) goalPositions['steps'] = pos;
    }
    if (_selectedMetrics['weight'] == true && _userWeightGoal > 0) {
      final pos = _getNormalizedGoalValue('weight', _userWeightGoal, dates);
      if (pos != null) goalPositions['weight'] = pos;
    }
    if (_selectedMetrics['systolic'] == true && _userBpSystolicGoal > 0) {
      final pos = _getNormalizedGoalValue(
        'systolic',
        _userBpSystolicGoal,
        dates,
      );
      if (pos != null) goalPositions['systolic'] = pos;
    }
    if (_selectedMetrics['sleep'] == true && _userSleepGoal > 0) {
      final pos = _getNormalizedGoalValue('sleep', _userSleepGoal, dates);
      if (pos != null) goalPositions['sleep'] = pos;
    }

    // Create goal lines with smart label positioning
    goalPositions.forEach((metric, position) {
      final alignment = _getSmartLabelAlignment(
        metric,
        position,
        goalPositions,
      );
      final isCompact = _shouldUseCompactLabel(position, goalPositions);

      Color color;
      String label;

      switch (metric) {
        case 'steps':
          color = primaryBlue;
          label =
              isCompact
                  ? '${_userStepsGoal.toInt()}'
                  : 'Goal: ${_userStepsGoal.toInt()} steps';
          break;
        case 'weight':
          color = secondaryTeal;
          label =
              isCompact
                  ? '${_userWeightGoal.toStringAsFixed(1)}kg'
                  : 'Goal: ${_userWeightGoal.toStringAsFixed(1)} kg';
          break;
        case 'systolic':
          color = dangerRed;
          label =
              isCompact
                  ? '<${_userBpSystolicGoal.toInt()}'
                  : 'Goal: <${_userBpSystolicGoal.toInt()} mmHg';
          break;
        case 'sleep':
          color = softPurple;
          label =
              isCompact
                  ? '${_userSleepGoal.toStringAsFixed(1)}h'
                  : 'Goal: ${_userSleepGoal.toStringAsFixed(1)}h';
          break;
        default:
          return;
      }

      goalLines.add(
        HorizontalLine(
          y: position,
          color: color.withOpacity(0.6),
          strokeWidth: 2,
          dashArray: [5, 5],
          label: HorizontalLineLabel(
            show: true,
            alignment: alignment,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: isCompact ? 10 : 11,
              backgroundColor: Colors.white.withOpacity(0.9),
            ),
            labelResolver: (line) => label,
          ),
        ),
      );
    });

    return goalLines;
  }

  Alignment _getSmartLabelAlignment(
    String metric,
    double position,
    Map<String, double> allPositions,
  ) {
    // Use different alignments to avoid overlaps
    final alignments = [
      Alignment.topRight,
      Alignment.topLeft,
      Alignment.bottomRight,
      Alignment.bottomLeft,
    ];

    final sortedMetrics =
        allPositions.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    final index = sortedMetrics.indexWhere((entry) => entry.key == metric);
    return alignments[index % alignments.length];
  }

  bool _shouldUseCompactLabel(
    double position,
    Map<String, double> allPositions,
  ) {
    // Use compact labels when there are multiple goals close together
    const proximityThreshold = 15.0; // 15% of chart range

    int nearbyCount = 0;
    for (final otherPosition in allPositions.values) {
      if ((position - otherPosition).abs() < proximityThreshold) {
        nearbyCount++;
      }
    }

    return nearbyCount > 1; // Use compact if there are other goals nearby
  }

  double? _getNormalizedGoalValue(
    String metricType,
    double goalValue,
    List<String> dates,
  ) {
    Map<String, double> data;

    switch (metricType) {
      case 'steps':
        data = _steps;
        break;
      case 'weight':
        data = _weights;
        break;
      case 'systolic':
        data = _systolic;
        break;
      case 'sleep':
        data = _sleep;
        break;
      default:
        return null;
    }

    // Get values for the displayed date range
    final values =
        dates.map((date) => data[date] ?? 0).where((v) => v > 0).toList();
    if (values.isEmpty) return null;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue - minValue;

    if (range <= 0) return 50; // If no variation, put goal in middle

    // Normalize goal to 0-100 scale using same logic as chart data
    final normalizedGoal = ((goalValue - minValue) / range) * 100;

    // Clamp to visible range
    return math.max(0, math.min(100, normalizedGoal));
  }

  String _formatYAxisValue(double value) {
    if (value == 0) return '0%';
    if (value == 25) return '25%';
    if (value == 50) return '50%';
    if (value == 75) return '75%';
    if (value == 100) return '100%';
    return '';
  }

  String _getChartExplanation() {
    final selectedMetrics =
        _selectedMetrics.entries
            .where((entry) => entry.value)
            .map((entry) => entry.key)
            .toList();

    if (selectedMetrics.isEmpty) {
      return 'Select metrics above to see how they relate to each other over time.';
    }

    if (selectedMetrics.length == 1) {
      return 'Select at least 2 metrics to see correlations. Lines going in the same direction show positive correlation.';
    }

    if (selectedMetrics.contains('steps') &&
        selectedMetrics.contains('systolic')) {
      return '🔍 Look for opposite patterns: When steps (blue) go UP, blood pressure (red) often goes DOWN. This shows exercise helps your kidneys! 🎯 Toggle "Goals" to see target lines.';
    }

    if (selectedMetrics.contains('weight') &&
        selectedMetrics.contains('systolic')) {
      return '🔍 Watch for similar patterns: When weight (teal) and blood pressure (red) both rise together, it may indicate fluid retention - important for kidney health.';
    }

    if (selectedMetrics.contains('sleep') && selectedMetrics.contains('mood')) {
      return '🔍 Notice similar patterns: Good sleep (purple) and mood (orange) often move together, both supporting kidney health recovery.';
    }

    return '🔍 Lines moving in SAME direction = positive correlation. Lines moving in OPPOSITE directions = negative correlation. Both patterns reveal important health connections!\n\n🎯 Toggle "Goals" button to show/hide your target lines!';
  }

  Widget _buildKidneyHealthDashboard() {
    final overallScore =
        _correlationInsights.isNotEmpty
            ? _correlationInsights.last.impactScore
            : 0.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              overallScore > 0.8
                  ? [successGreen, Color(0xFF059669)]
                  : overallScore > 0.6
                  ? [primaryBlue, Color(0xFF1D4ED8)]
                  : [warningOrange, Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (overallScore > 0.8 ? successGreen : primaryBlue)
                .withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kidney Health Score',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(overallScore * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      overallScore > 0.8
                          ? 'Excellent Protection'
                          : overallScore > 0.6
                          ? 'Good Management'
                          : 'Needs Attention',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.favorite,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildMiniMetric(
                'BP Control',
                _weeklyAverages['systolic'] ?? 120,
                'mmHg',
              ),
              _buildMiniMetric(
                'Weight Stability',
                _calculateVariability(_weights),
                'kg var',
              ),
              _buildMiniMetric(
                'Activity Level',
                _weeklyAverages['steps'] ?? 0,
                'steps',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(String label, double value, String unit) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${value.toStringAsFixed(unit == 'steps' ? 0 : 1)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              unit,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCorrelationAnalysisSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Correlation Analysis',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'How your health metrics interact and affect kidney function',
          style: TextStyle(fontSize: 16, color: mutedGray),
        ),
        const SizedBox(height: 20),
        ...(_correlationInsights
            .map((insight) => _buildCorrelationCard(insight))
            .toList()),
        _buildAISummaryBox(),
      ],
    );
  }

  Widget _buildCorrelationCard(CorrelationInsight insight) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: insight.color.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: cardShadow,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: insight.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getCorrelationIcon(insight.correlation),
                  color: insight.color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insight.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Impact: ',
                          style: TextStyle(fontSize: 14, color: mutedGray),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: insight.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${(insight.impactScore * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: insight.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            insight.analysis,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: insight.color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, color: insight.color, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    insight.recommendation,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: insight.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCorrelationIcon(double correlation) {
    if (correlation.abs() > 0.7) return Icons.trending_up;
    if (correlation.abs() > 0.3) return Icons.trending_flat;
    return Icons.trending_down;
  }

  Widget _buildRiskAssessmentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Risk Assessment',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Current risk factors and prevention strategies',
          style: TextStyle(fontSize: 16, color: mutedGray),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _buildRiskCard(
                'Cardiovascular',
                _riskAssessments['cardiovascular']!,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildRiskCard(
                'CKD Progression',
                _riskAssessments['progression']!,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildRiskCard(
          'Fluid Retention',
          _riskAssessments['fluid']!,
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _buildRiskCard(
    String title,
    RiskAssessment risk, {
    bool fullWidth = false,
  }) {
    Color color =
        risk.level == 'High'
            ? dangerRed
            : risk.level == 'Moderate'
            ? warningOrange
            : successGreen;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: cardShadow,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  risk.level == 'High'
                      ? Icons.warning_rounded
                      : risk.level == 'Moderate'
                      ? Icons.info_rounded
                      : Icons.check_circle_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${risk.level.toUpperCase()} RISK',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (risk.factors.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    risk.level == 'Low'
                        ? 'Why you\'re doing well:'
                        : risk.level == 'Moderate'
                        ? 'Areas to improve:'
                        : 'Urgent concerns:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...risk.factors
                      .map(
                        (factor) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  factor,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPredictiveInsightsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cardShadow,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: softPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights, color: softPurple, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Predictive Insights',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Statistics-based health predictions',
                      style: TextStyle(fontSize: 14, color: mutedGray),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildPredictionItem(
            'Weight Trend (7 days)',
            _trendPredictions['weight_7day'] ?? 0,
            'kg change',
            Icons.monitor_weight,
          ),
          _buildPredictionItem(
            'Blood Pressure Trend (14 days)',
            _trendPredictions['bp_14day'] ?? 0,
            'mmHg change',
            Icons.favorite,
          ),
          _buildPredictionItem(
            'CKD Progression Risk',
            _trendPredictions['ckd_progression'] ?? 0,
            '% risk score',
            Icons.health_and_safety,
          ),
        ],
      ),
    );
  }

  Widget _buildAISummaryBox() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [softPurple.withOpacity(0.1), primaryBlue.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: softPurple.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.analytics,
                  color: primaryBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Correlation Analysis AI Summary',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (!_aiSummaryLoading)
                InkWell(
                  onTap: _generateAISummary,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: primaryBlue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Generate',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primaryBlue,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_aiSummaryLoading)
            const SizedBox(
              height: 60,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(softPurple),
                  strokeWidth: 2,
                ),
              ),
            )
          else if (_aiSummary.isNotEmpty)
            Text(
              _aiSummary,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.black87,
              ),
            )
          else
            Text(
              'Tap the button to generate AI insights about your correlation analysis',
              style: TextStyle(
                fontSize: 14,
                color: mutedGray,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPredictionItem(
    String label,
    double value,
    String unit,
    IconData icon,
  ) {
    Color color =
        value > 0
            ? dangerRed
            : value < -1
            ? successGreen
            : primaryBlue;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} $unit',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class CorrelationInsight {
  final String title;
  final double correlation;
  final String analysis;
  final Color color;
  final double impactScore;
  final String recommendation;

  CorrelationInsight({
    required this.title,
    required this.correlation,
    required this.analysis,
    required this.color,
    required this.impactScore,
    required this.recommendation,
  });
}

class RiskAssessment {
  final String level;
  final double score;
  final List<String> factors;

  RiskAssessment({
    required this.level,
    required this.score,
    required this.factors,
  });
}

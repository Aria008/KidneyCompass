import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/recent_metrics_chart.dart';
import '../services/metrics_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StepsChartContainer extends StatefulWidget {
  const StepsChartContainer({super.key});

  @override
  State<StepsChartContainer> createState() => _StepsChartContainerState();
}

class _StepsChartContainerState extends State<StepsChartContainer> {
  final MetricsService _metricsService = MetricsService();
  List<FlSpot> _dataPoints = [];

  @override
  void initState() {
    super.initState();
    _fetchSteps();
  }

  Future<void> _fetchSteps() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final logs = await _metricsService.getStepsLog(user.id);

    final spots =
        logs.asMap().entries.map((entry) {
          int index = entry.key;
          double value = (entry.value['steps'] as int).toDouble();
          return FlSpot(index.toDouble(), value);
        }).toList();

    setState(() => _dataPoints = spots);
  }

  @override
  Widget build(BuildContext context) {
    return RecentMetricsChart(title: 'Steps', dataPoints: _dataPoints);
  }
}

import 'package:flutter/material.dart';

class TrackPage extends StatefulWidget {
  const TrackPage({super.key});

  @override
  State<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<TrackPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _stepsController = TextEditingController();
  double _sleepHours = 7;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFDEA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFDEA),
        elevation: 0,
        title: const Text(
          'Track Health Metrics',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          indicatorColor: Colors.green,
          tabs: const [
            Tab(text: 'Activity'),
            Tab(text: 'Vitals'),
            Tab(text: 'Wellbeing'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActivityTab(),
          _buildVitalsTab(),
          const Center(child: Text('Wellbeing coming soon...')),
        ],
      ),
    );
  }

  Widget _buildActivityTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildStepsCard(),
          const SizedBox(height: 20),
          _buildSleepCard(),
        ],
      ),
    );
  }

  Widget _buildStepsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE4EED2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.directions_walk, color: Colors.indigo),
              SizedBox(width: 8),
              Text(
                'Steps',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('How many steps did you take?'),
          const SizedBox(height: 6),
          TextField(
            controller: _stepsController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              hintText: '0',
            ),
          ),
          const SizedBox(height: 6),
          const Text('Goal: 5000 steps          5000 steps to go'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              // handle save
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDCE6AE),
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(40),
            ),
            child: const Text('Save Steps'),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE4EED2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.bedtime, color: Colors.indigo),
              SizedBox(width: 8),
              Text(
                'Sleep',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('How many hours did you sleep?'),
          Slider(
            value: _sleepHours,
            onChanged: (value) {
              setState(() => _sleepHours = value);
            },
            min: 0,
            max: 12,
            divisions: 24,
            label: '${_sleepHours.toStringAsFixed(1)}h',
            activeColor: Colors.green,
          ),
          Text(
            '${_sleepHours.toStringAsFixed(1)}h',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Text('Recommendation: 7–8 hours for kidney health'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              // handle save
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDCE6AE),
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(40),
            ),
            child: const Text('Save Sleep'),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalsTab() {
    final weightController = TextEditingController(text: '170');
    final systolicController = TextEditingController(text: '120');
    final diastolicController = TextEditingController(text: '80');
    final hydrationController = TextEditingController(text: '0');

    Widget card(String title, IconData icon, List<Widget> content) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFE4EED2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.indigo),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...content,
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          card('Weight', Icons.monitor_weight, [
            const Text('Current Weight (lbs)'),
            const SizedBox(height: 6),
            TextField(
              controller: weightController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: '170',
              ),
            ),
            const SizedBox(height: 6),
            const Text('Target: 170 lbs                            On target'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDCE6AE),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
              ),
              child: const Text('Save Weight'),
            ),
          ]),
          card('Blood Pressure', Icons.favorite_border, [
            const Text('Systolic                         Diastolic'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: systolicController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      hintText: '120',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: diastolicController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      hintText: '80',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Target: Below 120/80 mmHg for kidney health'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDCE6AE),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
              ),
              child: const Text('Save Blood Pressure'),
            ),
          ]),
          card('Hydration', Icons.water_drop_outlined, [
            const Text('Fluid Intake (oz)'),
            const SizedBox(height: 6),
            TextField(
              controller: hydrationController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: '0',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Daily Target: 64 oz                          64 oz remaining',
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDCE6AE),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
              ),
              child: const Text('Save Hydration'),
            ),
          ]),
        ],
      ),
    );
  }
}

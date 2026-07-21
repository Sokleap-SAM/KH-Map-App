import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin_dashboard.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';

/// Admin home: live/simulation mode badge + aggregate counts from
/// GET /transit/admin/dashboard. Day/Week/Month/Year tabs re-query the
/// window-bound ("in period") counts; the live fleet counts are period-
/// independent and stay put.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminService _service = AdminService();

  AdminDashboard? _data;
  bool _loading = true;
  String? _error;
  DashboardPeriod _period = DashboardPeriod.day;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await _service.fetchDashboard(_period);
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AdminApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  void _selectPeriod(DashboardPeriod p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(t.adminDashboardTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(t),
    );
  }

  Widget _buildBody(AppTexts t) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: Text(t.tryAgain),
              ),
            ],
          ),
        ),
      );
    }

    final data = _data!;
    final cur = data.current;
    final inP = data.inPeriod;

    final liveCards = <_Metric>[
      _Metric('ផ្លូវ', 'Routes', cur.routes, Icons.route),
      _Metric('ផ្លូវសកម្ម', 'Active routes', cur.activeRoutes, Icons.alt_route),
      _Metric('ចំណត', 'Stops', cur.stops, Icons.place),
      _Metric('រថយន្តក្រុង', 'Buses', cur.buses, Icons.directions_bus),
      _Metric('អ្នកបើកបរ', 'Drivers', cur.drivers, Icons.badge),
      _Metric('កំពុងបម្រើ', 'On shift', cur.driversOnShift, Icons.how_to_reg),
      _Metric('ដំណើរសកម្ម', 'Active trips', cur.activeTrips, Icons.play_circle),
      _Metric('បានកំណត់ពេល', 'Scheduled', cur.scheduledTrips, Icons.schedule),
    ];

    final periodCards = <_Metric>[
      _Metric('ដំណើរសរុប', 'Trips', inP.trips, Icons.directions),
      _Metric('បានបញ្ចប់', 'Completed', inP.completedTrips, Icons.check_circle),
      _Metric('បានលុបចោល', 'Cancelled', inP.cancelledTrips, Icons.cancel),
      _Metric('ផ្លូវថ្មី', 'New routes', inP.newRoutes, Icons.add_road),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _modeBanner(data),
          const SizedBox(height: 16),
          _periodTabs(),
          const SizedBox(height: 4),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          const SizedBox(height: 12),
          _sectionHeader(t.currentStatus, null),
          const SizedBox(height: 8),
          _grid(liveCards),
          const SizedBox(height: 20),
          _sectionHeader(t.overPeriod, _windowLabel(data)),
          const SizedBox(height: 8),
          _grid(periodCards),
        ],
      ),
    );
  }

  Widget _periodTabs() {
    final lang = context.watch<SettingsProvider>().languageCode;
    return Row(
      children: [
        for (final p in DashboardPeriod.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _PeriodTab(
                label: p.label(lang),
                selected: p == _period,
                onTap: () => _selectPeriod(p),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionHeader(String title, String? subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ),
      ],
    );
  }

  Widget _grid(List<_Metric> cards) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: cards.map((m) => _MetricCard(metric: m)).toList(),
    );
  }

  String? _windowLabel(AdminDashboard data) {
    final s = data.windowStart;
    final e = data.windowEnd;
    if (s == null || e == null) return null;
    String d(DateTime t) =>
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final from = d(s);
    final to = d(e);
    return from == to ? from : '$from → $to';
  }

  Widget _modeBanner(AdminDashboard data) {
    final t = context.watch<SettingsProvider>().t;
    final sim = data.isSimulation;
    final color = sim ? Colors.orange : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        children: [
          Icon(sim ? Icons.science_outlined : Icons.sensors, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sim ? t.simulated : t.live,
                  style: TextStyle(
                    color: color.shade800,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  t.systemMode,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryColor : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primaryColor : Colors.black26,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _Metric {
  final String labelKm;
  final String labelEn;
  final int value;
  final IconData icon;
  const _Metric(this.labelKm, this.labelEn, this.value, this.icon);
}

class _MetricCard extends StatelessWidget {
  final _Metric metric;
  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metric.icon, color: AppColors.primaryColor, size: 20),
              const Spacer(),
              Text(
                '${metric.value}',
                style: const TextStyle(
                  color: AppColors.primaryColor,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            context.watch<SettingsProvider>().languageCode == 'en'
                ? metric.labelEn
                : metric.labelKm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

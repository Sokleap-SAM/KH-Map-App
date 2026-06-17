import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/trip.dart';
import '../../providers/driver_provider.dart';
import '../../utils/constants/colors.dart';
import 'driver_trip_detail_screen.dart';

class DriverTripsScreen extends StatefulWidget {
  const DriverTripsScreen({super.key});

  @override
  State<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends State<DriverTripsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DriverProvider>().refreshTrips();
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'in-progress':
        return Colors.green;
      case 'scheduled':
        return Colors.blue;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.black54;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DriverProvider>();
    final today = d.today;
    final history = d.history;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('ដំណើរ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: d.loadingTrips
                ? null
                : () => context.read<DriverProvider>().refreshTrips(),
          ),
        ],
      ),
      body: d.loadingTrips && d.allTrips.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => context.read<DriverProvider>().refreshTrips(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (d.profile?.hasAssignedBus != true)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Contact admin — your bus assignment is missing.',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  if (today.isNotEmpty) ...[
                    const _SectionHeader(title: 'ថ្ងៃនេះ'),
                    for (final t in today)
                      _TripCard(
                        trip: t,
                        title: d.routeTitle(t),
                        busNumber: d.busNumberOf(t),
                        statusColor: _statusColor(t.status),
                      ),
                  ],
                  if (history.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const _SectionHeader(title: 'ប្រវត្តិ'),
                    for (final t in history)
                      _TripCard(
                        trip: t,
                        title: d.routeTitle(t),
                        busNumber: d.busNumberOf(t),
                        statusColor: _statusColor(t.status),
                      ),
                  ],
                  if (today.isEmpty && history.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text('មិនមានដំណើរសម្រាប់ឡានរបស់អ្នក'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
    ),
  );
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  final String title;
  final String? busNumber;
  final Color statusColor;
  const _TripCard({
    required this.trip,
    required this.title,
    required this.busNumber,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(
          busNumber != null ? 'ឡានលេខ $busNumber' : trip.direction,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            trip.status,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DriverTripDetailScreen(tripId: trip.id),
          ),
        ),
      ),
    );
  }
}

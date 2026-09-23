import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../utils/constants/colors.dart';
import '../../utils/theme/app_palette.dart';
import 'admin_buses_screen.dart';
import 'admin_trips_screen.dart';
import 'admin_users_screen.dart';

/// Management hub — a launcher for the admin areas that don't warrant a bottom
/// tab of their own.
///
/// Places and Routes keep their own tabs because they're map-driven and used
/// constantly; users, trips and buses are occasional record-keeping, so they sit
/// one tap deeper rather than pushing the nav bar past five items.
class AdminManagementScreen extends StatelessWidget {
  const AdminManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(t.managementTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ManagementCard(
            icon: Icons.group,
            color: Colors.deepPurple,
            title: t.userManagement,
            subtitle: t.userManagementDesc,
            builder: (_) => const AdminUsersScreen(),
          ),
          const SizedBox(height: 12),
          _ManagementCard(
            icon: Icons.alt_route,
            color: AppColors.secondaryColor,
            title: t.tripManagement,
            subtitle: t.tripManagementDesc,
            builder: (_) => const AdminTripsScreen(),
          ),
          const SizedBox(height: 12),
          _ManagementCard(
            icon: Icons.directions_bus,
            color: Colors.teal,
            title: t.busManagement,
            subtitle: t.busManagementDesc,
            builder: (_) => const AdminBusesScreen(),
          ),
        ],
      ),
    );
  }
}

class _ManagementCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  const _ManagementCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Card(
      margin: EdgeInsets.zero,
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: builder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withAlpha(38), // ~0.15 opacity
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: p.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

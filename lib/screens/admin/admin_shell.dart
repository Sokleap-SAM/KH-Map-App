import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../utils/constants/colors.dart';
import '../account_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_places_screen.dart';
import 'admin_routes_screen.dart';

/// Admin shell: Dashboard home, Places + Routes management, plus Account (kept
/// for logout). Reuses the existing AccountScreen unchanged, same as the driver
/// shell.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  static const _screens = <Widget>[
    AdminDashboardScreen(),
    AdminPlacesScreen(),
    AdminRoutesScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.primaryColor,
        selectedItemColor: AppColors.secondaryColor,
        unselectedItemColor: AppColors.secondaryTextColor,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: t.adminDashboardTab,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.place_outlined),
            activeIcon: const Icon(Icons.place),
            label: t.placesTab,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.route_outlined),
            activeIcon: const Icon(Icons.route),
            label: t.routesTab,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            activeIcon: const Icon(Icons.person),
            label: t.navAccount,
          ),
        ],
      ),
    );
  }
}

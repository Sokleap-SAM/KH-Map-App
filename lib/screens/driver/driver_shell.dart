import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../utils/constants/colors.dart';
import '../account_screen.dart';
import 'driver_home_screen.dart';
import 'driver_trips_screen.dart';

/// 3-tab driver shell. Reuses the existing AccountScreen unchanged per
/// driver-frontend-brief.md §"Account screen".
class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _index = 0;

  static const _screens = <Widget>[
    DriverHomeScreen(),
    DriverTripsScreen(),
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
            icon: const Icon(Icons.home_outlined),
            activeIcon: const Icon(Icons.home),
            label: t.home,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.directions_bus_outlined),
            activeIcon: const Icon(Icons.directions_bus),
            label: t.tripsTitle,
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

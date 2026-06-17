import 'package:flutter/material.dart';

import '../../utils/constants/colors.dart';
import '../account_screen.dart';
import 'admin_routes_screen.dart';
import 'admin_stops_screen.dart';

/// Admin shell: Stops + Routes management, plus Account (kept for logout).
/// Reuses the existing AccountScreen unchanged, same as the driver shell.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  static const _screens = <Widget>[
    AdminStopsScreen(),
    AdminRoutesScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
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
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.place_outlined),
            activeIcon: Icon(Icons.place),
            label: 'ចំណត',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.route_outlined),
            activeIcon: Icon(Icons.route),
            label: 'ផ្លូវ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'គណនី',
          ),
        ],
      ),
    );
  }
}

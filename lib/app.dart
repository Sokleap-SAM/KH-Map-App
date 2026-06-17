import 'package:flutter/material.dart';
import 'package:kh_map_app/screens/map_screen.dart';
import 'package:kh_map_app/screens/bookmark_screen.dart';
import 'package:kh_map_app/screens/contribute_screen.dart';
import 'package:kh_map_app/screens/account_screen.dart';
import 'package:kh_map_app/utils/constants/colors.dart';
import 'package:provider/provider.dart';
import 'providers/map_provider.dart';
import 'providers/transit_provider.dart';
import 'services/location_service.dart';
import 'utils/theme/theme.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  int _currentIndex = 0;

  void _goToMapTab() => setState(() => _currentIndex = 0);

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      const MapScreen(),
      BookmarkScreen(onNavigateToMap: _goToMapTab),
      const ContributeScreen(),
      const AccountScreen(),
    ];
    return ChangeNotifierProvider(
      create: (_) => MapProvider(LocationService()),
      child: ChangeNotifierProvider(
        create: (_) => TransitProvider(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          home: Scaffold(
            body: IndexedStack(index: _currentIndex, children: screens),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              type: BottomNavigationBarType.fixed,
              backgroundColor: AppColors.primaryColor,
              selectedItemColor: AppColors.secondaryColor,
              unselectedItemColor: AppColors.secondaryTextColor,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.location_on_outlined),
                  activeIcon: Icon(Icons.location_on),
                  label: 'ផែនទី',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.bookmark_border),
                  activeIcon: Icon(Icons.bookmark),
                  label: 'ចំណាំ',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.add_circle_outline),
                  activeIcon: Icon(Icons.add_circle),
                  label: 'ចូលរួម',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: 'គណនី',
                ),
              ],
            ),
          ),
        ),
        // ),
      ),
    );
  }
}

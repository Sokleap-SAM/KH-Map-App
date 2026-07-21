import 'package:flutter/material.dart';
import 'package:kh_map_app/screens/map_screen.dart';
import 'package:kh_map_app/screens/bookmark_screen.dart';
import 'package:kh_map_app/screens/contribute_screen.dart';
import 'package:kh_map_app/screens/account_screen.dart';
import 'package:kh_map_app/screens/driver/driver_shell.dart';
import 'package:kh_map_app/screens/admin/admin_shell.dart';
import 'package:kh_map_app/services/auth_service.dart';
import 'package:kh_map_app/utils/constants/colors.dart';
import 'package:kh_map_app/utils/jwt.dart';
import 'package:provider/provider.dart';
import 'providers/driver_provider.dart';
import 'providers/map_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/transit_provider.dart';
import 'services/location_service.dart';
import 'utils/theme/theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MapProvider(LocationService())),
        ChangeNotifierProvider(create: (_) => TransitProvider()),
        ChangeNotifierProvider(create: (_) => DriverProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const _RoleAwareShell(),
      ),
    );
  }
}

/// Watches the auth token and picks the shell to render based on `role`.
/// - `driver` → DriverShell (Home / Trips / Account)
/// - `admin` → AdminShell (Routes / Account)
/// - anything else → rider shell (existing 4-tab nav)
class _RoleAwareShell extends StatefulWidget {
  const _RoleAwareShell();

  @override
  State<_RoleAwareShell> createState() => _RoleAwareShellState();
}

class _RoleAwareShellState extends State<_RoleAwareShell> {
  String? _lastRole;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AuthService.tokenNotifier,
      builder: (context, token, _) {
        final role = roleFromToken(token);
        // Initialize / shut down DriverProvider on role transitions.
        if (role != _lastRole) {
          _lastRole = role;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final driver = context.read<DriverProvider>();
            if (role == 'driver') {
              driver.init();
            } else {
              driver.shutdownForLogout();
            }
          });
        }
        if (role == 'driver') return const DriverShell();
        if (role == 'admin') return const AdminShell();
        return const _RiderShell();
      },
    );
  }
}

class _RiderShell extends StatefulWidget {
  const _RiderShell();

  @override
  State<_RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends State<_RiderShell> {
  int _currentIndex = 0;

  void _goToMapTab() => setState(() => _currentIndex = 0);

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    final screens = <Widget>[
      const MapScreen(),
      BookmarkScreen(onNavigateToMap: _goToMapTab),
      const ContributeScreen(),
      const AccountScreen(),
    ];
    return Scaffold(
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
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.location_on_outlined),
            activeIcon: const Icon(Icons.location_on),
            label: t.navMap,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.bookmark_border),
            activeIcon: const Icon(Icons.bookmark),
            label: t.navBookmarks,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.add_circle_outline),
            activeIcon: const Icon(Icons.add_circle),
            label: t.navContribute,
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

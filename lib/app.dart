import 'package:flutter/material.dart';
import 'package:kh_map_app/utils/constants/colors.dart';
import 'utils/theme/theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: Center(
          child: Text(
            'Clicked',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.clickedTextColor),
          ),
        ),
      ),
    );
  }
}

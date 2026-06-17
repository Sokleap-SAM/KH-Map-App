import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:kh_map_app/app.dart';
import 'package:provider/provider.dart';
import 'package:kh_map_app/providers/settings_provider.dart';
import 'package:kh_map_app/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await AuthService.initTokenNotifier();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const App(),
    ),
  );
}
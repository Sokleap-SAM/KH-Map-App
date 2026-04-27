import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:kh_map_app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await dotenv.load(fileName: ".env");

  try {
    await dotenv.load(fileName: ".env"); // 2. Load it 
    print("Environment variables loaded: ${dotenv.env['BASE_URL']}"); // 3. Debug print to verify
  } catch (e) {
    print("Error loading .env file: $e");
  }
  runApp(const App());
}

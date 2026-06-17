import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:kh_map_app/providers/settings_provider.dart';
import 'package:kh_map_app/screens/login_screen.dart';
import 'package:kh_map_app/services/auth_service.dart';
import 'package:kh_map_app/utils/constants/colors.dart';
import 'package:provider/provider.dart';
import 'package:kh_map_app/utils/jwt.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String userName = "មិនមានគណនី";
  bool isLoggedIn = false;
  bool isLoading = true;

  final String baseUrl = AuthService.baseUrl;

  @override
  void initState() {
    super.initState();
    _fetchProfile(); // Runs automatically when screen opens
  }

  Future<void> _fetchProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    // Logging in as a driver swaps this whole shell out, disposing this
    // screen while the request is still in flight — guard every setState.
    if (!mounted) return;

    if (token == null) {
      setState(() => isLoading = false);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse("$baseUrl/users/profile"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        print("PROFILE DATA FROM BACKEND: $data");

        setState(() {
          userName = data['name'] ?? "No Name Found";
          isLoggedIn = true;
        });
      } else if (response.statusCode == 401) {
        // Token genuinely invalid/expired — treat as logged out.
        setState(() => isLoggedIn = false);
      } else {
        // Endpoint not authorized for this role (e.g. 403 for drivers).
        // We still hold a valid session — show the name from the JWT.
        _fallbackToTokenName(token);
      }
    } catch (e) {
      debugPrint("Error fetching profile: $e");
      // Network error but we have a token — stay logged in using JWT claims.
      _fallbackToTokenName(token);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _fallbackToTokenName(String token) {
    if (!mounted) return;
    final claims = decodeJwtPayload(token);
    setState(() {
      userName = (claims?['name'] as String?) ?? "Driver";
      isLoggedIn = true;
    });
  }

  Future<void> _handleLogout() async {
    await AuthService().logout();
    if (!mounted) return;
    setState(() {
      isLoggedIn = false;
      userName = "មិនមានគណនី";
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final Color textColor = settings.isDarkMode ? Colors.white : Colors.black87;
    final Color subTextColor = settings.isDarkMode ? Colors.white70 : Colors.black54;
    final Color containerColor = settings.isDarkMode ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
    return Scaffold(
      backgroundColor: settings.isDarkMode ? AppColors.primaryColor : Colors.white,
      body: Container(
        decoration: BoxDecoration(
          gradient: settings.isDarkMode
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 1.0], // Smooth transition from top to bottom
                  colors: [
                    Colors.white, // Start with pure white
                    const Color(0xFFF0F4F8), // End with a very subtle, light blue-grey
                  ],
                ),
        ),
        child: SafeArea(
          child: isLoading
              ? Center(child: CircularProgressIndicator(color: settings.isDarkMode ? const Color(0xFFE8B67D) : AppColors.primaryColor))
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 30),
                          child: Column(
                            children: [
                              const SizedBox(height: 60),

                              // 1. Profile Icon (Static)
                              const Center(
                                child: CircleAvatar(
                                  radius: 50,
                                  backgroundColor: Colors.transparent,
                                  backgroundImage: AssetImage('assets/images/defaultAccountIcon.png'),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // --- START CONDITIONAL UI ---
                              if (!isLoggedIn) ...[
                                Text(settings.locale.languageCode == 'km' ? "មិនមានគណនី" : "No Account",
                                    style: const TextStyle(color: Color(0xFFE8B67D), fontSize: 22, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 25),
                                _buildDescriptionBox(settings.locale.languageCode, textColor),
                                const SizedBox(height: 40),
                                _buildLoginButton(context, settings.locale.languageCode),
                                const SizedBox(height: 15),
                                _buildSocialRow(),
                              ] else ...[
                        Text(
                          userName, 
                          style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)
                        ),
                        const SizedBox(height: 25),
                        _buildLogoutButton(settings.locale.languageCode),
                      ],

                      const SizedBox(height: 40),
                      
                      // 5. ADD THE SETTINGS SECTION HERE
                      _buildSettingsSection(settings, textColor, subTextColor, containerColor),

                      const SizedBox(height: 60),
                      Text("...", style: TextStyle(color: subTextColor, fontSize: 30)),
                    ],
                  ),
                ),
              ),
            ),
            _buildSupportBar(settings.locale.languageCode),
          ],
        ),
      ),
    ));
  }

  // --- NEW SETTINGS UI SECTION ---
  Widget _buildSettingsSection(SettingsProvider settings, Color textColor, Color subTextColor, Color bgColor) {
    bool isKhmer = settings.locale.languageCode == 'km';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 10),
          child: Text(
            isKhmer ? "ការកំណត់" : "Settings",
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              // Dark Mode Toggle
              ListTile(
                leading: Icon(Icons.dark_mode, color: isKhmer ? const Color(0xFFE8B67D) : Colors.blue),
                title: Text(isKhmer ? "ប្ដូវពណ៌ផ្ទាំង" : "Dark Mode", style: TextStyle(color: textColor)),
                trailing: Switch(
                  value: settings.isDarkMode,
                  activeColor: const Color(0xFFE8B67D),
                  onChanged: (val) => settings.toggleTheme(val),
                ),
              ),
              const Divider(height: 1, indent: 0, color: Colors.white24),
              // Language Switcher
              ListTile(
                leading: Icon(Icons.language, color: Colors.blueAccent),
                title: Text(isKhmer ? "ភាសា" : "Language", style: TextStyle(color: textColor)),
                trailing: DropdownButton<String>(
                  value: settings.locale.languageCode,
                  dropdownColor: settings.isDarkMode ? Color(0xFF1E1E1E) : Colors.white,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'km', child: Text("ខ្មែរ", style: TextStyle(color: Colors.blue))),
                    DropdownMenuItem(value: 'en', child: Text("English", style: TextStyle(color: Colors.blue))),
                  ],
                  onChanged: (code) {
                    if (code != null) settings.setLocale(Locale(code));
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Updated Helper Methods to handle translations
  Widget _buildDescriptionBox(String lang, Color textColor) {
    String text = lang == 'km' 
      ? "សូមបង្កើតឬចូលក្នុងគណនីដើម្បីរក្សាទុកទិន្នន័យ និងទទួលបានបទពិសោធន៍ពេញលេញជាមួយ KH-Map"
      : "Please create or login to an account to save data and get the full experience with KH-Map";
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
        color: Colors.white.withOpacity(0.05),
      ),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 14, height: 1.5)),
    );
  }

  Widget _buildLoginButton(BuildContext context, String lang) {
    return SizedBox(
      width: 140,
      child: ElevatedButton(
        onPressed: () async {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
          if (result == true) _fetchProfile();
        },
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF91A5D4), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
        child: Text(lang == 'km' ? "ចូលគណនី" : "Login", style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildLogoutButton(String lang) {
    return GestureDetector(
      onTap: _handleLogout,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFAAB8DA), borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(lang == 'km' ? "ផ្លាស់ប្តូរគណនី" : "Change Account", style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            const Icon(Icons.keyboard_arrow_down, color: Colors.black87),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportBar(String lang) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFAAB8DA), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.settings_outlined, color: Colors.black87),
            const SizedBox(width: 10),
            Text(lang == 'km' ? "បច្ចេកទេស" : "Technical Support", style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _socialIcon(String imagePath) {
    return Image.asset(imagePath, width: 25, height: 25, errorBuilder: (context, error, stackTrace) => const Icon(Icons.error, color: Colors.white));
  }

  Widget _buildSocialRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _socialIcon('assets/images/google_icon.png'),
        const SizedBox(width: 20),
        _socialIcon('assets/images/apple_icon.png'),
        const SizedBox(width: 20),
        _socialIcon('assets/images/facebook_icon.png'),
      ],
    );
  }
}

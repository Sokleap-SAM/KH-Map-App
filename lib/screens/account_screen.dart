import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:kh_map_app/screens/login_screen.dart';
import 'package:kh_map_app/services/auth_service.dart';
import 'package:kh_map_app/utils/constants/colors.dart';
import 'package:kh_map_app/utils/jwt.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    return Scaffold(
      backgroundColor: AppColors.primaryColor,
      body: SafeArea(
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFE8B67D)),
              )
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
                                backgroundImage: AssetImage(
                                  'assets/images/defaultAccountIcon.png',
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // --- START CONDITIONAL UI ---
                            if (!isLoggedIn) ...[
                              // UI FOR LOGGED OUT USERS
                              const Text(
                                "មិនមានគណនី",
                                style: TextStyle(
                                  color: Color(0xFFE8B67D),
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 25),

                              _buildDescriptionBox(),

                              const SizedBox(height: 40),

                              _buildLoginButton(context),

                              const SizedBox(height: 15),

                              const Text(
                                "ចូលជាមួយ",
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),

                              const SizedBox(height: 15),

                              _buildSocialRow(),
                            ] else ...[
                              // UI FOR LOGGED IN USERS
                              Text(
                                userName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 25),

                              // "Change Account" Box (Acts as Logout)
                              GestureDetector(
                                onTap: _handleLogout,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFAAB8DA),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "ផ្លាស់ប្តូរគណនី",
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Icon(
                                        Icons.keyboard_arrow_down,
                                        color: Colors.black87,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            // --- END CONDITIONAL UI ---
                            const SizedBox(height: 60),
                            const Text(
                              "...",
                              style: TextStyle(
                                color: Colors.white24,
                                fontSize: 30,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Settings Bar (Always visible at the bottom)
                  _buildSupportBar(),
                ],
              ),
      ),
    );
  }

  // UI HELPER METHODS

  Widget _buildDescriptionBox() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
        color: Colors.white.withOpacity(0.05),
      ),
      child: const Text(
        "សូមបង្កើតឬចូលក្នុងគណនីដើម្បីរក្សាទុកទិន្នន័យ និងទទួលបានបទពិសោធន៍ពេញលេញជាមួយ KH-Map",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
      ),
    );
  }

  Widget _buildLoginButton(BuildContext context) {
    return SizedBox(
      width: 140,
      child: ElevatedButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
          // If login was successful, refresh the profile
          if (result == true) {
            _fetchProfile();
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF91A5D4),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: const Text(
          "ចូលគណនី",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
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

  Widget _buildSupportBar() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFAAB8DA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.settings_outlined, color: Colors.black87),
            SizedBox(width: 10),
            Text(
              "បច្ចេកទេស",
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _socialIcon(String imagePath) {
    return Image.asset(
      imagePath,
      width: 25,
      height: 25,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.error, color: Colors.white),
    );
  }
}

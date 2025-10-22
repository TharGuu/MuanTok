import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'signin_screen.dart';
import 'main_navigation.dart'; // make sure this exists

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final Image _logo;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Preload the logo so it displays instantly
    _logo = Image.asset('assets/images/muan_tok_logo.png', width: 150);
    precacheImage(_logo.image, context);
  }

  Future<void> _bootstrap() async {
    try {
      // Keep the splash visible briefly for brand feel
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      final session = Supabase.instance.client.auth.currentSession;
      if (!mounted) return;

      if (session == null) {
        // Not signed in → go to Sign In
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SignInScreen()),
        );
      } else {
        // Already signed in → go to main app
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainNavigation()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      // On any unexpected error, fall back to Sign In
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _logo,
            const SizedBox(height: 20),
            const Text(
              'MuanTok',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFFa29bfe),
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

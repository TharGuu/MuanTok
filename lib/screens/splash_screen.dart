import 'dart:async';
import 'package:flutter/material.dart';
import 'signin_screen.dart'; // We will create this next

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {

  @override
  void initState() {
    super.initState();
    // Wait for 3 seconds then navigate to the Sign In screen
    Timer(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => SignInScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Your logo
            Image.asset(
              'assets/images/muan_tok_logo.png',
              width: 150, // Adjust the size as needed
            ),
            const SizedBox(height: 20),
            // Your App Name
            const Text(
              'MuanTok',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFFa29bfe), // A color similar to your logo
              ),
            ),
          ],
        ),
      ),
    );
  }
}
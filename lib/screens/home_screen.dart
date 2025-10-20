import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'signin_screen.dart'; // Import your sign-in screen

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // --- ADD LOGOUT LOGIC ---
              await Supabase.instance.client.auth.signOut();

              // Navigate back to Sign In screen and remove all previous routes
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const SignInScreen()),
                      (route) => false, // This removes all routes from the stack
                );
              }
            },
          )
        ],
      ),
      body: const Center(
        child: Text(
          'Welcome to MuanTok!',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
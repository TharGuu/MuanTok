import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_navigation.dart'; // <-- 1. IMPORT MainNavigation instead of HomeScreen
import 'signup_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  final _supabase = Supabase.instance.client;

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final AuthResponse res = await _supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // If sign in is successful, navigate to home
      if (res.user != null && context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          // 2. NAVIGATE TO MainNavigation
          MaterialPageRoute(builder: (context) => const MainNavigation()),
              (route) => false,
        );
      }
    } on AuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("An unexpected error occurred"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // The Gradient Background
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFf3e5f5), Color(0xFFe1bee7)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Welcome Back!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF673ab7),
                          ),
                        ),
                        const SizedBox(height: 30),

                        _buildTextField(_emailController, 'Email', 'Enter your email address'),
                        const SizedBox(height: 20),
                        _buildTextField(_passwordController, 'Password', 'Enter your password', isPassword: true),
                        const SizedBox(height: 10),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () { /* Handle Forgot Password */ },
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(color: Color(0xFF673ab7)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 5. Update Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _signIn, // Call _signIn
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFd1c4e9),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.black54),
                          )
                              : const Text(
                            'Sign In',
                            style: TextStyle(fontSize: 18, color: Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // (Google Sign In button is here - logic can be added later)
                        // ...
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?"),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const SignUpScreen()),
                          );
                        },
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(
                            color: Color(0xFF673ab7),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Reusable Text Field
  Widget _buildTextField(TextEditingController controller, String label, String hint, {bool isPassword = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPassword,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            suffixIcon: isPassword
                ? const Icon(Icons.visibility_off_outlined, color: Colors.grey)
                : null,
          ),
        ),
      ],
    );
  }
}
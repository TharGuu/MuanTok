import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_navigation.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  final _supabase = Supabase.instance.client;

  Future<void> _signUp() async {
    if (_isLoading) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() => _isLoading = true);
    try {
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text.trim();
      final fullName = _fullNameCtrl.text.trim();

      final res = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
        },
        // If you handle email confirmation deep links in-app, set redirectTo:
        // emailRedirectTo: 'com.muantok.app://auth-callback',
      );

      // If your Supabase project requires email confirmation,
      // res.session will be null and res.user is created but unconfirmed.
      if (!mounted) return;

      if (res.session != null) {
        // Session available -> go straight to app
        // (auto-confirm ON)
        // Optional: create profile row
        await _maybeCreateProfile(res.user!.id, fullName);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainNavigation()),
              (_) => false,
        );
      } else {
        // No session -> ask user to verify email then return to Sign In
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Check your inbox to verify your email, then sign in.'),
          ),
        );
        Navigator.of(context).pop(); // back to Sign In
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An unexpected error occurred'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _maybeCreateProfile(String userId, String fullName) async {
    // Comment this out if you don't have a "profiles" table yet.
    // Minimal schema:
    // create table public.profiles (
    //   id uuid primary key references auth.users(id) on delete cascade,
    //   full_name text,
    //   avatar_url text,
    //   created_at timestamp with time zone default now()
    // );
    try {
      await _supabase.from('profiles').upsert({
        'id': userId,
        'full_name': fullName,
      });
    } catch (_) {
      // Non-fatal for MVP
    }
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: Container(
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
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Create an Account',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF673ab7),
                              ),
                            ),
                            const SizedBox(height: 30),

                            _LabeledField(
                              label: 'Full Name',
                              child: TextFormField(
                                controller: _fullNameCtrl,
                                textInputAction: TextInputAction.next,
                                decoration: _decoration('Your full name'),
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  if (value.isEmpty) return 'Full name is required';
                                  if (value.length < 2) return 'Too short';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 20),

                            _LabeledField(
                              label: 'Email Address',
                              child: TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: _decoration('your@example.com'),
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  if (value.isEmpty) return 'Email is required';
                                  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
                                  if (!ok) return 'Enter a valid email';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 20),

                            _LabeledField(
                              label: 'Password',
                              child: TextFormField(
                                controller: _passwordCtrl,
                                obscureText: _obscure1,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.newPassword],
                                decoration: _decoration('********').copyWith(
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure1
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined),
                                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                                  ),
                                ),
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  if (value.isEmpty) return 'Password is required';
                                  if (value.length < 6) return 'Minimum 6 characters';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 20),

                            _LabeledField(
                              label: 'Confirm Password',
                              child: TextFormField(
                                controller: _confirmCtrl,
                                obscureText: _obscure2,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _signUp(),
                                decoration: _decoration('********').copyWith(
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure2
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined),
                                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                                  ),
                                ),
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  if (value.isEmpty) return 'Please confirm your password';
                                  if (value != _passwordCtrl.text.trim()) return 'Passwords do not match';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 30),

                            ElevatedButton(
                              onPressed: _isLoading ? null : _signUp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFd1c4e9),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(color: Colors.black54),
                              )
                                  : const Text('Sign Up',
                                  style: TextStyle(fontSize: 18, color: Colors.black87)),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Already have an account?'),
                        TextButton(
                          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                          child: const Text(
                            'Sign In',
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
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400),
    filled: true,
    fillColor: Colors.grey.shade100,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
  );
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54,
            )),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

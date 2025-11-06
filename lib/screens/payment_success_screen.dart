// lib/screens/payment_success_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';

// ⬇️ This is the screen that owns your bottom dock
import 'main_navigation.dart';

/* ------------------------------ Lucid Theme ------------------------------ */
const kPrimary  = Color(0xFF7C3AED);
const kText     = Color(0xFF1F2937);
const kMuted    = Color(0xFF6B7280);
const kBgTop    = Color(0xFFF8F5FF);
const kBgBottom = Color(0xFFFDFBFF);

class PaymentSuccessScreen extends StatefulWidget {
  const PaymentSuccessScreen({super.key}); // no params needed

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen>
    with SingleTickerProviderStateMixin {
  bool _checking = true;
  late final AnimationController _anim;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim  = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _scale = CurvedAnimation(parent: _anim, curve: Curves.easeOutBack);
    _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);

    // Simulate payment verification
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _checking = false);
      _anim.forward();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _goHome() async {
    if (!mounted) return;
    // Go back to the base scaffold that has the bottom dock
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavigation()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [kBgTop, kBgBottom],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: WillPopScope(
          onWillPop: () async => false, // prevent returning to checkout
          child: SafeArea(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _checking
                    ? const _Checking()
                    : FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: _SuccessCard(onGoHome: _goHome),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('checking'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        SizedBox(height: 12),
        CircularProgressIndicator(color: kPrimary),
        SizedBox(height: 16),
        Text('Checking payment…', style: TextStyle(color: kText, fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text('This usually takes a few seconds.', style: TextStyle(color: kMuted)),
      ],
    );
  }
}

/* ----------------------- Rounded-rectangle success card ------------------ */
class _SuccessCard extends StatelessWidget {
  final VoidCallback onGoHome;
  const _SuccessCard({required this.onGoHome});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.sizeOf(context).width * .82,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 12))],
        border: Border.all(color: const Color(0x11000000)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 84,
            width: 84,
            decoration: BoxDecoration(
              color: kPrimary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 16),
          const Text(
            'Payment Successful',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kText),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your order is being prepared.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kMuted),
          ),
          const SizedBox(height: 18),
          // Single button (inside the card) to go back to the base nav with dock
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onGoHome,
              icon: const Icon(Icons.home_rounded),
              label: const Text('Go to Home'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

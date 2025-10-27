import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/splash_screen.dart';

// 1. main() must be void, not Future<void> async
void main() {
  // WidgetsFlutterBinding.ensureInitialized() runs first and sets up the Root Zone
  WidgetsFlutterBinding.ensureInitialized();

  // Basic error wiring
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  // 2. Wrap ALL asynchronous setup logic inside runZonedGuarded
  runZonedGuarded(
        () async { // Use async here for the setup function
      await dotenv.load(fileName: ".env");

      final supabaseUrl = dotenv.env['SUPABASE_URL'];
      final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

      if (supabaseUrl == null || supabaseAnonKey == null) {
        throw Exception('Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env');
      }

      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );

      // 3. runApp is called here, after all awaits are complete
      runApp(const MyApp());
    },
        (error, stack) {
      // Uncaught error handling
      // ignore: avoid_print
      print('Uncaught error: $error');
    },
  );
}

// Supabase client accessible app-wide
final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MuanTok',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.purple,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const SplashScreen(),
    );
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment (works in debug/dev; you can also use dart-define in CI later)
  await dotenv.load(fileName: ".env");

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseAnonKey == null) {
    // Fail fast with a clear message in development
    throw Exception('Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env');
  }

  // Initialize Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  // Basic error wiring (keeps it simple)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  runZonedGuarded(
        () => runApp(const MyApp()),
        (error, stack) {
      // TODO: plug in a crash reporter later (Sentry/Crashlytics)
      // For now, print so we see it in logs
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

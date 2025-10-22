import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'screens/signin_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/main_navigation.dart';
import 'screens/home_screen.dart';
import 'screens/message_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/create_screen.dart';
import 'screens/shop_screen.dart';

class AppRoutes {
  static const splash = '/';
  static const signIn = '/signin';
  static const signUp = '/signup';
  static const mainNav = '/main';
  static const home = '/home';
  static const chat = '/chat';
  static const profile = '/profile';
  static const create = '/create';
  static const shop = '/shop';

  static Map<String, WidgetBuilder> map = {
    splash: (_) => const SplashScreen(),
    signIn: (_) => const SignInScreen(),
    signUp: (_) => const SignUpScreen(),
    mainNav: (_) => const MainNavigation(),
    home: (_) => const HomeScreen(),
    chat: (_) => const MessageScreen(),
    profile: (_) => const ProfileScreen(),
    create: (_) => const CreateScreen(),
    shop: (_) => const ShopScreen(),
  };
}

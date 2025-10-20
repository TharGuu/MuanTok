import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'shop_screen.dart';
import 'create_screen.dart';
import 'message_screen.dart';
import 'profile_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0; // This controls which tab is active

  // List of all the pages
  static const List<Widget> _widgetOptions = <Widget>[
    HomeScreen(),
    ShopScreen(),
    CreateScreen(),
    MessageScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The body changes based on the selected tab
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),

      // The Bottom Navigation Bar
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shop_outlined),
            activeIcon: Icon(Icons.shop),
            label: 'Shop',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline, size: 35), // Larger create icon
            activeIcon: Icon(Icons.add_circle, size: 35),
            label: '', // No label for create
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.message_outlined),
            activeIcon: Icon(Icons.message),
            label: 'Message',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,

        // Styling to match your design
        type: BottomNavigationBarType.fixed, // Fixes item width
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF673ab7), // Purple color
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false, // Hide labels as per design
        showUnselectedLabels: false,

        onTap: _onItemTapped,
      ),
    );
  }
}
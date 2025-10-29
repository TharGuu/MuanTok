/*import 'package:flutter/material.dart';
import 'watch_live_screen.dart';


class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // WatchLiveScreen already returns a full Scaffold with the feed.
    return const WatchLiveScreen();
  }
}
*/

import 'package:flutter/material.dart';
//import 'package:muantok/screens/chat_list_screen.dart'; // To navigate to messages
import 'package:muantok/screens/search_screen.dart'; // To navigate to search
import 'watch_live_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 1. Add an AppBar to provide navigation and actions.
      appBar: AppBar(
        // Use a Stack to overlay the title on the transparent background
        title: Stack(
          children: [
            // This provides a subtle gradient so the text is readable
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.5), Colors.transparent],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(
                'MuanTok',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: <Shadow>[
                    Shadow(
                      offset: Offset(1.0, 1.0),
                      blurRadius: 3.0,
                      color: Color.fromARGB(150, 0, 0, 0),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent, // Make AppBar see-through
        elevation: 0,
        centerTitle: true,
        // 2. Add action buttons for Search and Messages.
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              );
            },
          ),
        ],
      ),
      // 3. Make the AppBar draw over the body content.
      extendBodyBehindAppBar: true,
      // 4. The main content of the screen is still your WatchLiveScreen.
      body: const WatchLiveScreen(),
    );
  }
}
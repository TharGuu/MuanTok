import 'package:flutter/material.dart';
import 'watch_live_screen.dart';


class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // WatchLiveScreen already returns a full Scaffold with the feed.
    return const WatchLiveScreen();
  }
}

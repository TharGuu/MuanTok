import 'package:flutter/material.dart';
import 'watch_live_screen.dart';

/// Home = TikTok-style vertical live feed.
/// We delegate the whole screen to WatchLiveScreen to avoid
/// duplicate overlays (top bar, right stats, bottom product card).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // WatchLiveScreen already returns a full Scaffold with the feed.
    return const WatchLiveScreen();
  }
}

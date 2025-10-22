import 'package:flutter/material.dart';
import 'search_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // PageView for vertical scrolling like TikTok
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: 5, // demo pages
      itemBuilder: (context, index) {
        return _buildVideoPage(context); // Build the video page UI
      },
    );
  }

  // This widget builds the UI for a single video page
  Widget _buildVideoPage(BuildContext context) {
    final safeArea = MediaQuery.of(context).padding;

    return Stack(
      fit: StackFit.expand,
      children: [
        // --- 1. The Blank Video Area ---
        Container(
          color: Colors.grey[300],
          child: const Center(
            child: Text(
              'Live Stream Placeholder',
              style: TextStyle(color: Colors.black54, fontSize: 18),
            ),
          ),
        ),

        // --- 2. Top Bar (Public/Friend, Search, Profile) ---
        Positioned(
          top: safeArea.top + 10,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Public/Friend Toggle (static for now)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Public',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: const Text('Friend',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              // Icons
              Row(
                children: [
                  // SEARCH → open SearchScreen
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white, size: 30, shadows: [Shadow(blurRadius: 2)]),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // AVATAR → open current user's ProfileScreen
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    },
                    child: const CircleAvatar(
                      radius: 15,
                      backgroundColor: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // --- 3. Right Side Bar (Like, Comment, etc.) ---
        Positioned(
          bottom: 20,
          right: 16,
          child: Column(
            children: [
              _buildSideBarIcon(Icons.favorite_rounded, '2.3M'),
              const SizedBox(height: 20),
              _buildSideBarIcon(Icons.comment_rounded, '56.7K'),
              const SizedBox(height: 20),
              _buildSideBarIcon(Icons.share_rounded, '12.9K'),
              const SizedBox(height: 20),
              _buildSideBarIcon(Icons.bookmark_rounded, '88.2K'),
            ],
          ),
        ),

        // --- 4. Bottom Info (User, Description, Follow) ---
        Positioned(
          bottom: 20,
          left: 16,
          right: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Overlay
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(radius: 12, backgroundColor: Colors.pink[100]),
                    const SizedBox(width: 8),
                    const Text(
                      'Bags: the product is quite good',
                      style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // User Info
              Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '@LilyDreamer',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      shadows: [Shadow(blurRadius: 2)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFd1c4e9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add, color: Colors.black87, size: 16),
                        Text(
                          'Follow',
                          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Embracing the lilac skies... #LilacDreamer #PastelLife',
                style: TextStyle(color: Colors.white, fontSize: 14, shadows: [Shadow(blurRadius: 1)]),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper widget for the side bar icons
  Widget _buildSideBarIcon(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 35, shadows: const [Shadow(blurRadius: 2)]),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 1)],
          ),
        ),
      ],
    );
  }
}

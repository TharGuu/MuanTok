import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart'; // Using your UserProfile model
import '../services/profile_service.dart'; // Using your ProfileService
import 'edit_profile_screen.dart';
import 'main_navigation.dart'; // For navigation after logout

// Converted to a StatefulWidget for refresh capabilities
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Keep a single instance of the service
  final ProfileService _profileService = ProfileService();
  // Using the purple color defined in your signin/signup screens
  final Color primaryPurple = const Color(0xFF673ab7);

  // Future to hold the state for the FutureBuilder
  late Future<UserProfile> _userProfileFuture;

  @override
  void initState() {
    super.initState();
    // Fetch the data when the widget is first created
    _userProfileFuture = _fetchData();
  }

  // Centralized data fetching method
  Future<UserProfile> _fetchData() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      // If user is not logged in, return a future with an error
      return Future.error('User is not authenticated.');
    }
    // Call the service to get the profile data
    return _profileService.fetchUserProfile(userId);
  }

  // Method to manually refresh the data (for pull-to-refresh)
  Future<void> _refreshProfile() async {
    setState(() {
      // Create a new future to trigger the FutureBuilder to rebuild
      _userProfileFuture = _fetchData();
    });
  }

  // Helper to format large numbers (e.g., 25800 -> 25.8K)
  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      final String formatted = (count / 1000).toStringAsFixed(1);
      return formatted.endsWith('.0') ? '${formatted.substring(0, formatted.length - 2)}K' : '${formatted}K';
    } else {
      return count.toString();
    }
  }

  // Helper to show a snackbar for actions
  void _showSnackbar(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 50,
      ),
      // The body now uses the stateful future
      body: FutureBuilder<UserProfile>(
        future: _userProfileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(primaryPurple)));
          }
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
            ));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('No profile data found.'));
          }

          final user = snapshot.data!;

          // Using RefreshIndicator for pull-to-refresh
          return RefreshIndicator(
            onRefresh: _refreshProfile,
            color: primaryPurple,
            child: ListView( // Changed from SingleChildScrollView to ListView for RefreshIndicator
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              children: [
                // --- TOP PROFILE CARD AREA ---
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 16), // Add some top padding
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                            ? NetworkImage(user.avatarUrl!)
                            : null,
                        child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                            ? Icon(Icons.person, size: 50, color: Colors.grey.shade600)
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        user.fullName ?? 'User',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '@${user.fullName?.replaceAll(' ', '').toLowerCase() ?? 'userhandle'}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Text(
                          user.bio ?? 'No bio set. Please edit your profile.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: () async {
                          // Navigate to EditProfileScreen and wait for a result
                          final bool? profileWasUpdated = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(builder: (context) => EditProfileScreen(initialProfile: user)),
                          );
                          // If the profile was updated, refresh the data
                          if (profileWasUpdated == true) {
                            _refreshProfile();
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 45),
                          side: const BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Edit Profile', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () => _showSnackbar(context, 'Sell Products clicked'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryPurple,
                          minimumSize: const Size(double.infinity, 45),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('My Products', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // --- SOCIAL CONNECTIONS ---
                _SectionHeader(title: 'Social Connections'),
                _ConnectionTile(
                  title: 'Following',
                  count: user.followingCount,
                  formatCount: _formatCount,
                  onTap: () => _showSnackbar(context, 'Go to Following list'),
                ),
                _ConnectionTile(
                  title: 'Followers',
                  count: user.followersCount,
                  formatCount: _formatCount,
                  onTap: () => _showSnackbar(context, 'Go to Followers list'),
                ),
                const SizedBox(height: 20),

                // --- ACCOUNT ACTIONS ---
                _SectionHeader(title: 'Account Actions'),
                _ActionTile(
                  title: 'Voucher',
                  icon: Icons.card_giftcard_outlined,
                  onTap: () => _showSnackbar(context, 'Voucher clicked'),
                  color: primaryPurple,
                ),
                _ActionTile(
                  title: 'Log Out',
                  icon: Icons.logout,
                  isDestructive: true,
                  onTap: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const MainNavigation()),
                            (route) => false,
                      );
                      _showSnackbar(context, 'You have been logged out.');
                    }
                  },
                  color: Colors.red,
                ),
                const SizedBox(height: 20), // Add padding at the bottom
              ],
            ),
          );
        },
      ),
    );
  }
}


// These helper widgets remain unchanged as they are already well-structured.
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10.0, bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  final String title;
  final int count;
  final String Function(int) formatCount;
  final VoidCallback onTap;

  const _ConnectionTile({
    required this.title,
    required this.count,
    required this.formatCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero, // Match design better
      leading: Icon(Icons.person_outline, color: Colors.grey.shade700),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatCount(count),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;
  final Color color;

  const _ActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.color,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero, // Match design better
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

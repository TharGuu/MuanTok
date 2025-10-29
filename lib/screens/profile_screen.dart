// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:muantok/screens/signin_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import '../services/profile_service.dart';
import 'edit_profile_screen.dart';
import 'main_navigation.dart';
import 'signin_screen.dart' hide SignInScreen;
import '../services/messaging_service.dart';
import 'chat_room_screen.dart';
import 'my_products_screen.dart';
import '../features/profile/voucher_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileService _profileService = ProfileService();
  final MessagingService _messagingService = MessagingService();
  final Color primaryPurple = const Color(0xFF673ab7);
  final _supabase = Supabase.instance.client;

  late Future<UserProfile> _userProfileFuture;

  bool _isSelf = true;
  bool _isFollowing = false;
  String get _viewerId => _supabase.auth.currentUser?.id ?? '';
  String get _targetId => widget.userId ?? _viewerId;

  @override
  void initState() {
    super.initState();
    _isSelf = (widget.userId == null) || (widget.userId == _viewerId);
    _userProfileFuture = _fetchData();
    if (!_isSelf && _viewerId.isNotEmpty) {
      _checkFollowing();
    }
  }

  Future<UserProfile> _fetchData() async {
    if (_targetId.isEmpty) {
      return Future.error('User is not authenticated.');
    }
    return _profileService.fetchUserProfile(_targetId);
  }

  Future<void> _refreshProfile() async {
    final newProfileData = _fetchData();

    setState(() {
      _userProfileFuture = newProfileData;
    });

    // --- Step 3: Perform other asynchronous work AFTER setState ---
    if (!_isSelf && _viewerId.isNotEmpty) {
      await _checkFollowing();
    }
  }


  Future<void> _checkFollowing() async {
    try {
      final rel = await _supabase
          .from('connections')
          .select('id')
          .eq('follower_id', _viewerId)
          .eq('following_id', _targetId)
          .limit(1);
      if (!mounted) return;
      setState(() => _isFollowing = (rel is List && rel.isNotEmpty));
    } catch (_) {}
  }


  Future<void> _toggleFollow(UserProfile user) async {
    if (_viewerId.isEmpty || _isSelf) return;
    final wasFollowing = _isFollowing;
    setState(() {
      _isFollowing = !wasFollowing;
    });

    try {
      if (wasFollowing) {
        // If they were following, delete the connection.
        await _supabase
            .from('connections')
            .delete()
            .match({'follower_id': _viewerId, 'following_id': _targetId});
      } else {
        // If they were not following, insert the connection.
        await _supabase.from('connections').insert({
          'follower_id': _viewerId,
          'following_id': _targetId,
        });
      }
      await _refreshProfile();

    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isFollowing = wasFollowing;
      });

      // Handle known 'duplicate key' error gracefully (no message, just sync UI)
      if (e is PostgrestException && e.code == '23505') {
        // The state was out of sync. Reverting the UI fix it locally.
      } else {
        // For all other unexpected errors, show a message.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
      }

      await _refreshProfile();
    }
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) {
      final s = (count / 1000).toStringAsFixed(1);
      return s.endsWith('.0') ? '${s.substring(0, s.length - 2)}K' : '${s}K';
    }
    return count.toString();
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
            (_) => false,
      );
      _showSnackbar('You have been logged out.');
    } catch (e) {
      _showSnackbar('Sign out failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelf ? 'My Profile' : 'Profile',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 50,
        actions: [
          if (_isSelf)
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout, color: Colors.black87),
              onPressed: _signOut,
            ),
        ],
      ),
      body: FutureBuilder<UserProfile>(
        future: _userProfileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('No profile data found.'));
          }

          final user = snapshot.data!;

          return RefreshIndicator(
            onRefresh: _refreshProfile,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              children: [
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                            ? NetworkImage(user.avatarUrl!)
                            : null,
                        child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                            ? Icon(Icons.person, size: 50, color: Colors.grey.shade600)
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        user.fullName ?? 'User',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '@${(user.fullName ?? 'user').replaceAll(' ', '').toLowerCase()}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Text(
                          user.bio ?? 'No bio set.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (!_isSelf)
                        Row(
                          children: [
                            // --- Button 1: Follow / Following ---
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _toggleFollow(user),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isFollowing ? Colors.grey.shade300 : primaryPurple,
                                  minimumSize: const Size(double.infinity, 45),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  _isFollowing ? 'Following' : 'Follow',
                                  style: TextStyle(
                                    color: _isFollowing ? Colors.black87 : Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10), // Spacer between buttons

                            // --- Button 2: Message ---
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  try {
                                    // Use the service to get or create a chat room
                                    final roomId = await _messagingService.getOrCreateRoom(user.id);

                                    if (mounted) {
                                      // Navigate to the chat room screen
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ChatRoomScreen(
                                            roomId: roomId,
                                            otherUserName: user.fullName ?? 'User',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    _showSnackbar('Failed to open chat: ${e.toString()}');
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 45),
                                  side: const BorderSide(color: Colors.grey),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  'Message',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                      if (_isSelf) ...[
                        OutlinedButton(
                          onPressed: () async {
                            final bool? updated = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      EditProfileScreen(initialProfile: user)),
                            );
                            if (updated == true) _refreshProfile();
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 45),
                            side: const BorderSide(color: Colors.grey),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text(
                            'Edit Profile',
                            style: TextStyle(
                                color: Colors.black, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // UPDATED: go to MyProductsScreen
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const MyProductsScreen()),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryPurple,
                            minimumSize: const Size(double.infinity, 45),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text(
                            'My Products',
                            style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                _SectionHeader(title: 'Social Connections'),
                _ConnectionTile(
                  title: 'Following',
                  count: user.followingCount,
                  formatCount: _formatCount,
                  onTap: () => _showSnackbar('Go to Following list'),
                ),
                _ConnectionTile(
                  title: 'Followers',
                  count: user.followersCount,
                  formatCount: _formatCount,
                  onTap: () => _showSnackbar('Go to Followers list'),
                ),
                const SizedBox(height: 20),

                if (_isSelf) ...[
                  _SectionHeader(title: 'Account Actions'),
                  _ActionTile(
                    title: 'Voucher',
                    icon: Icons.card_giftcard_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                          const VoucherScreen(initialTab: VoucherTab.available),
                        ),
                      );
                    },
                    color: primaryPurple,
                  ),
                  _ActionTile(
                    title: 'Log Out',
                    icon: Icons.logout,
                    isDestructive: true,
                    onTap: _signOut,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/* ----- Helpers: Section header, connection tile, action tile ----- */

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10.0, bottom: 8.0),
    child: Text(title,
        style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
  );
}

class _ConnectionTile extends StatelessWidget {
  final String title;
  final int count;
  final String Function(int) formatCount;
  final VoidCallback onTap;
  const _ConnectionTile(
      {required this.title,
        required this.count,
        required this.formatCount,
        required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.person_outline, color: Colors.grey.shade700),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(formatCount(count),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, color: Colors.grey),
      ]),
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
  const _ActionTile(
      {required this.title,
        required this.icon,
        required this.onTap,
        required this.color,
        this.isDestructive = false});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title,
          style: TextStyle(
              color: isDestructive ? Colors.red : color,
              fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

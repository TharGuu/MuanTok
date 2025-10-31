import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import 'profile_screen.dart';

enum ConnectionsMode { following, followers}

class ConnectionsScreen extends StatefulWidget {
  final String userId;
  final ConnectionsMode mode;
  final int initialCount;

  const ConnectionsScreen({
    super.key,
    required this.userId,
    required this.mode,
    required this.initialCount,
  });

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final ProfileService _profileService = ProfileService();
  late Future<List<UserProfile>> _connectionsFuture;

  String get _appBarTitle {
    return widget.mode == ConnectionsMode.following ? 'Following' : 'Followers';
  }

  @override
  void initState() {
    super.initState();
    //Fetch the list of users based on the mode
    _connectionsFuture = _profileService.fetchConnections(
      userId : widget.userId,
      mode : widget.mode,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$_appBarTitle (${widget.initialCount})',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: FutureBuilder<List<UserProfile>>(
          future: _connectionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Text('No users Found',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              );
            }
            final users = snapshot.data!;

            return ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 25,
                    backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                  child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                    ? const Icon(Icons.person, size: 25)
                    : null,
                  ),
                  title: Text(user.fullName ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '@${(user.fullName ?? 'user').replaceAll('', '').toLowerCase()}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ProfileScreen(userId: user.id),
                      ),
                    );
                  },
                );
              }
            );
          },
      ),
    );
  }
}
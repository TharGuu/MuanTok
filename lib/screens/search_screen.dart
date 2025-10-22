import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// If you have a profile page that can show any user by id:
import 'profile_screen.dart'; // ensure it can take a userId param OR make a simple viewer

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _supabase = Supabase.instance.client;
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(q.trim());
    });
  }

  Future<void> _search(String q) async {
    final uid = _supabase.auth.currentUser?.id;

    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _loading = true);
    try {
      final data = await _supabase
          .from('users')
          .select('id, full_name, avatar_url')
          .ilike('full_name', '%$q%')
          .limit(25);

      // Filter out the current user manually if uid exists
      final filtered = (data as List)
          .where((user) => user['id'] != uid)
          .toList();

      if (!mounted) return;
      setState(() => _results = List<Map<String, dynamic>>.from(filtered));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search users')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search by name…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('Type a name to find users'))
                : ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final u = _results[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: (u['avatar_url'] != null && (u['avatar_url'] as String).isNotEmpty)
                        ? NetworkImage(u['avatar_url'])
                        : null,
                    child: (u['avatar_url'] == null || (u['avatar_url'] as String).isEmpty)
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(u['full_name'] ?? 'Unnamed'),
                  onTap: () {
                    // Navigate to their profile page
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(userId: u['id']), // make ProfileScreen accept userId
                      ),
                    );
                  },
                  trailing: const Icon(Icons.chevron_right),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

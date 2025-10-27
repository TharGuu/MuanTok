import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// If you have a profile page that can show any user by id:
import 'profile_screen.dart'; // ensure it can take a userId param OR make a simple viewer

/*
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
*/


// Tabbed Search Screen for "Products", "Users", "Hashtags"
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

// Add TickerProviderStateMixin for the TabController animation
class _SearchScreenState extends State<SearchScreen> with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _controller = TextEditingController();
  late final TabController _tabController;
  Timer? _debounce;
  bool _loading = false;

  // --- NEW: Separate lists for each search category ---
  List<Map<String, dynamic>> _userResults = [];
  List<Map<String, dynamic>> _productResults = [];
  // List<Map<String, dynamic>> _hashtagResults = []; // For future implementation

  @override
  void initState() {
    super.initState();
    // Initialize the TabController with 3 tabs
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // When the text changes, start a short timer (debounce) to avoid searching on every keystroke
  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(q.trim());
    });
  }

  // --- UPDATED: The main search function now searches everything in parallel ---
  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() {
        _userResults = [];
        _productResults = [];
      });
      return;
    }

    setState(() => _loading = true);

    try {
      // Run all search queries at the same time for better performance
      final responses = await Future.wait([
        // Search for users
        _supabase
            .from('users')
            .select('id, full_name, avatar_url')
            .ilike('full_name', '%$q%')
            .limit(25),
        // Search for products
        _supabase
            .from('products')
            .select('id, name, price, image_urls')
            .ilike('name', '%$q%')
            .limit(25),
        // In the future, you could add hashtag search here
        // _supabase.from('hashtags')...
      ]);

      if (!mounted) return;

      // Process user results
      final currentUserId = _supabase.auth.currentUser?.id;
      final userList = (responses[0] as List)
          .where((user) => user['id'] != currentUserId) // Exclude self
          .toList();

      // Process product results
      final productList = responses[1] as List;

      setState(() {
        _userResults = List<Map<String, dynamic>>.from(userList);
        _productResults = List<Map<String, dynamic>>.from(productList);
      });

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
      appBar: AppBar(
        title: _buildSearchField(), // The AppBar now contains the search bar
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF673ab7),
          tabs: const [
            Tab(text: 'Products'),
            Tab(text: 'Users'),
            Tab(text: 'Hashtags'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Show a loading bar at the top while searching
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Products Tab
                _buildProductResultsList(),
                // Users Tab
                _buildUserResultsList(),
                // Hashtags Tab (placeholder for now)
                const Center(child: Text('Hashtag search coming soon!')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET HELPERS to keep the build method clean ---

  Widget _buildSearchField() {
    return TextField(
      controller: _controller,
      onChanged: _onQueryChanged,
      autofocus: true, // Automatically focus the search bar
      textInputAction: TextInputAction.search,
      onSubmitted: _search,
      decoration: const InputDecoration(
        hintText: 'Search products, users...',
        border: InputBorder.none,
      ),
    );
  }

  Widget _buildUserResultsList() {
    if (_controller.text.isEmpty) {
      return const Center(child: Text('Start typing to find users.'));
    }
    if (_userResults.isEmpty && !_loading) {
      return const Center(child: Text('No users found.'));
    }
    return ListView.separated(
      itemCount: _userResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final u = _userResults[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: (u['avatar_url'] != null && (u['avatar_url'] as String).isNotEmpty)
                ? NetworkImage(u['avatar_url']) : null,
            child: (u['avatar_url'] == null || (u['avatar_url'] as String).isEmpty)
                ? const Icon(Icons.person) : null,
          ),
          title: Text(u['full_name'] ?? 'Unnamed'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileScreen(userId: u['id'])),
            );
          },
          trailing: const Icon(Icons.chevron_right),
        );
      },
    );
  }

  Widget _buildProductResultsList() {
    if (_controller.text.isEmpty) {
      return const Center(child: Text('Start typing to find products.'));
    }
    if (_productResults.isEmpty && !_loading) {
      return const Center(child: Text('No products found.'));
    }
    return ListView.separated(
      itemCount: _productResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = _productResults[i];
        final imageUrl = (p['image_urls'] as List?)?.first;

        return ListTile(
          leading: SizedBox(
            width: 50,
            height: 50,
            child: imageUrl != null
                ? Image.network(imageUrl, fit: BoxFit.cover)
                : Container(color: Colors.grey.shade200, child: const Icon(Icons.shopping_bag_outlined)),
          ),
          title: Text(p['name'] ?? 'Unnamed Product'),
          subtitle: Text('\$${p['price']?.toStringAsFixed(2) ?? '0.00'}'),
          onTap: () {
            // TODO: Navigate to a ProductDetailScreen(productId: p['id'])
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Tapped on product: ${p['name']}')),
            );
          },
          trailing: const Icon(Icons.chevron_right),
        );
      },
    );
  }
}
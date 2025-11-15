// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'orders/orders_list_screen.dart';

// ✅ keep only one SignIn import
import 'signin_screen.dart'; // provides SignInScreen

// ✅ correct path to the card manager screen
import '../features/profile/payment_cards_screen.dart';

import '../models/user_profile.dart';
import '../services/profile_service.dart';
import 'edit_profile_screen.dart';
import 'main_navigation.dart';
import '../services/messaging_service.dart';
import 'chat_room_screen.dart';
import 'my_products_screen.dart';
import '../features/profile/voucher_screen.dart';
import 'connections_screen.dart';
import '../services/supabase_service.dart';
import 'product_detail_screen.dart';

// ✅ NEW: About screen import
import 'about_muantok_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileService _profileService = ProfileService();
  final MessagingService _messagingService = MessagingService();

  // Lucid purple
  final Color primaryPurple = const Color(0xFF7C3AED);

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
        await _supabase
            .from('connections')
            .delete()
            .match({'follower_id': _viewerId, 'following_id': _targetId});
      } else {
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
      if (e is PostgrestException && e.code == '23505') {
        // duplicate key; ignore
      } else {
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
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 50,
        foregroundColor: Colors.black87,
        actions: [
          if (_isSelf)
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout),
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
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '@${(user.fullName ?? "user").replaceAll(" ", "").toLowerCase()}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
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
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _toggleFollow(user),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isFollowing ? Colors.grey.shade300 : primaryPurple,
                                  minimumSize: const Size(double.infinity, 45),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  try {
                                    final roomId = await _messagingService.getOrCreateRoom(user.id);
                                    if (mounted) {
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
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Message', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),

                      if (_isSelf) ...[
                        OutlinedButton(
                          onPressed: () async {
                            final bool? updated = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(builder: (_) => EditProfileScreen(initialProfile: user)),
                            );
                            if (updated == true) _refreshProfile();
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
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const MyProductsScreen()));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryPurple,
                            minimumSize: const Size(double.infinity, 45),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('My Products', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ConnectionsScreen(
                          userId: _targetId,
                          mode: ConnectionsMode.following,
                          initialCount: user.followingCount,
                        ),
                      ),
                    );
                  },
                ),
                _ConnectionTile(
                  title: 'Followers',
                  count: user.followersCount,
                  formatCount: _formatCount,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ConnectionsScreen(
                          userId: _targetId,
                          mode: ConnectionsMode.followers,
                          initialCount: user.followersCount,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Viewer-only published products
                if (!_isSelf) ViewerPublishedProductsSection(sellerId: _targetId),

                if (_isSelf) ...[
                  _SectionHeader(title: 'Account Actions'),

                  _ActionTile(
                    title: 'My Orders',
                    icon: Icons.local_shipping_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OrdersListScreen()),
                      );
                    },
                    color: primaryPurple, // matches your theme
                  ),

                  // Payment cards manager
                  _ActionTile(
                    title: 'Payment cards',
                    icon: Icons.credit_card,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PaymentCardsScreen()),
                      );
                    },
                    color: primaryPurple,
                  ),

                  _ActionTile(
                    title: 'Coupons',
                    icon: Icons.card_giftcard_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VoucherScreen(initialTab: VoucherTab.available),
                        ),
                      );
                    },
                    color: primaryPurple,
                  ),

                  // ✅ NEW: About before Log Out
                  _ActionTile(
                    title: 'About Muan Tok',
                    icon: Icons.info_outline,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AboutMuanTokScreen(),
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
    child: Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
    ),
  );
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
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.person_outline, color: Colors.grey.shade700),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(formatCount(count), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: isDestructive ? Colors.red.withOpacity(.12) : color.withOpacity(.12),
        child: Icon(icon, color: isDestructive ? Colors.red : color),
      ),
      title: Text(
        title,
        style: TextStyle(color: isDestructive ? Colors.red : Colors.black87, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

/* =================================================================== */
/* ============= Viewer Published Products (unchanged) =============== */
/* =================================================================== */

class ViewerPublishedProductsSection extends StatefulWidget {
  final String sellerId;
  const ViewerPublishedProductsSection({super.key, required this.sellerId});

  @override
  State<ViewerPublishedProductsSection> createState() => _ViewerPublishedProductsSectionState();
}

class _ViewerPublishedProductsSectionState extends State<ViewerPublishedProductsSection> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sb = Supabase.instance.client;
      final rows = await sb
          .from('products')
          .select('''
            id,
            name,
            description,
            category,
            price,
            stock,
            image_urls,
            seller_id,
            seller:users!products_seller_id_fkey(full_name)
          ''')
          .eq('seller_id', widget.sellerId)
          .order('id', ascending: false)
          .limit(60);

      final list = (rows as List).cast<Map<String, dynamic>>();

      final ids = list.map((e) => e['id']).whereType<int>().toList();
      final best = await SupabaseService.fetchBestDiscountMapForProducts(ids);
      for (final p in list) {
        final pid = p['id'] as int?;
        if (pid != null && best.containsKey(pid)) {
          p['discount_percent'] = best[pid];
          p['is_event'] = true;
        }
      }

      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SectionHeader(title: 'Published products'),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Text('Error: _error', style: const TextStyle(color: Colors.red)),
          )
        else if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Align(alignment: Alignment.centerLeft, child: Text('No products yet.')),
            )
          else
            GridView.builder(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.70,
              ),
              itemBuilder: (_, i) => _ViewerProductCard(data: _items[i]),
            ),
      ],
    );
  }
}

class _ViewerProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ViewerProductCard({required this.data});

  List<String> _extractImageUrls(dynamic v) {
    if (v is List) {
      return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    } else if (v is String && v.isNotEmpty) {
      return [v];
    }
    return const [];
  }

  num _parseNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  String _fmtBaht(num value) {
    final s = value.toStringAsFixed(2);
    return s.endsWith('00') ? value.toStringAsFixed(0) : s;
  }

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '').toString();
    final category = (data['category'] ?? '').toString();

    final urls = _extractImageUrls(
      data['image_urls'] ?? data['imageurl'] ?? data['image_url'],
    );
    final img = urls.isNotEmpty ? urls.first : null;

    final priceRaw = _parseNum(data['price']);
    final discountPercent = (data['discount_percent'] is int)
        ? data['discount_percent'] as int
        : int.tryParse('${data['discount_percent'] ?? 0}') ?? 0;
    final hasDiscount = discountPercent > 0 && priceRaw > 0;
    final num discounted = hasDiscount ? (priceRaw * (100 - discountPercent)) / 100 : priceRaw;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(
                productId: data['id'] as int,
                initialData: data,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: img == null
                        ? Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
                    )
                        : Image.network(img, fit: BoxFit.cover),
                  ),
                  if (category.isNotEmpty)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, height: 1.0),
                        ),
                      ),
                    ),
                  if (hasDiscount)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          '-$discountPercent%',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, height: 1.0),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  hasDiscount
                      ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '฿ ${_fmtBaht(discounted)}',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w800, fontSize: 14, height: 1.0),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '฿ ${_fmtBaht(priceRaw)}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          decoration: TextDecoration.lineThrough,
                          decorationThickness: 2,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          height: 1.0,
                        ),
                      ),
                    ],
                  )
                      : Text(
                    priceRaw == 0 ? '' : '฿ ${_fmtBaht(priceRaw)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.0),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
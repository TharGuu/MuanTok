// lib/screens/shop_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../services/voucher_service.dart'; // <-- live coupons service
import '../features/profile/voucher_screen.dart';
import 'promotion_screen.dart';
import 'product_detail_screen.dart';
import 'favourite_screen.dart';
import 'cart_screen.dart';

void _openFavourites(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const FavouriteScreen()),
  );
}

/* -------------------------------------------------------------------------- */
/*                               LUCID THEME TOKENS                           */
/* -------------------------------------------------------------------------- */

const kLucidPrimary = Color(0xFF7C3AED); // core purple
const kLucidPrimaryLite = Color(0xFFD8BEE5); // your requested icon tint
const kLucidShadow = Color(0x14000000);

const kLucidBg = Color(0xFFF5F3FF);
const kLucidSurface = Colors.white;
const kLucidText = Color(0xFF111827);
const kLucidMuted = Color(0xFF6B7280);
const kLucidBorder = Color(0xFFE5E7EB);

/* -------------------------------------------------------------------------- */
/*                        OUT-OF-STOCK VISIBILITY HELPERS                     */
/* -------------------------------------------------------------------------- */

bool _isAdminViewer() => SupabaseService.isAdmin;
String? _viewerUid() => SupabaseService.currentUserId;

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// Filter a list of products so buyers only see stock>0.
/// Admin or product owner still see everything.
List<Map<String, dynamic>> _visibleToViewer(List<Map<String, dynamic>> raw) {
  final isAdmin = _isAdminViewer();
  final me = _viewerUid();
  return raw.where((p) {
    final stock = _asInt(p['stock']);
    final sellerId = p['seller_id']?.toString();
    if (isAdmin || (me != null && me == sellerId)) return true; // admin/owner
    return stock > 0; // buyer: only in-stock
  }).toList();
}

/// true = viewer should be blocked from opening detail on this product
bool _isOutOfStockForViewer(Map<String, dynamic> p) {
  final stock = _asInt(p['stock']);
  if (stock > 0) return false;
  final me = _viewerUid();
  final sellerId = p['seller_id']?.toString();
  if (_isAdminViewer() || (me != null && me == sellerId)) return false;
  return true;
}

/* -------------------------------------------------------------------------- */
/*                               CATEGORY MODEL                               */
/* -------------------------------------------------------------------------- */

class _Category {
  final String key; // DB value in 'category' column
  final String label; // UI text
  final IconData icon;
  const _Category(this.key, this.label, this.icon);
}

// Keep in sync w/ DB
const _categories = <_Category>[
  _Category('Electronics', 'Electronics', Icons.electrical_services_rounded),
  _Category('Beauty', 'Beauty', Icons.spa_rounded),
  _Category('Fashion', 'Fashion', Icons.checkroom_rounded),
  _Category('Sport', 'Sport', Icons.sports_soccer_rounded),
  _Category('Food', 'Food', Icons.fastfood_rounded),
  _Category('Other', 'Other', Icons.category_rounded),
];

/* -------------------------------------------------------------------------- */
/*                               PRICE HELPERS                                */
/* -------------------------------------------------------------------------- */

String _fmtBaht(num value) {
  final s = value.toStringAsFixed(2);
  return s.endsWith('00') ? value.toStringAsFixed(0) : s;
}

num _parseNum(dynamic v) {
  if (v is num) return v;
  if (v is String) {
    final d = double.tryParse(v);
    if (d != null) return d;
  }
  return 0;
}

/* -------------------------------------------------------------------------- */
/*                                 SHOP SCREEN                                */
/* -------------------------------------------------------------------------- */

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  String selectedTab = 'Buy'; // 'Buy' | 'Sell'

  void _openSearch(BuildContext context) {
    showSearch(context: context, delegate: ProductSearchDelegate());
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: kLucidBg,
      body: Stack(
        children: [
          // body
          Positioned.fill(
            top: safe.top + 64,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: selectedTab == 'Buy'
                  ? const _BuyHome()
                  : const SellFormSection(key: ValueKey('sell-form')),
            ),
          ),

          // header row
          Positioned(
            top: safe.top + 10,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // buy/sell pill
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [kLucidPrimary, Color(0xFFFB7185)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: kLucidShadow,
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _togglePill(
                        label: 'Buy',
                        isSelected: selectedTab == 'Buy',
                        onTap: () => setState(() => selectedTab = 'Buy'),
                      ),
                      _togglePill(
                        label: 'Sell',
                        isSelected: selectedTab == 'Sell',
                        onTap: () => setState(() => selectedTab = 'Sell'),
                      ),
                    ],
                  ),
                ),

                Row(
                  children: [
                    // search icon (Buy tab only)
                    if (selectedTab == 'Buy') ...[
                      GestureDetector(
                        onTap: () => _openSearch(context),
                        child: const Icon(
                          Icons.search,
                          color: kLucidPrimary, // 💜 #D8BEE5
                          size: 28,
                          shadows: [Shadow(blurRadius: 2)],
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],

                    // favorite icon (heart) - visible on Buy tab
                    if (selectedTab == 'Buy') ...[
                      GestureDetector(
                        onTap: () => _openFavourites(context),
                        child: const Icon(
                          Icons.favorite_border_rounded,
                          color: kLucidPrimary, // 💜 #D8BEE5
                          size: 28,
                          shadows: [Shadow(blurRadius: 2)],
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],

                    // cart icon - visible on Buy tab
                    if (selectedTab == 'Buy') ...[
                      IconButton(
                        tooltip: 'My Cart',
                        icon: const Icon(
                          Icons.shopping_cart_outlined,
                          color: kLucidPrimary, // 💜 #D8BEE5
                          size: 28,
                          shadows: [Shadow(blurRadius: 2)],
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const CartScreen()),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _togglePill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kLucidSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? kLucidText : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                BUY HOME VIEW                               */
/* -------------------------------------------------------------------------- */

enum _RecSort { none, ratingHighLow, ratingLowHigh }

class _BuyHome extends StatefulWidget {
  const _BuyHome();
  @override
  State<_BuyHome> createState() => _BuyHomeState();
}

class _BuyHomeState extends State<_BuyHome> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _recommended = [];

  RealtimeChannel? _channel;
  StreamSubscription<void>? _debounce;

  // NEW: local sort for Recommended
  _RecSort _recSort = _RecSort.none;

  @override
  void initState() {
    super.initState();
    _fetchRecommended();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _debounce?.cancel();
    super.dispose();
  }

  num _ratingOf(Map<String, dynamic> p) {
    // prefer 'rating' then fallback to 'avg_rating' then 0
    final v = p['rating'] ?? p['avg_rating'] ?? 0;
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  Future<void> _enrichRatings(List<Map<String, dynamic>> items) async {
    final futures = <Future<void>>[];
    for (final p in items) {
      final pid = p['id'];
      if (pid is! int) continue;
      futures.add(() async {
        try {
          final agg = await SupabaseService.fetchRatingAggregate(pid);
          p['rating'] = agg['avg'] ?? p['rating'] ?? 0;
          p['rating_count'] = agg['count'] ?? p['rating_count'] ?? 0;
        } catch (_) {
          // ignore per-item errors
        }
      }());
    }
    await Future.wait(futures);
  }

  void _applyRecSort() {
    if (_recSort == _RecSort.none) return;
    _recommended.sort((a, b) {
      final ra = _ratingOf(a);
      final rb = _ratingOf(b);
      if (_recSort == _RecSort.ratingHighLow) {
        return rb.compareTo(ra); // high → low
      } else {
        return ra.compareTo(rb); // low → high
      }
    });
  }

  Future<void> _fetchRecommended() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // latest 6 products
      final list = await SupabaseService.listProducts(
        limit: 6,
        offset: 0,
        orderBy: 'id',
        ascending: false,
      );
      if (!mounted) return;
      final visible = _visibleToViewer(list);

      // hydrate ratings from product_ratings
      await _enrichRatings(visible);
      if (!mounted) return;

      setState(() {
        _recommended = visible;
        _applyRecSort(); // apply current rating sort locally
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    final client = Supabase.instance.client;
    _channel = client
        .channel('public:products')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'products',
      callback: (_) => _scheduleRefresh(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'products',
      callback: (_) => _scheduleRefresh(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'products',
      callback: (_) => _scheduleRefresh(),
    )
        .subscribe();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Stream<void>.periodic(const Duration(milliseconds: 250))
        .take(1)
        .listen((_) {
      if (mounted) _fetchRecommended();
    });
  }

  void _openCategory(BuildContext context, _Category c) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryProductsScreen(
          category: c.key,
          label: c.label,
          icon: c.icon,
        ),
      ),
    );
  }

  void _openViewAll() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AllProductsScreen()),
    );
  }

  // pick which asset banner to show for each event
  String _bannerForEvent(EventInfo ev) {
    final lower = ev.name.toLowerCase();

    if (lower.contains('promo') || lower.contains('promotion')) {
      return 'assets/banners/promotion.png';
    }
    if (lower.contains('christmas') ||
        lower.contains('xmas') ||
        lower.contains('holiday')) {
      return 'assets/banners/christmas_sale.png';
    }
    return 'assets/banners/default_event.png';
  }

  PopupMenuButton<_RecSort> _recSortMenu() {
    return PopupMenuButton<_RecSort>(
      tooltip: 'Sort Recommended',
      initialValue: _recSort,
      onSelected: (value) {
        setState(() {
          _recSort = value;
          _applyRecSort();
        });
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: _RecSort.none, child: Text('Default')),
        PopupMenuItem(
            value: _RecSort.ratingHighLow,
            child: Text('Rating: High → Low')),
        PopupMenuItem(
            value: _RecSort.ratingLowHigh,
            child: Text('Rating: Low → High')),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.sort, size: 18, color: kLucidMuted),
          SizedBox(width: 6),
          Text(
            'Sort',
            style: TextStyle(fontSize: 12, color: kLucidText),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: kLucidPrimary,
      onRefresh: () async {
        await _fetchRecommended();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 8),

          // Categories carousel
          SizedBox(
            height: 140,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final c = _categories[i];
                return _CategoryCard(
                  icon: c.icon,
                  label: c.label,
                  selected: false,
                  onTap: () => _openCategory(context, c),
                  width: 160,
                  showSwipeHint: true,
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Coupons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Coupons',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: kLucidText,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const CouponsSection(),

          const SizedBox(height: 16),

          // 🔥 EVENT / PROMOTIONS SECTION
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Event',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: kLucidText,
              ),
            ),
          ),
          const SizedBox(height: 8),

          FutureBuilder<List<EventInfo>>(
            future: SupabaseService.fetchActiveEvents(),
            builder: (context, snap) {
              // loading state
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 180,
                  child: Center(
                      child: CircularProgressIndicator(color: kLucidPrimary)),
                );
              }

              // error state
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: kLucidSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Failed to load events:\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }

              final events = snap.data ?? const <EventInfo>[];
              if (events.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: kLucidSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kLucidBorder),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'No active events',
                      style: TextStyle(
                        color: kLucidMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }

              return SizedBox(
                height: 180,
                child: PageView.builder(
                  controller: PageController(viewportFraction: 0.88),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final ev = events[index];
                    final bannerAsset = _bannerForEvent(ev);

                    final endsText = ev.endsAtDisplay.isNotEmpty
                        ? '🔥 Ends ${ev.endsAtDisplay}'
                        : 'Limited time';

                    return _EventBannerDynamicCard(
                      heroTag: 'event_${ev.id}',
                      eventName: ev.name,
                      bannerAsset: bannerAsset,
                      endsText: endsText,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PromotionScreen(
                              eventId: ev.id,
                              eventName: ev.name,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // Recommended header + rating sort + View all
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Recommended for you',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: kLucidText,
                  ),
                ),
                const Spacer(),
                _recSortMenu(),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: _openViewAll,
                  child: const Text(
                    'View all',
                    style: TextStyle(
                      fontSize: 12,
                      color: kLucidPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(
                  child: CircularProgressIndicator(color: kLucidPrimary)),
            )
          else if (_error != null)
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            )
          else if (_recommended.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Text(
                  'No products yet.',
                  style: TextStyle(color: kLucidMuted),
                ),
              )
            else
              const SizedBox.shrink(),
          if (_recommended.isNotEmpty) _ProductGrid(products: _recommended),
        ],
      ),
    );
  }
}

/* --------------------------- EVENT BANNER CARD --------------------------- */

class _EventBannerDynamicCard extends StatelessWidget {
  final String heroTag;
  final String eventName;
  final String bannerAsset; // local PNG path
  final String endsText;
  final VoidCallback onTap;

  const _EventBannerDynamicCard({
    required this.heroTag,
    required this.eventName,
    required this.bannerAsset,
    required this.endsText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // spacing between banners
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Hero(
          tag: heroTag,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Image.asset(
                    bannerAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) {
                      return Container(
                        color: Colors.grey.shade300,
                        child: const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.black54,
                            size: 32,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // slight overlay for readable text
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.25),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 12,
                  right: 12,
                  child: Text(
                    eventName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                          blurRadius: 4,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      endsText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ------------------------------ CATEGORY CARD ------------------------------ */

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double width;
  final bool showSwipeHint;

  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.width = 160,
    this.showSwipeHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = selected;

    final Color bg = isSelected ? kLucidPrimary : kLucidSurface;
    final Color borderColor = isSelected ? kLucidPrimary : kLucidBorder;
    final Color iconColor = isSelected ? Colors.white : kLucidPrimary;
    final Color textColor = isSelected ? Colors.white : kLucidText;
    final Color hintColor =
    isSelected ? Colors.white.withOpacity(0.8) : kLucidMuted;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: width,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor,
            width: 1.3,
          ),
          boxShadow: const [
            BoxShadow(
              color: kLucidShadow,
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon in a soft circular chip
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? Colors.white.withOpacity(0.16)
                    : kLucidPrimary.withOpacity(0.08),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 28,
              ),
            ),
            const SizedBox(height: 10),

            // Label
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),

            if (showSwipeHint) ...[
              const SizedBox(height: 4),
              Text(
                'Tap to browse',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hintColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/* ------------------------------ PRODUCT GRID ------------------------------ */

class _ProductGrid extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  const _ProductGrid({required this.products});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62, // taller tiles → avoids bottom overflow
      ),
      itemBuilder: (_, i) => _ProductCard(data: products[i]),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ProductCard({required this.data});

  List<String> _extractImageUrls(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (v is String) {
      return [v];
    }
    return const [];
  }

  double _extractRating(Map<String, dynamic> p) {
    final v = p['rating'] ?? p['avg_rating'] ?? p['avgRating'] ?? 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
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
    final isEvent = (data['is_event'] == true);
    final discountPercent = (data['discount_percent'] is int)
        ? data['discount_percent'] as int
        : int.tryParse('${data['discount_percent'] ?? 0}') ?? 0;

    final bool hasDiscount = isEvent && discountPercent > 0 && priceRaw > 0;
    final num discounted =
    hasDiscount ? (priceRaw * (100 - discountPercent)) / 100 : priceRaw;

    final rating = _extractRating(data);

    final sellerId = (data['seller_id'] ?? data['sellerId'] ?? '').toString();

    final Map<String, dynamic>? sellerMap =
        (data['seller'] is Map ? data['seller'] as Map<String, dynamic> : null) ??
            (data['users'] is Map ? data['users'] as Map<String, dynamic> : null) ??
            (data['profiles'] is Map
                ? data['profiles'] as Map<String, dynamic>
                : null);

    final sellerNameFromRow = (sellerMap?['full_name'] ??
        data['seller_full_name'] ??
        data['full_name'] ??
        data['seller_name'])
        ?.toString();

    final stock = _asInt(data['stock']);
    final showOutBadge =
        stock <= 0 && !_isOutOfStockForViewer(data); // admin/owner badge

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (_isOutOfStockForViewer(data)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Out of stock')),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(
                productId: data['id'] as int,
                initialData: data,
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: kLucidSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kLucidBorder),
            boxShadow: const [
              BoxShadow(
                color: kLucidShadow,
                blurRadius: 15,
                offset: Offset(0, 8),
              ),
            ],
          ),
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
                        color: kLucidBg,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: kLucidMuted,
                        ),
                      )
                          : Image.network(img, fit: BoxFit.cover),
                    ),
                    if (category.isNotEmpty)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _CategoryValueBadge(text: category),
                      ),
                    if (hasDiscount)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: _DiscountBadge(percent: discountPercent),
                      ),
                    if (showOutBadge)
                      Positioned(
                        left: 8,
                        top: 8 + (category.isNotEmpty ? 28 : 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.70),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'OUT OF STOCK',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                            ),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // name
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: kLucidText,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // ⭐ Rating row
                    _StarRating(
                      rating: rating,
                      size: 13,
                      color: kLucidPrimary,
                      showNumber: true,
                    ),

                    const SizedBox(height: 4),

                    // price / discount
                    hasDiscount
                        ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '฿ ${_fmtBaht(discounted)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '฿ ${_fmtBaht(priceRaw)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kLucidMuted,
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
                      priceRaw == 0
                          ? ''
                          : '฿ ${_fmtBaht(priceRaw)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.0,
                        color: Color(0xFFDC2626),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // seller row
                    Row(
                      children: [
                        const Icon(
                          Icons.storefront_rounded,
                          size: 13,
                          color: kLucidMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: sellerNameFromRow != null &&
                              sellerNameFromRow.isNotEmpty
                              ? Text(
                            sellerNameFromRow,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: kLucidMuted,
                              height: 1.0,
                            ),
                          )
                              : _SellerName(sellerId: sellerId),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* --------------------------- CATEGORY PRODUCTS ---------------------------- */

class CategoryProductsScreen extends StatefulWidget {
  final String category;
  final String label;
  final IconData icon;
  const CategoryProductsScreen({
    super.key,
    required this.category,
    required this.label,
    required this.icon,
  });

  @override
  State<CategoryProductsScreen> createState() =>
      _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _enrichRatings(List<Map<String, dynamic>> items) async {
    final futures = <Future<void>>[];
    for (final p in items) {
      final pid = p['id'];
      if (pid is! int) continue;
      futures.add(() async {
        try {
          final agg = await SupabaseService.fetchRatingAggregate(pid);
          p['rating'] = agg['avg'] ?? p['rating'] ?? 0;
          p['rating_count'] = agg['count'] ?? p['rating_count'] ?? 0;
        } catch (_) {}
      }());
    }
    await Future.wait(futures);
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fetched = await SupabaseService.listProducts(
        category: widget.category,
        limit: 60,
        offset: 0,
        orderBy: 'id',
        ascending: false,
      );

      // ensure only correct category (safety) + apply visibility
      final cleaned = fetched.where((p) {
        final cat = (p['category'] ?? '').toString().trim();
        return cat == widget.category;
      }).toList();

      final visible = _visibleToViewer(cleaned);

      // hydrate ratings
      await _enrichRatings(visible);
      if (!mounted) return;

      setState(() => _items = visible);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 0,
        backgroundColor: kLucidBg,
        foregroundColor: kLucidText,
        title: Row(
          children: [
            Icon(widget.icon, size: 20, color: kLucidPrimary),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: const TextStyle(
                color: kLucidText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      backgroundColor: kLucidBg,
      body: RefreshIndicator(
        color: kLucidPrimary,
        onRefresh: _fetch,
        child: _loading
            ? const Center(
          child: CircularProgressIndicator(color: kLucidPrimary),
        )
            : _error != null
            ? Center(
          child: Text(
            'Error: $_error',
            style: const TextStyle(color: Colors.red),
          ),
        )
            : _items.isEmpty
            ? const Center(
          child: Text(
            'No products in this category.',
            style: TextStyle(color: kLucidMuted),
          ),
        )
            : _ProductGrid(products: _items),
      ),
    );
  }
}

/* ------------------------------ VIEW ALL SCREEN --------------------------- */

enum _AllSort {
  newest,
  priceLowHigh,
  priceHighLow,
  ratingHighLow,
  ratingLowHigh,
}

class AllProductsScreen extends StatefulWidget {
  const AllProductsScreen({super.key});
  @override
  State<AllProductsScreen> createState() => _AllProductsScreenState();
}

class _AllProductsScreenState extends State<AllProductsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  _AllSort _sort = _AllSort.newest;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  String _labelForSort(_AllSort value) {
    switch (value) {
      case _AllSort.newest:
        return 'Newest';
      case _AllSort.priceLowHigh:
        return 'Price: Low → High';
      case _AllSort.priceHighLow:
        return 'Price: High → Low';
      case _AllSort.ratingHighLow:
        return 'Rating: High → Low';
      case _AllSort.ratingLowHigh:
        return 'Rating: Low → High';
    }
  }

  Future<void> _enrichRatings(List<Map<String, dynamic>> items) async {
    final futures = <Future<void>>[];
    for (final p in items) {
      final pid = p['id'];
      if (pid is! int) continue;
      futures.add(() async {
        try {
          final agg = await SupabaseService.fetchRatingAggregate(pid);
          p['rating'] = agg['avg'] ?? p['rating'] ?? 0;
          p['rating_count'] = agg['count'] ?? p['rating_count'] ?? 0;
        } catch (_) {}
      }());
    }
    await Future.wait(futures);
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    String orderBy = 'id';
    bool ascending = false;

    switch (_sort) {
      case _AllSort.newest:
        orderBy = 'id';
        ascending = false;
        break;
      case _AllSort.priceLowHigh:
        orderBy = 'price';
        ascending = true;
        break;
      case _AllSort.priceHighLow:
        orderBy = 'price';
        ascending = false;
        break;
      case _AllSort.ratingHighLow:
        orderBy = 'rating';
        ascending = false;
        break;
      case _AllSort.ratingLowHigh:
        orderBy = 'rating';
        ascending = true;
        break;
    }

    try {
      final list = await SupabaseService.listProducts(
        limit: 120,
        offset: 0,
        orderBy: orderBy,
        ascending: ascending,
      );
      if (!mounted) return;
      final visible = _visibleToViewer(list);

      // hydrate ratings for All Products
      await _enrichRatings(visible);
      if (!mounted) return;

      setState(() => _items = visible);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Lucid-style app bar
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        elevation: 0,
        backgroundColor: kLucidBg,
        foregroundColor: kLucidText,
        title: const Text(
          'All Products',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: kLucidText,
          ),
        ),
      ),
      backgroundColor: kLucidBg,
      body: RefreshIndicator(
        color: kLucidPrimary,
        onRefresh: _fetch,
        child: _loading
            ? const Center(
          child: CircularProgressIndicator(color: kLucidPrimary),
        )
            : _error != null
            ? ListView(
          children: [
            const SizedBox(height: 24),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Error loading products\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ],
        )
            : ListView(
          children: [
            const SizedBox(height: 8),

            // 🔽 Lucid purple sort dropdown bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: kLucidSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: kLucidBorder,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: kLucidShadow,
                      blurRadius: 14,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Purple icon + title
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kLucidPrimary.withOpacity(0.08),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: kLucidPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Sort by',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kLucidText,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Dropdown
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<_AllSort>(
                          isExpanded: true,
                          value: _sort,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: kLucidMuted,
                          ),
                          items: _AllSort.values.map((value) {
                            return DropdownMenuItem<_AllSort>(
                              value: value,
                              child: Text(
                                _labelForSort(value),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: kLucidText,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _sort = value);
                            _fetch();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Product content
            _items.isEmpty
                ? const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: Center(
                child: Text(
                  'No products yet.',
                  style: TextStyle(
                    color: kLucidMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
                : _ProductGrid(products: _items),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                         SELL FORM (UPDATED VERSION)                        */
/* -------------------------------------------------------------------------- */

class ProductInput {
  final List<PickedImage> images;
  final String name;
  final String description;
  final String category;
  final double price;
  final int stock;

  ProductInput({
    required this.images,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.stock,
  });
}

// raw picked image from camera/gallery
class PickedImage {
  final Uint8List bytes;
  final String name;
  PickedImage(this.bytes, this.name);
}

/// Wrapper so `ShopScreen` can just show SellFormSection in Sell tab
class SellFormSection extends StatelessWidget {
  const SellFormSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const SellForm();
  }
}

/// Full seller form with multi-event support
class SellForm extends StatefulWidget {
  const SellForm({super.key});

  @override
  State<SellForm> createState() => _SellFormState();
}

class _SellFormState extends State<SellForm> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '1');

  final _picker = ImagePicker();
  final List<PickedImage> _images = [];

  String? _category;
  bool _submitting = false;

  // events from SupabaseService
  List<EventInfo> _availableEvents = [];
  bool _loadingEvents = true;

  // eventId -> discountPercent
  final Map<int, int> _selectedEvents = {};

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    try {
      final events = await SupabaseService.fetchActiveEvents();
      if (!mounted) return;
      setState(() {
        _availableEvents = events;
        _loadingEvents = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _availableEvents = [];
        _loadingEvents = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load events: $e')),
      );
    }
  }

  Future<void> _addFromGallery() async {
    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (files.isEmpty) return;
      for (final f in files) {
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) continue;
        _images.add(PickedImage(bytes, f.name));
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gallery pick failed: $e')),
      );
    }
  }

  Future<void> _addFromCamera() async {
    try {
      final f = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) return;
      setState(() => _images.add(PickedImage(bytes, f.name)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera failed: $e')),
      );
    }
  }

  void _removeAt(int index) => setState(() => _images.removeAt(index));

  void _openFullScreen(int startIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenGallery(
          images: _images,
          initialIndex: startIndex,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add product photos.')),
      );
      return;
    }
    if (_formKey.currentState?.validate() != true) return;

    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;
    final category = _category ?? _categories.first.key;

    final productInput = ProductInput(
      images: List.unmodifiable(_images),
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      category: category,
      price: price,
      stock: stock,
    );

    setState(() => _submitting = true);

    try {
      // 1) upload images
      final sellerId = SupabaseService.requireUserId();
      final urls = await SupabaseService.uploadProductImages(
        images: _images
            .map((p) => ImageToUpload(bytes: p.bytes, fileName: p.name))
            .toList(),
        userId: sellerId,
      );

      // 2) create product row
      final inserted = await SupabaseService.insertProduct(
        sellerId: sellerId,
        name: productInput.name,
        description: productInput.description,
        category: productInput.category,
        price: productInput.price,
        stock: productInput.stock,
        imageUrls: urls,
        // keep legacy cols for backward compat
        isEvent: false,
        discountPercent: 0,
      );

      final productId = inserted['id'] as int;

      // 3) link product to selected events
      final selectedSnapshot = Map<int, int>.from(_selectedEvents);

      for (final entry in selectedSnapshot.entries) {
        final eventId = entry.key;
        final discountPct = entry.value;

        debugPrint(
          'attachProductToEvent -> product $productId event $eventId discountPct $discountPct',
        );

        await SupabaseService.attachProductToEvent(
          productId: productId,
          eventId: eventId,
          discountPct: discountPct,
        );
      }

      if (!mounted) return;

      // reset form
      setState(() {
        _images.clear();
        _nameCtrl.clear();
        _descCtrl.clear();
        _priceCtrl.clear();
        _stockCtrl.text = '1';
        _category = null;
        _selectedEvents.clear();
      });

      // success toast
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ ${inserted['name']} published in ${selectedSnapshot.length} event(s)',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: kLucidBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // PHOTOS
              Row(
                children: [
                  const Text(
                    'Photos',
                    style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _addFromCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_images.isEmpty)
                Container(
                  height: 160,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kLucidSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kLucidBorder),
                  ),
                  child: Text(
                    'Add multiple photos',
                    style: TextStyle(color: kLucidMuted),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _images.length,
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemBuilder: (context, i) {
                    final p = _images[i];
                    return GestureDetector(
                      onTap: () => _openFullScreen(i),
                      onLongPress: () => _removeAt(i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          p.bytes,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 16),

              // PRODUCT NAME
              _LightInput(
                controller: _nameCtrl,
                label: 'Product name',
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Product name is required'
                    : null,
              ),
              const SizedBox(height: 12),

              // DESCRIPTION
              _LightInput(
                controller: _descCtrl,
                label: 'Description',
                maxLines: 4,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Description is required'
                    : null,
              ),
              const SizedBox(height: 12),

              // CATEGORY DROPDOWN
              _LightDropdown(
                value: _category == null
                    ? null
                    : _categories.firstWhere((c) => c.key == _category).label,
                items: _categories.map((c) => c.label).toList(),
                label: 'Category',
                onChanged: (val) {
                  final found =
                  _categories.firstWhere((c) => c.label == val);
                  setState(() => _category = found.key);
                },
                validator: (v) =>
                (v == null || v.isEmpty) ? 'Select a category' : null,
              ),
              const SizedBox(height: 12),

              // PRICE + STOCK
              Row(
                children: [
                  Expanded(
                    child: _LightInput(
                      controller: _priceCtrl,
                      label: 'Price',
                      prefixText: '฿ ',
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
                      ],
                      validator: (v) {
                        final val = double.tryParse((v ?? '').trim());
                        if (val == null) return 'Enter a number';
                        if (val <= 0) return 'Price must be > 0';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LightInput(
                      controller: _stockCtrl,
                      label: 'Stock',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      validator: (v) {
                        final val = int.tryParse((v ?? '').trim());
                        if (val == null) return 'Enter stock';
                        if (val < 0) return 'Stock must be ≥ 0';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // EVENT SELECTION BLOCK (multi select)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add to Events',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: kLucidText,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              if (_loadingEvents)
                const LinearProgressIndicator(
                    minHeight: 2, color: kLucidPrimary)
              else if (_availableEvents.isEmpty)
                Text(
                  'No active events',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kLucidMuted,
                  ),
                )
              else
                Column(
                  children: [
                    for (final ev in _availableEvents) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _selectedEvents.containsKey(ev.id),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedEvents.putIfAbsent(ev.id, () => 0);
                                } else {
                                  _selectedEvents.remove(ev.id);
                                }
                              });
                            },
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // event name
                                Text(
                                  ev.name,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: kLucidText,
                                  ),
                                ),

                                // "Ends Dec 31, 2025"
                                if (ev.endsAtDisplay.isNotEmpty)
                                  Text(
                                    'Ends ${ev.endsAtDisplay}',
                                    style:
                                    theme.textTheme.bodySmall?.copyWith(
                                      color: kLucidMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                const SizedBox(height: 8),

                                // discount field if selected
                                if (_selectedEvents.containsKey(ev.id))
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 110,
                                        child: TextFormField(
                                          initialValue:
                                          _selectedEvents[ev.id]
                                              ?.toString() ??
                                              '0',
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            labelText: 'Discount (%)',
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (val) {
                                            final parsed =
                                                int.tryParse(val) ?? 0;
                                            setState(() {
                                              _selectedEvents[ev.id] =
                                                  parsed.clamp(0, 100);
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),

              const SizedBox(height: 24),

              // PUBLISH
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _submitting
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.publish_outlined),
                  label: Text(_submitting ? 'Publishing...' : 'Publish'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kLucidPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _submitting ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ----------------------------- Fullscreen viewer ---------------------------- */

class FullscreenGallery extends StatefulWidget {
  final List<PickedImage> images;
  final int initialIndex;
  const FullscreenGallery({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  State<FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<FullscreenGallery> {
  late final PageController _ctrl =
  PageController(initialPage: widget.initialIndex);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _ctrl,
              itemCount: widget.images.length,
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Center(
                  child: Image.memory(
                    widget.images[i].bytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* --------------------------- UI HELPERS / WIDGETS -------------------------- */

class _CategoryValueBadge extends StatelessWidget {
  final String text;
  const _CategoryValueBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  final int percent;
  const _DiscountBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '-$percent%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}

/* ------------------------------ STAR RATING -------------------------------- */

class _StarRating extends StatelessWidget {
  final double rating; // 0..5
  final double size; // icon size
  final bool showNumber; // show numeric score
  final Color color; // star color (Lucid purple)

  const _StarRating({
    super.key,
    required this.rating,
    this.size = 12,
    this.showNumber = true,
    this.color = kLucidPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final r = rating.clamp(0, 5).toDouble();
    final stars = <Widget>[];
    for (int i = 1; i <= 5; i++) {
      final icon = r >= i
          ? Icons.star_rounded
          : (r >= i - 0.5
          ? Icons.star_half_rounded
          : Icons.star_border_rounded);
      stars.add(Icon(icon, size: size, color: color));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...stars,
        if (showNumber) ...[
          const SizedBox(width: 6),
          Text(
            r.toStringAsFixed(1),
            style: TextStyle(
              fontSize: size - 1,
              fontWeight: FontWeight.w700,
              height: 1,
              color: kLucidText,
            ),
          ),
        ],
      ],
    );
  }
}

/* ------------------------- SELLER NAME (lazy cached) ----------------------- */

class _SellerName extends StatefulWidget {
  final String sellerId;
  const _SellerName({required this.sellerId});

  @override
  State<_SellerName> createState() => _SellerNameState();
}

class _SellerNameState extends State<_SellerName> {
  static final Map<String, String> _cache = {};
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchFullName();
  }

  Future<String> _fetchFullName() async {
    if (widget.sellerId.isEmpty) return 'Unknown seller';
    if (_cache.containsKey(widget.sellerId)) {
      return _cache[widget.sellerId]!;
    }

    try {
      final sb = Supabase.instance.client;
      final rows = await sb
          .from('users')
          .select('full_name, username, name')
          .eq('id', widget.sellerId)
          .limit(1);

      if (rows is List && rows.isNotEmpty) {
        final r = rows.first as Map<String, dynamic>;
        final fullName =
        (r['full_name'] ?? r['username'] ?? r['name'] ?? 'Unknown seller')
            .toString();
        _cache[widget.sellerId] = fullName;
        return fullName;
      }
    } catch (e) {
      debugPrint('Error fetching seller name: $e');
    }

    return 'Unknown seller';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (_, snap) {
        final txt = snap.data ?? 'Unknown seller';
        return Text(
          txt,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
            height: 1.0,
          ),
        );
      },
    );
  }
}

/* ----------------------- LIVE COUPONS UI (Lucid Purple) -------------------- */

class CouponsSection extends StatefulWidget {
  const CouponsSection({super.key});
  @override
  State<CouponsSection> createState() => _CouponsSectionState();
}

/* local tokens */
const _lcPrimary = Color(0xFF7C3AED);
const _lcPrimary2 = Color(0xFF9B8AFB);
const _lcMuted = Color(0xFF6B7280);
const _lcDanger = Color(0xFFE11D48);

BoxDecoration _lcGlass([double r = 12]) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(r),
  border: Border.all(color: const Color(0x11000000)),
  boxShadow: const [
    BoxShadow(
        color: Color(0x14000000),
        blurRadius: 12,
        offset: Offset(0, 6))
  ],
);

class _CouponsSectionState extends State<CouponsSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future =
        VoucherService.fetchActiveCoupons(excludeAlreadyClaimed: true);
  }

  Future<void> _refresh() async {
    setState(() {
      _future =
          VoucherService.fetchActiveCoupons(excludeAlreadyClaimed: true);
    });
  }

  String _subtitle(Map<String, dynamic> c) {
    final type = (c['discount_type'] ?? '').toString();
    final val = c['discount_value'];
    if (type == 'percent') {
      final pct = int.tryParse('$val') ?? 0;
      return 'Save $pct%';
    }
    if (type == 'amount') {
      final amt = num.tryParse('$val') ?? 0;
      return 'Save ฿ ${_fmtBaht(amt)}';
    }
    return (c['description'] ?? 'Coupon').toString();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
                child: CircularProgressIndicator(color: _lcPrimary)),
          );
        }

        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 120,
              alignment: Alignment.center,
              decoration: _lcGlass(12).copyWith(
                border:
                Border.all(color: const Color(0x26E11D48)),
              ),
              child: Text(
                'Failed to load coupons:\n${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _lcDanger),
              ),
            ),
          );
        }

        final coupons = snap.data ?? const [];
        if (coupons.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 120,
              alignment: Alignment.center,
              decoration: _lcGlass(12),
              child: const Text('No coupons available',
                  style: TextStyle(
                      color: _lcMuted,
                      fontWeight: FontWeight.w600)),
            ),
          );
        }

        return SizedBox(
          height: 140,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemCount: coupons.length,
            itemBuilder: (context, i) {
              final c = coupons[i];
              final title = (c['title'] ?? 'Coupon').toString();
              final code = (c['code'] ?? '').toString();

              return Container(
                width: 240,
                padding: const EdgeInsets.all(12),
                decoration: _lcGlass(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                                colors: [_lcPrimary, _lcPrimary2]),
                          ),
                          child: const Icon(
                              Icons.local_offer_rounded,
                              color: Colors.white,
                              size: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Subtitle only
                    Text(
                      _subtitle(c),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: _lcMuted),
                    ),

                    const Spacer(),

                    // Claim button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            await VoucherService
                                .claimCouponByCode(code);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                content: Text(
                                    '🎉 Coupon claimed: $title')));
                            await _refresh();
                          } on StateError catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                content: Text(e.message)));
                          } on PostgrestException catch (e) {
                            if (!mounted) return;
                            final msg = (e.code == '23505')
                                ? 'You already claimed this coupon.'
                                : (e.code == '42501')
                                ? 'Permission denied.'
                                : (e.message ??
                                'Cannot claim coupon.');
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                content: Text(msg)));
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                content:
                                Text('Error: $e')));
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding:
                          const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(10)),
                          foregroundColor: Colors.white,
                          backgroundColor: _lcPrimary,
                        ),
                        child: const Text('Claim'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/* ------------------------------ INPUT WIDGETS ------------------------------ */

class _LightInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? prefixText;
  final int maxLines;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;

  const _LightInput({
    required this.controller,
    required this.label,
    this.prefixText,
    this.maxLines = 1,
    this.validator,
    this.inputFormatters,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefixText,
        filled: true,
        fillColor: kLucidSurface,
        labelStyle: const TextStyle(color: kLucidMuted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kLucidBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
          const BorderSide(color: kLucidPrimary, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }
}

class _LightDropdown extends FormField<String> {
  _LightDropdown({
    super.key,
    required String? value,
    required List<String> items,
    required String label,
    required FormFieldSetter<String?> onChanged,
    String? Function(String?)? validator,
  }) : super(
    validator: validator,
    initialValue: value,
    builder: (state) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: kLucidSurface,
          labelStyle: const TextStyle(color: kLucidMuted),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
            const BorderSide(color: kLucidBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
                color: kLucidPrimary, width: 1.5),
          ),
          errorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.redAccent),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: state.value,
            isExpanded: true,
            items: items
                .map(
                  (e) => DropdownMenuItem<String>(
                value: e,
                child: Text(e),
              ),
            )
                .toList(),
            onChanged: (val) {
              state.didChange(val);
              onChanged(val);
            },
          ),
        ),
      );
    },
  );
}

/* ---------------------------- PRODUCT SEARCH ---------------------------- */

enum _SearchSort {
  relevance,
  priceLowHigh,
  priceHighLow,
  ratingHighLow,
  ratingLowHigh,
}

class ProductSearchDelegate extends SearchDelegate<String?> {
  final _sb = Supabase.instance.client;

  @override
  String? get searchFieldLabel => 'Search products by name';

  @override
  TextInputType get keyboardType => TextInputType.text;

  @override
  TextStyle? get searchFieldStyle => const TextStyle(
    color: kLucidText,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      scaffoldBackgroundColor: kLucidBg,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: kLucidBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: kLucidPrimary),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(
          color: kLucidMuted,
          fontSize: 15,
        ),
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: const TextStyle(
          color: kLucidText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear, color: kLucidMuted),
          onPressed: () => query = '',
          tooltip: 'Clear',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: kLucidPrimary),
      onPressed: () => close(context, null),
      tooltip: 'Back',
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _SearchList(queryText: query.trim(), sb: _sb);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _SearchList(queryText: query.trim(), sb: _sb);
  }
}

// pulls products from Supabase based on queryText + filter/sort
class _SearchList extends StatefulWidget {
  final String queryText;
  final SupabaseClient sb;
  const _SearchList({required this.queryText, required this.sb});

  @override
  State<_SearchList> createState() => _SearchListState();
}

class _SearchListState extends State<_SearchList> {
  late Future<List<Map<String, dynamic>>> _future;

  _SearchSort _sort = _SearchSort.relevance;
  String _selectedCategory = 'All'; // uses same categories as shop

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  double _ratingOf(Map<String, dynamic> p) {
    final v = p['rating'] ?? p['avg_rating'] ?? p['avgRating'] ?? 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  String _sortLabel(_SearchSort s) {
    switch (s) {
      case _SearchSort.relevance:
        return 'Relevance';
      case _SearchSort.priceLowHigh:
        return 'Price: Low → High';
      case _SearchSort.priceHighLow:
        return 'Price: High → Low';
      case _SearchSort.ratingHighLow:
        return 'Rating: High → Low';
      case _SearchSort.ratingLowHigh:
        return 'Rating: Low → High';
    }
  }

  List<Map<String, dynamic>> _applyFilterAndSort(
      List<Map<String, dynamic>> items) {
    // 1) Category filter
    final filteredByCategory = _selectedCategory == 'All'
        ? items
        : items.where((p) {
      final cat = (p['category'] ?? '').toString();
      return cat == _selectedCategory;
    }).toList();

    // 2) Sort
    final list = [...filteredByCategory];

    switch (_sort) {
      case _SearchSort.relevance:
      // keep current order (id desc from fetch)
        break;
      case _SearchSort.priceLowHigh:
        list.sort(
                (a, b) => _parseNum(a['price']).compareTo(_parseNum(b['price'])));
        break;
      case _SearchSort.priceHighLow:
        list.sort(
                (a, b) => _parseNum(b['price']).compareTo(_parseNum(a['price'])));
        break;
      case _SearchSort.ratingHighLow:
        list.sort((a, b) => _ratingOf(b).compareTo(_ratingOf(a)));
        break;
      case _SearchSort.ratingLowHigh:
        list.sort((a, b) => _ratingOf(a).compareTo(_ratingOf(b)));
        break;
    }

    return list;
  }

  Future<void> _enrichRatings(List<Map<String, dynamic>> items) async {
    final futures = <Future<void>>[];
    for (final p in items) {
      final pid = p['id'];
      if (pid is! int) continue;
      futures.add(() async {
        try {
          final agg = await SupabaseService.fetchRatingAggregate(pid);
          p['rating'] = agg['avg'] ?? p['rating'] ?? 0;
          p['rating_count'] = agg['count'] ?? p['rating_count'] ?? 0;
        } catch (_) {}
      }());
    }
    await Future.wait(futures);
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    // 1. Get recent products from Supabase
    final rows = await widget.sb
        .from('products')
        .select('''
          id,
          name,
          description,
          category,
          price,
          stock,
          image_urls,
          is_event,
          discount_percent,
          seller_id,
          seller:users!products_seller_id_fkey(full_name),
          rating
        ''')
        .order('id', ascending: false)
        .limit(120);

    // 2. Cast once
    final list = (rows as List).cast<Map<String, dynamic>>();

    // 3. Local text filter: by NAME (description as extra)
    final q = widget.queryText.trim().toLowerCase();
    final filtered = q.isEmpty
        ? list
        : list.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final desc = (p['description'] ?? '').toString().toLowerCase();
      // primary: name.contains(q); desc is bonus
      return name.contains(q) || desc.contains(q);
    }).toList();

    // 4. Normalize seller for safety
    for (final p in filtered) {
      final sellerMap = p['seller'];
      if (sellerMap == null) {
        final fallbackName = p['seller_full_name'];
        p['seller'] = {
          'full_name': fallbackName ?? 'Unknown Seller',
        };
      } else if (sellerMap is! Map<String, dynamic>) {
        p['seller'] = {
          'full_name': sellerMap.toString(),
        };
      } else {
        p['seller']['full_name'] ??= 'Unknown Seller';
      }
    }

    // 5. Pull best discount for each product from product_events
    final productIds =
    filtered.map((p) => p['id']).whereType<int>().toList();

    final bestMap =
    await SupabaseService.fetchBestDiscountMapForProducts(productIds);

    for (final p in filtered) {
      final pid = p['id'] as int?;
      if (pid != null && bestMap.containsKey(pid)) {
        p['discount_percent'] = bestMap[pid]; // override with best discount
        p['is_event'] = true; // mark this as an event deal
      }
    }

    // 6. Apply visibility rule so buyers don't see stock=0 in search either
    final visible = _visibleToViewer(filtered);

    // 7. Hydrate ratings as well
    await _enrichRatings(visible);

    return visible;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: kLucidPrimary));
        }
        if (snap.hasError) {
          return _SearchErrorState(error: snap.error.toString());
        }
        final raw = snap.data ?? const [];
        if (raw.isEmpty) {
          return const _SearchEmptyState(message: 'No products found');
        }

        final items = _applyFilterAndSort(raw);

        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const SizedBox(height: 8),

            // 💜 Lucid Filter + Sort bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: kLucidSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kLucidBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: kLucidShadow,
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: const [
                        Icon(
                          Icons.filter_alt_rounded,
                          size: 18,
                          color: kLucidPrimary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Filter & sort',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kLucidText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Category + Sort dropdowns
                    Row(
                      children: [
                        // Category filter
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _selectedCategory,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: kLucidMuted,
                                size: 20,
                              ),
                              items: const [
                                'All',
                                'Electronics',
                                'Beauty',
                                'Fashion',
                                'Sport',
                                'Food',
                                'Other',
                              ].map((cat) {
                                return DropdownMenuItem<String>(
                                  value: cat,
                                  child: Text(
                                    cat,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: kLucidText,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() => _selectedCategory = val);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Sort dropdown (rating + price)
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<_SearchSort>(
                              isExpanded: true,
                              value: _sort,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: kLucidMuted,
                                size: 20,
                              ),
                              items: _SearchSort.values.map((s) {
                                return DropdownMenuItem<_SearchSort>(
                                  value: s,
                                  child: Text(
                                    _sortLabel(s),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: kLucidText,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() => _sort = val);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Product grid using your existing Lucid cards
            _ProductGrid(products: items),
          ],
        );
      },
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  final String message;
  const _SearchEmptyState({required this.message});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 40),
        Center(
          child: Text(
            message,
            style: TextStyle(color: kLucidMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  final String error;
  const _SearchErrorState({required this.error});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 40),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Error: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ],
    );
  }
}
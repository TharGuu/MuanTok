// lib/screens/shop_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../features/profile/voucher_screen.dart';
import 'promotion_screen.dart';

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
      backgroundColor: Colors.white,
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
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
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
                          color: Colors.white,
                          size: 28,
                          shadows: [Shadow(blurRadius: 2)],
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],

                    // favorite icon (heart) - visible on Buy tab
                    if (selectedTab == 'Buy') ...[
                      const Icon(
                        Icons.favorite_border_rounded,
                        color: Colors.white,
                        size: 28,
                        shadows: [Shadow(blurRadius: 2)],
                      ),
                      const SizedBox(width: 16),
                    ],

                    // cart icon - visible on Buy tab
                    if (selectedTab == 'Buy') ...[
                      const Icon(
                        Icons.shopping_cart_outlined,
                        color: Colors.white,
                        size: 28,
                        shadows: [Shadow(blurRadius: 2)],
                      ),
                    ],

                    // if you ALSO want icons in Sell tab later,
                    // you can add an `else` with different icons here.
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                BUY HOME VIEW                               */
/* -------------------------------------------------------------------------- */

class _BuyHome extends StatefulWidget {
  const _BuyHome();
  @override
  State<_BuyHome> createState() => _BuyHomeState();
}

class _BuyHomeState extends State<_BuyHome> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _recommended = [];

  // coupons demo (static placeholders)
  final List<_Coupon> _coupons = [
    _Coupon('c1', '฿50 OFF', 'Min. spend ฿300'),
    _Coupon('c2', 'Free Ship', 'Nationwide'),
    _Coupon('c3', '10% OFF', 'Cap ฿100'),
    _Coupon('c4', 'Buy 1 Get 1', 'Selected items'),
  ];

  final Set<String> _claimedIds = <String>{};
  List<_Coupon> get _visibleCoupons =>
      _coupons.where((c) => !_claimedIds.contains(c.id)).toList();

  RealtimeChannel? _channel;
  StreamSubscription<void>? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchRecommended();
    _subscribeRealtime();
    _loadClaimedCouponIds();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadClaimedCouponIds() async {
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) return;

      final rows = await sb
          .from('user_coupons')
          .select('coupon_id')
          .eq('user_id', uid);

      final ids = <String>{};
      for (final r in (rows as List)) {
        final v = r['coupon_id'];
        if (v != null) ids.add(v.toString());
      }

      if (!mounted) return;
      setState(() {
        _claimedIds
          ..clear()
          ..addAll(ids);
      });
    } catch (_) {
      // silent fail
    }
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
      setState(() => _recommended = list);
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

  Future<void> _ensureCouponExistsOnServer(_Coupon c) async {
    final sb = Supabase.instance.client;
    final discountType = c.title.contains('%') ? 'percent' : 'amount';
    final discountValue = _parseDiscountValue(c.title);

    await sb.from('coupons').upsert(
      {
        'id': c.id,
        'title': c.title,
        'description': c.subtitle,
        'code': c.id,
        'image_url': null,
        'discount_type': discountType,
        'discount_value': discountValue,
        'min_spend': null,
        'expires_at': null,
        'is_active': true,
      },
      onConflict: 'id',
    );
  }

  num _parseDiscountValue(String title) {
    final percent = RegExp(r'(\d+)\s*%').firstMatch(title);
    if (percent != null) return num.parse(percent.group(1)!);
    final amount = RegExp(r'฿\s*(\d+)').firstMatch(title);
    if (amount != null) return num.parse(amount.group(1)!);
    return 0;
  }

  Future<void> _claimCouponToServer(_Coupon c) async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw 'Please sign in to claim coupons.';
    }

    await _ensureCouponExistsOnServer(c);

    final existing = await sb
        .from('user_coupons')
        .select('id')
        .eq('user_id', uid)
        .eq('coupon_id', c.id)
        .limit(1);

    if (existing is List && existing.isNotEmpty) return;

    await sb.from('user_coupons').insert({
      'user_id': uid,
      'coupon_id': c.id,
    });
  }

  void _claimCoupon(_Coupon coupon) async {
    if (_claimedIds.contains(coupon.id)) return;
    try {
      await _claimCouponToServer(coupon);

      if (!mounted) return;
      setState(() {
        coupon.claimed = true;
        _claimedIds.add(coupon.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Coupon claimed: ${coupon.title}'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                  const VoucherScreen(initialTab: VoucherTab.available),
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Claim failed: $e')),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchRecommended();
        await _loadClaimedCouponIds();
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
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),

          if (_visibleCoupons.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 110,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  'No coupons available',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 130, // give a bit more breathing space
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4), // prevent pixel overflow
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _visibleCoupons.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => Align(
                    alignment: Alignment.topCenter, // ensures cards stay inside
                    child: _CouponCard(
                      coupon: _visibleCoupons[i],
                      onClaim: () => _claimCoupon(_visibleCoupons[i]),
                    ),
                  ),
                ),
              ),
            ),


          const SizedBox(height: 16),

          // 🔥 EVENT / PROMOTIONS SECTION
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Event',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
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
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              // error state
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
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
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'No active events',
                      style: TextStyle(
                        color: Colors.grey.shade700,
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

          // Recommended header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Recommended for you',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _openViewAll,
                  child: const Text('View all'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
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
                child: Text('No products yet.'),
              )
            else
              _ProductGrid(products: _recommended),
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
    final bg = selected ? Colors.black : Colors.white;
    final fg = selected ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.black : Colors.grey.shade300,
            width: 1.2,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 32),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showSwipeHint) ...[
              const SizedBox(height: 4),
              Text(
                'Tap →',
                style: TextStyle(
                  color: fg.withOpacity(0.7),
                  fontSize: 12,
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
        childAspectRatio: 0.70,
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

    final sellerId =
    (data['seller_id'] ?? data['sellerId'] ?? '').toString();

    final Map<String, dynamic>? sellerMap =
        (data['seller'] is Map
            ? data['seller'] as Map<String, dynamic>
            : null) ??
            (data['users'] is Map
                ? data['users'] as Map<String, dynamic>
                : null) ??
            (data['profiles'] is Map
                ? data['profiles'] as Map<String, dynamic>
                : null);

    final sellerNameFromRow = (sellerMap?['full_name'] ??
        data['seller_full_name'] ??
        data['full_name'] ??
        data['seller_name'])
        ?.toString();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // TODO: go to details
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
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.grey,
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
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  hasDiscount
                      ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '฿ ${_fmtBaht(discounted)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.red,
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
                    priceRaw == 0
                        ? ''
                        : '฿ ${_fmtBaht(priceRaw)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.storefront_rounded,
                        size: 13,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: sellerNameFromRow != null &&
                            sellerNameFromRow.isNotEmpty
                            ? Text(
                          sellerNameFromRow,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
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

      // ensure only correct category (safety)
      final cleaned = fetched.where((p) {
        final cat = (p['category'] ?? '').toString().trim();
        return cat == widget.category;
      }).toList();

      if (!mounted) return;
      setState(() => _items = cleaned);
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
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: Row(
          children: [
            Icon(widget.icon, size: 20),
            const SizedBox(width: 8),
            Text(widget.label),
          ],
        ),
      ),
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
          child: Text(
            'Error: $_error',
            style: const TextStyle(color: Colors.red),
          ),
        )
            : _items.isEmpty
            ? const Center(
          child: Text('No products in this category.'),
        )
            : _ProductGrid(products: _items),
      ),
    );
  }
}

/* ------------------------------ VIEW ALL SCREEN --------------------------- */

enum _AllSort { newest, priceLowHigh, priceHighLow, ratingHighLow }

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
    }

    try {
      final list = await SupabaseService.listProducts(
        limit: 120,
        offset: 0,
        orderBy: orderBy,
        ascending: ascending,
      );
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Widget _sortChip(_AllSort value, String label) {
    final selected = _sort == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (s) {
        if (!s) return;
        setState(() => _sort = value);
        _fetch();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selectedColor: Colors.black,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
      ),
      backgroundColor: Colors.grey.shade100,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('All Products'),
      ),
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
          children: [
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        )
            : ListView(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _sortChip(_AllSort.newest, 'Newest'),
                  _sortChip(_AllSort.priceLowHigh,
                      'Price: Low → High'),
                  _sortChip(_AllSort.priceHighLow,
                      'Price: High → Low'),
                  _sortChip(_AllSort.ratingHighLow,
                      'Rating: High → Low'),
                ],
              ),
            ),
            _items.isEmpty
                ? const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: Center(
                  child: Text('No products yet.')),
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
          'attachProductToEvent -> product $productId '
              'event $eventId discountPct $discountPct',
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
      color: Colors.white,
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
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    'Add multiple photos',
                    style: TextStyle(color: Colors.grey.shade700),
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
                    : _categories
                    .firstWhere((c) => c.key == _category)
                    .label,
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
                  ),
                ),
              ),
              const SizedBox(height: 8),

              if (_loadingEvents)
                const LinearProgressIndicator(minHeight: 2)
              else if (_availableEvents.isEmpty)
                Text(
                  'No active events',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
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
                                  _selectedEvents.putIfAbsent(
                                      ev.id, () => 0);
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
                                  style:
                                  theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),

                                // "Ends Dec 31, 2025"
                                if (ev.endsAtDisplay.isNotEmpty)
                                  Text(
                                    'Ends ${ev.endsAtDisplay}',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(
                                      color: Colors.grey[600],
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
                                          keyboardType:
                                          TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          decoration:
                                          const InputDecoration(
                                            isDense: true,
                                            labelText: 'Discount (%)',
                                            border:
                                            OutlineInputBorder(),
                                          ),
                                          onChanged: (val) {
                                            final parsed =
                                                int.tryParse(val) ??
                                                    0;
                                            setState(() {
                                              _selectedEvents[ev.id] =
                                                  parsed.clamp(
                                                      0, 100);
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(Icons.publish_outlined),
                  label: Text(
                    _submitting ? 'Publishing...' : 'Publish',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding:
                    const EdgeInsets.symmetric(vertical: 14),
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
                icon: const Icon(Icons.close,
                    color: Colors.white),
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
        final fullName = (r['full_name'] ??
            r['username'] ??
            r['name'] ??
            'Unknown seller')
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

/* ------------------------------- COUPON UI -------------------------------- */

class _Coupon {
  final String id;
  final String title;
  final String subtitle;
  bool claimed;
  _Coupon(this.id, this.title, this.subtitle, {this.claimed = false});
}

class _CouponCard extends StatelessWidget {
  final _Coupon coupon;
  final VoidCallback onClaim;

  const _CouponCard({
    required this.coupon,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final claimed = coupon.claimed;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: claimed ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
          claimed ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                claimed
                    ? Icons.verified_rounded
                    : Icons.local_offer_rounded,
                color: claimed ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  coupon.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            coupon.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: claimed ? null : onClaim,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                claimed ? Colors.green.shade600 : Colors.black,
                foregroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(claimed ? 'Claimed' : 'Claim'),
            ),
          ),
        ],
      ),
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
        fillColor: Colors.grey.shade100,
        labelStyle: TextStyle(color: Colors.grey.shade700),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade600),
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
          fillColor: Colors.grey.shade100,
          labelStyle: TextStyle(color: Colors.grey.shade700),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
            BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
            BorderSide(color: Colors.grey.shade600),
          ),
          errorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide:
            BorderSide(color: Colors.redAccent),
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
/*
Goal:
- When search opens and query is empty: show ALL products.
- When user types: show filtered list.
- Show discount/non-discount all the same (ProductCard).

We use .filter('name','ilike','%text%') instead of .ilike() for sdk 2.5.0.
*/

class ProductSearchDelegate extends SearchDelegate<String?> {
  final _sb = Supabase.instance.client;

  @override
  String? get searchFieldLabel => 'Search products by name';

  @override
  TextInputType get keyboardType => TextInputType.text;

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
          tooltip: 'Clear',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
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

// pulls products from Supabase based on queryText
class _SearchList extends StatelessWidget {
  final String queryText;
  final SupabaseClient sb;
  const _SearchList({required this.queryText, required this.sb});

  Future<List<Map<String, dynamic>>> _fetch() async {
    // 1. Get recent products from Supabase
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
          is_event,
          discount_percent,
          seller_id,
          seller:users!products_seller_id_fkey(full_name)
        ''')
        .order('id', ascending: false)
        .limit(120);

    // 2. Cast once
    final list = (rows as List).cast<Map<String, dynamic>>();

    // 3. Local text filter (because we can't ilike/or easily on your SDK)
    final q = queryText.trim().toLowerCase();
    final filtered = q.isEmpty
        ? list
        : list.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      return name.contains(q);
    }).toList();

    // 4. Normalize seller for safety (same helper logic you use elsewhere)
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

    // 5. 🔥 Pull best discount for each product from product_events
    //    and inject it so _ProductCard can show red discounted price.
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

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetch(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _SearchErrorState(error: snap.error.toString());
        }
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return const _SearchEmptyState(message: 'No products found');
        }
        return _ProductGrid(products: items);
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
            style: TextStyle(color: Colors.grey.shade700),
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

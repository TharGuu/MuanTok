// lib/screens/favourite_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import 'product_detail_screen.dart';
import 'shop_screen.dart';

class FavouriteScreen extends StatefulWidget {
  const FavouriteScreen({super.key});

  @override
  State<FavouriteScreen> createState() => _FavouriteScreenState();
}

class _FavouriteScreenState extends State<FavouriteScreen> {
  bool _loading = true;
  String? _error;

  /// Each item:
  /// {
  ///   'fav_id': <int?>,
  ///   'product': <Map>,
  ///   'best_discount': <int>,
  ///   'discounted_price': <num>
  /// }
  List<Map<String, dynamic>> _items = [];

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchFavourites();
  }

  // ---------------- helpers (safe parsing) ----------------
  num _readNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  int _readInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  String? _firstImage(dynamic value) {
    if (value is List) {
      final list = value
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return list.isNotEmpty ? list.first : null;
    }
    if (value is String && value.trim().isNotEmpty) return value;
    return null;
  }

  String _fmtBaht(num value) {
    final s = value.toStringAsFixed(2);
    return s.endsWith('00') ? value.toStringAsFixed(0) : s;
  }

  void _goToShop() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ShopScreen()),
    );
  }

  // ---------------- data fetch ----------------
  Future<void> _fetchFavourites() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Please sign in to view favourites.';
        _items = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Select only columns that exist in your schema
      final rows = await _sb
          .from('favourites')
          .select('''
            id,
            product_id,
            created_at,
            products (
              id,
              name,
              price,
              image_urls,
              category,
              stock
            )
          ''')
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      final list = (rows as List).cast<Map<String, dynamic>>();

      // Collect product IDs
      final ids = <int>[];
      for (final r in list) {
        final p = (r['products'] ?? {}) as Map<String, dynamic>;
        final pid = p['id'];
        if (pid is int) ids.add(pid);
      }

      // Best discount via product_events
      final bestMap = await SupabaseService.fetchBestDiscountMapForProducts(ids);

      // Decorate items safely
      final decorated = <Map<String, dynamic>>[];
      for (final r in list) {
        final p = (r['products'] ?? {}) as Map<String, dynamic>;
        final pid = p['id'];
        if (pid is! int) continue;

        final price = _readNum(p['price']);
        final bestDiscount = _readInt(bestMap[pid]);
        final discounted =
        bestDiscount > 0 ? (price * (100 - bestDiscount)) / 100 : price;

        decorated.add({
          'fav_id': r['id'],
          'product': p,
          'best_discount': bestDiscount,
          'discounted_price': discounted,
        });
      }

      setState(() => _items = decorated);
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeFavourite(int productId) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _sb.from('favourites').delete().eq('user_id', uid).eq('product_id', productId);
      setState(() {
        _items.removeWhere((m) => (m['product'] as Map)['id'] == productId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from favourites')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
    )
        : _items.isEmpty
        ? const Center(child: Text('No favourites yet!'))
        : RefreshIndicator(
      onRefresh: _fetchFavourites,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = _items[index];
          final product =
          (row['product'] ?? {}) as Map<String, dynamic>;
          final pid = product['id'];
          if (pid is! int) return const SizedBox.shrink();

          final name = (product['name'] ?? '').toString();
          final category =
          (product['category'] ?? '').toString();
          final price = _readNum(product['price']);
          final bestDiscount = _readInt(row['best_discount']);
          final discounted = _readNum(row['discounted_price']);
          final stock = product['stock'];
          final img = _firstImage(product['image_urls']);

          return Dismissible(
            key: ValueKey('fav-$pid'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding:
              const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.red,
              child:
              const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Remove favourite'),
                  content: const Text(
                      'Do you want to remove this product from favourites?'),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(ctx).pop(true),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              );
              return ok == true;
            },
            onDismissed: (_) => _removeFavourite(pid),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: img == null
                    ? const SizedBox(
                  width: 64,
                  height: 64,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(0xFFEFEFEF)),
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: Colors.grey,
                    ),
                  ),
                )
                    : Image.network(
                  img,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red),
                    tooltip: 'Remove',
                    onPressed: () => _removeFavourite(pid),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (category.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        'Category: $category',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 4),
                  // Price / Discount
                  bestDiscount > 0
                      ? Row(
                    children: [
                      Text(
                        '฿ ${_fmtBaht(discounted)}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '฿ ${_fmtBaht(price)}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          decoration:
                          TextDecoration.lineThrough,
                          decorationThickness: 2,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          borderRadius:
                          BorderRadius.circular(6),
                        ),
                        child: Text(
                          '-$bestDiscount%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  )
                      : Text(
                    '฿ ${_fmtBaht(price)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Spacer(),
                      Text(
                        'Stock: ${stock ?? '-'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ProductDetailScreen(productId: pid),
                  ),
                );
              },
            ),
          );
        },
      ),
    );

    return WillPopScope(
      onWillPop: () async {
        _goToShop();
        return false; // prevent default back
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goToShop,
            tooltip: 'Back to Shop',
          ),
          title: const Text('Favourite Products'),
          backgroundColor: const Color(0xFFD8BEE5),
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: body,
      ),
    );
  }
}

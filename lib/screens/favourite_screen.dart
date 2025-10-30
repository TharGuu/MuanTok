// lib/screens/favourite_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import 'product_detail_screen.dart';

/// ---------------------------------------------------------------------------
/// Lucid (Purple) Theme Tokens (same as CartScreen)
/// ---------------------------------------------------------------------------
const kPurple = Color(0xFF7C3AED);   // primary (deep purple)
const kPurpleDark = Color(0xFF5B21B6);
const kLilac = Color(0xFFD8BEE5);    // accent lilac
const kCard = Color(0xFFF9F7FB);     // soft card bg
const kBorder = Color(0xFFE7DFF3);   // subtle border
const kInk = Color(0xFF1F1F1F);

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
    // same style as cart
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
      await _sb
          .from('favourites')
          .delete()
          .eq('user_id', uid)
          .eq('product_id', productId);
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

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: kPurple,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator(color: kPurple))
        : _error != null
        ? Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: _ErrorCard(error: _error!),
      ),
    )
        : _items.isEmpty
        ? const _EmptyFavourite()
        : RefreshIndicator(
      color: kPurple,
      onRefresh: _fetchFavourites,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final row = _items[index];
          final product =
          (row['product'] ?? {}) as Map<String, dynamic>;
          final pid = product['id'];
          if (pid is! int) return const SizedBox.shrink();

          final name = (product['name'] ?? '').toString();
          final category = (product['category'] ?? '').toString();
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
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
            child: _FavCard(
              imageUrl: img,
              title: name,
              category: category,
              price: price,
              discountedPrice: discounted,
              bestDiscount: bestDiscount,
              stock: stock is int ? stock : _readInt(stock),
              onRemove: () => _removeFavourite(pid),
              onOpenDetail: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) =>
                        ProductDetailScreen(productId: pid),
                    transitionsBuilder: (_, a, __, child) =>
                        FadeTransition(opacity: a, child: child),
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
        Navigator.of(context).popUntil((r) => r.isFirst);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('Favourites'),
          centerTitle: true,
          leading: IconButton(
            tooltip: 'Back to Home',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [kPurple, kPurpleDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          actions: [
            if (_items.isNotEmpty)
              IconButton(
                tooltip: 'Clear all',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear favourites'),
                      content: const Text(
                          'Remove all items from your favourites list?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Remove all'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    try {
                      final uid = _sb.auth.currentUser?.id;
                      if (uid != null) {
                        await _sb.from('favourites').delete().eq('user_id', uid);
                        setState(() => _items.clear());
                        _toast('Favourites cleared');
                      }
                    } catch (e) {
                      _toast('Failed to clear: $e');
                    }
                  }
                },
              ),
          ],
        ),
        body: body,
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Cards & Widgets (Lucid style)
/// ---------------------------------------------------------------------------

class _FavCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String category;
  final num price;
  final num discountedPrice;
  final int bestDiscount;
  final int stock;
  final VoidCallback onRemove;
  final VoidCallback onOpenDetail;

  const _FavCard({
    required this.imageUrl,
    required this.title,
    required this.category,
    required this.price,
    required this.discountedPrice,
    required this.bestDiscount,
    required this.stock,
    required this.onRemove,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = bestDiscount > 0 && price > 0;
    final outOfStock = stock <= 0;

    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpenDetail,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
            boxShadow: [
              BoxShadow(
                color: kPurple.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // image
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageUrl == null
                    ? Container(
                  width: 84,
                  height: 84,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: Icon(Icons.image_outlined,
                      size: 28, color: kPurple.withOpacity(.5)),
                )
                    : Image.network(
                  imageUrl!,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),

              // info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // title + remove
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: kInk,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              height: 1.2,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          icon:
                          const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: onRemove,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    if (category.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.sell_outlined,
                              size: 14, color: Colors.black54),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 8),

                    // Price / Discount (discounted price + % in RED)
                    hasDiscount
                        ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '฿ ${_fmt(discountedPrice)}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '฿ ${_fmt(price)}',
                          style: TextStyle(
                            color: Colors.black54,
                            decoration: TextDecoration.lineThrough,
                            decorationThickness: 2,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _DiscountChip(percent: bestDiscount),
                      ],
                    )
                        : Text(
                      price == 0 ? '' : '฿ ${_fmt(price)}',
                      style: const TextStyle(
                        color: kInk,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // stock
                    Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 14, color: Colors.black54),
                        const SizedBox(width: 4),
                        Text(
                          outOfStock ? 'Unavailable' : 'Stock: $stock',
                          style: TextStyle(
                            fontSize: 12,
                            color: outOfStock ? Colors.red : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
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

  String _fmt(num v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('00') ? v.toStringAsFixed(0) : s;
  }
}

class _DiscountChip extends StatelessWidget {
  final int percent;
  const _DiscountChip({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red.shade600, // solid red to match cart
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        '-$percent%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1.0,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class _EmptyFavourite extends StatelessWidget {
  const _EmptyFavourite();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 60),
        Icon(Icons.favorite_border_rounded,
            size: 72, color: kPurple.withOpacity(.35)),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'No favourites yet!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: kInk,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text('Save products you love and find them here.',
              style: TextStyle(color: Colors.black54)),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String error;
  const _ErrorCard({required this.error});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFC9C9)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: Colors.red, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

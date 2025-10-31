// lib/screens/my_products_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'product_detail_screen.dart';

const String kProductImagesBucket = 'product-images';

class BrandColors {
  static const deep = Color(0xFF7C3AED);   // primary
  static const soft = Color(0xFFA78BFA);   // accent
  static const pastel = Color(0xFFD8BEE5); // your earlier pick
  static const chipBg = Color(0x803C1E70); // translucent purple
}

class MyProductsScreen extends StatefulWidget {
  const MyProductsScreen({super.key});
  @override
  State<MyProductsScreen> createState() => _MyProductsScreenState();
}

class _MyProductsScreenState extends State<MyProductsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  RealtimeChannel? _channel;
  StreamSubscription<void>? _debounce;

  String get _uid => _sb.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _fetch();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_uid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Please sign in to view your products.';
        _items = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _sb
          .from('products')
          .select(r'''
            id, name, price, category, image_urls,
            is_event, discount_percent,
            product_events(
              discount_pct,
              events(active, ends_at)
            )
          ''')
          .eq('seller_id', _uid)
          .order('id', ascending: false);

      setState(() => _items = (rows as List).cast<Map<String, dynamic>>());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    if (_uid.isEmpty) return;
    _channel = _sb
        .channel('public:products:mine')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'products',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'seller_id',
        value: _uid,
      ),
      callback: (_) => _scheduleRefresh(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'products',
      filter: PostgresChangeFilterType.eq ==
          PostgresChangeFilterType.eq // keep analyzer happy
          ? PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'seller_id',
        value: _uid,
      )
          : null,
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
      if (mounted) _fetch();
    });
  }

  List<String> _extractImageUrls(Map<String, dynamic> data) {
    final v = data['image_urls'];
    if (v is List) {
      return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    } else if (v is String && v.isNotEmpty) {
      return [v];
    }
    return const [];
  }

  String? _guessStoragePathFromUrl(String url) {
    if (!url.contains('http') && !url.contains('https')) return url;
    final marker = '/object/public/$kProductImagesBucket/';
    final idx = url.indexOf(marker);
    if (idx == -1) return null;
    final start = idx + marker.length;
    if (start >= url.length) return null;
    return url.substring(start);
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final id = product['id'];
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete product?'),
        content: const Text('This will remove the product permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final prev = List<Map<String, dynamic>>.from(_items);
    setState(() => _items.removeWhere((e) => e['id'] == id));

    try {
      await _sb.from('products').delete().match({'id': id, 'seller_id': _uid});

      final urls = _extractImageUrls(product);
      final paths = <String>[];
      for (final u in urls) {
        final p = _guessStoragePathFromUrl(u);
        if (p != null && p.isNotEmpty) paths.add(p);
      }
      if (paths.isNotEmpty) {
        try {
          await _sb.storage.from(kProductImagesBucket).remove(paths);
        } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('✅ Product deleted')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _items = prev);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 🌈 Background gradient
        const _PurpleBackdrop(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            elevation: 0,
            centerTitle: false,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: const Text(
              'My Products',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          body: RefreshIndicator(
            color: BrandColors.deep,
            backgroundColor: Colors.white,
            onRefresh: _fetch,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _error != null
                ? ListView(
              children: [
                const SizedBox(height: 24),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Error: $_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            )
                : _items.isEmpty
                ? ListView(
              children: const [
                SizedBox(height: 40),
                Center(
                    child: Text(
                      'You haven’t published any products yet.',
                      style: TextStyle(color: Colors.white),
                    )),
                SizedBox(height: 8),
              ],
            )
                : _MyProductsGrid(
              products: _items,
              onDelete: _deleteProduct,
            ),
          ),
        ),
      ],
    );
  }
}

/* ------------------------------ BACKDROP ----------------------------------- */

class _PurpleBackdrop extends StatelessWidget {
  const _PurpleBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BrandColors.deep,
            BrandColors.soft,
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

/* ------------------------------ GRID & CARD -------------------------------- */

class _MyProductsGrid extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final void Function(Map<String, dynamic> product) onDelete;
  const _MyProductsGrid({required this.products, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.66, // taller to avoid overflow
      ),
      itemBuilder: (_, i) => _MyProductCard(
        data: products[i],
        onDelete: () => onDelete(products[i]),
      ),
    );
  }
}

class _MyProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onDelete;
  const _MyProductCard({required this.data, required this.onDelete});

  List<String> _extractImageUrls(dynamic v) {
    if (v is List) {
      return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    } else if (v is String) {
      return [v];
    }
    return const [];
  }

  int? _bestActiveDiscountPercent(Map<String, dynamic> product) {
    final now = DateTime.now();
    int? best;
    final rel = product['product_events'];
    if (rel is List) {
      for (final row in rel.whereType<Map>()) {
        final m = row.cast<String, dynamic>();
        final dpRaw = m['discount_pct'];
        final int? pct =
        (dpRaw is num) ? dpRaw.toInt() : (dpRaw is String ? int.tryParse(dpRaw) : null);

        final ev = m['events'];
        bool active = true;
        DateTime? endsAt;
        if (ev is Map) {
          final a = ev['active'];
          if (a is bool) active = a;
          final endRaw = ev['ends_at'];
          if (endRaw is String) endsAt = DateTime.tryParse(endRaw);
          if (endRaw is DateTime) endsAt = endRaw;
        }
        if (pct == null || pct <= 0) continue;
        if (!active) continue;
        if (endsAt != null && endsAt.isBefore(now)) continue;
        if (best == null || pct > best) best = pct;
      }
    }
    if (best == null) {
      final ie = product['is_event'];
      final dp = product['discount_percent'];
      final bool isEvent = ie == true || (ie is String && ie.toLowerCase() == 'true');
      final int? pct = (dp is num) ? dp.toInt() : (dp is String ? int.tryParse(dp) : null);
      if (isEvent && pct != null && pct > 0) best = pct;
    }
    return best;
  }

  String _formatTHB(num v) => (v % 1 == 0) ? '฿ ${v.toInt()}' : '฿ ${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '').toString();
    final priceRaw = data['price'];
    final num? priceNum = priceRaw is num ? priceRaw : num.tryParse('$priceRaw');
    final double? price = priceNum?.toDouble();

    final category = (data['category'] ?? '').toString();
    final urls = _extractImageUrls(data['image_urls']);
    final img = urls.isNotEmpty ? urls.first : null;

    final int? bestPct = _bestActiveDiscountPercent(data);
    final double? discounted =
    (price != null && bestPct != null) ? (price * (1 - bestPct / 100)).clamp(0, double.infinity) : null;

    final idRaw = data['id'];
    final int? productId =
    idRaw is int ? idRaw : (idRaw is num ? idRaw.toInt() : int.tryParse('$idRaw'));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BrandColors.pastel.withOpacity(.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (productId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cannot open product: missing id')),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(
                productId: productId,
                initialData: {
                  'id': productId,
                  'name': name,
                  'price': price,
                  'image_urls': urls,
                  'category': category,
                  'best_discount_pct': bestPct,
                  'discounted_price': discounted,
                },
              ),
            ),
          );
        },
        onLongPress: onDelete,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image
                AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: img == null
                            ? Container(
                          color: Colors.white,
                          child: const Icon(Icons.image_not_supported_outlined,
                              color: Colors.grey),
                        )
                            : Image.network(img, fit: BoxFit.cover),
                      ),
                      if (category.isNotEmpty)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: _CategoryValueBadge(text: category),
                        ),
                      if (bestPct != null && bestPct > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: _DiscountBadge(text: '-$bestPct%'),
                        ),
                    ],
                  ),
                ),

                // Text
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1033),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (discounted != null && price != null) ...[
                        Text(
                          _formatTHB(price),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatTHB(discounted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.red, // red accent
                          ),
                        ),
                      ] else
                        Text(
                          price == null ? '' : _formatTHB(price),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: BrandColors.deep,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // Delete
            Positioned(
              right: 8,
              bottom: 8,
              child: Tooltip(
                message: 'Delete product',
                child: InkWell(
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete this product?'),
                        content: const Text('This action cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) onDelete();
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6)],
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ---------------------------- BADGES --------------------------------------- */

class _CategoryValueBadge extends StatelessWidget {
  final String text;
  const _CategoryValueBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BrandColors.chipBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BrandColors.pastel.withOpacity(.7)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  final String text;
  const _DiscountBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    // Red percentage text with readable white chip + red outline
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 8),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.red,        // 🔴 discount percentage in red
          fontSize: 11,
          fontWeight: FontWeight.w900,
          height: 1.0,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

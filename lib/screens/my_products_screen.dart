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
            id, name, price, stock, category, image_urls,
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
        .channel('public:my_products_plus_events')
    // products by me
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
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'seller_id',
        value: _uid,
      ),
      callback: (_) => _scheduleRefresh(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'products',
      callback: (_) => _scheduleRefresh(),
    )
    // discounts relation
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'product_events',
      callback: (_) => _scheduleRefresh(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'product_events',
      callback: (_) => _scheduleRefresh(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'product_events',
      callback: (_) => _scheduleRefresh(),
    )
    // event active/expiry impacts discounts
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'events',
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

      // best-effort storage cleanup
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Product deleted')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _items = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Delete failed: $e')));
    }
  }

  // Keyboard-safe bottom sheet (prevents "bottom overflow")
  Future<void> _editStockDialog(BuildContext context, Map<String, dynamic> item) async {
    final controller = TextEditingController(text: ((item['stock'] as int?) ?? 0).toString());
    final id = item['id'] as int;

    final newValue = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottom + 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0x22000000),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const Text('Edit Stock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stock',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final v = int.tryParse(controller.text.trim());
                            if (v == null || v < 0) return;
                            Navigator.pop(ctx, v);
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (newValue == null) return;

    await _sb.from('products').update({'stock': newValue}).eq('id', id);
    await _fetch();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock updated')));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _PurpleBackdrop(),
        Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            elevation: 0,
            centerTitle: false,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('My Products', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: RefreshIndicator(
            color: BrandColors.deep,
            backgroundColor: Colors.white,
            onRefresh: _fetch,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _error != null
                ? ListView(
              children: const [
                SizedBox(height: 24),
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Something went wrong',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
                  ),
                ),
                SizedBox(height: 24),
              ],
            )
                : _items.isEmpty
                ? ListView(
              children: const [
                SizedBox(height: 40),
                Center(
                    child: Text('You haven’t published any products yet.',
                        style: TextStyle(color: Colors.white))),
                SizedBox(height: 8),
              ],
            )
                : _MyProductsGrid(
              products: _items,
              onDelete: _deleteProduct,
              onEditStock: (item) => _editStockDialog(context, item),
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
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrandColors.deep, BrandColors.soft],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

/* ------------------------------ GRID & CARD -------------------------------- */

class _MyProductsGrid extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final void Function(Map<String, dynamic> product) onDelete;
  final void Function(Map<String, dynamic> product) onEditStock;

  const _MyProductsGrid({
    required this.products,
    required this.onDelete,
    required this.onEditStock,
  });

  @override
  Widget build(BuildContext context) {
    final paddingBottom = 16.0 + MediaQuery.of(context).padding.bottom;

    // Card sizing: square image + compact info section
    final screenWidth = MediaQuery.of(context).size.width;
    final totalHPad = 16 + 16 + 12; // left + right + cross spacing
    final itemWidth = (screenWidth - totalHPad) / 2;
    final itemHeight = itemWidth + 120;  // tighter

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 8, 16, paddingBottom),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: products.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: itemHeight,
      ),
      itemBuilder: (_, i) => _MyProductCard(
        data: products[i],
        onDelete: () => onDelete(products[i]),
        onEditStock: () => onEditStock(products[i]),
      ),
    );
  }
}

class _MyProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onDelete;
  final VoidCallback onEditStock;
  const _MyProductCard({
    required this.data,
    required this.onDelete,
    required this.onEditStock,
  });

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
      for (final raw in rel) {
        if (raw is! Map) continue;
        final m = raw.cast<String, dynamic>();

        final dpRaw = m['discount_pct'];
        final int? pct = switch (dpRaw) {
          int v => v,
          num v => v.toInt(),
          String s => int.tryParse(s),
          _ => null,
        };
        if (pct == null || pct <= 0) continue;

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
        if (!active) continue;
        if (endsAt != null && endsAt.isBefore(now)) continue;

        if (best == null || pct > best) best = pct;
      }
    }

    // fallback to legacy columns when no active event applies
    if (best == null) {
      final ie = product['is_event'];
      final dp = product['discount_percent'];
      final isEvent = ie == true || (ie is String && ie.toLowerCase() == 'true');
      final int? pct = switch (dp) {
        int v => v,
        num v => v.toInt(),
        String s => int.tryParse(s),
        _ => null,
      };
      if (isEvent && pct != null && pct > 0) best = pct;
    }
    return best;
  }

  double? _discountedPrice(num? price, int? pct) {
    if (price == null || pct == null || pct <= 0) return null;
    final discounted = price * (1 - pct / 100.0);
    return discounted.roundToDouble(); // clean baht
  }

  String _formatTHB(num v) => (v % 1 == 0) ? '฿ ${v.toInt()}' : '฿ ${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '').toString();
    final priceRaw = data['price'];
    final num? priceNum = priceRaw is num ? priceRaw : num.tryParse('$priceRaw');
    final double? price = priceNum?.toDouble();

    final stockRaw = data['stock'];
    final int stock = stockRaw is int ? stockRaw : (stockRaw is num ? stockRaw.toInt() : 0);

    final category = (data['category'] ?? '').toString();
    final urls = _extractImageUrls(data['image_urls']);
    final img = urls.isNotEmpty ? urls.first : null;

    final int? bestPct = _bestActiveDiscountPercent(data);
    final double? discounted = _discountedPrice(price, bestPct);

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
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: img == null
                            ? Container(
                          color: Colors.white,
                          child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
                        )
                            : Image.network(img, fit: BoxFit.cover),
                      ),
                      if (category.isNotEmpty)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: _CategoryValueBadge(text: category),
                        ),
                      if ((bestPct ?? 0) > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: _DiscountBadge(text: '-${bestPct!}%'),
                        ),
                      if (stock <= 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            color: Colors.red.shade600,
                            child: const Text(
                              'OUT OF STOCK',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // compact info section
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
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
                          fontSize: 13.5,
                          color: Color(0xFF1C1033),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (discounted != null && price != null) ...[
                        // ORIGINAL (lined out)
                        Text(
                          _formatTHB(price),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            decoration: TextDecoration.lineThrough,      // << line-through
                            decorationThickness: 2,                      // << clearer strike
                          ),
                        ),
                        const SizedBox(height: 2),
                        // DISCOUNTED
                        Text(
                          _formatTHB(discounted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.red,
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
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 13, color: Colors.black54),
                          const SizedBox(width: 4),
                          Text(
                            'Stock: $stock',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // actions menu (edit stock / delete) — moved a bit higher
            Positioned(
              right: 6,
              bottom: 16, // << was 6; lift it up so card feels shorter
              child: PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (v) {
                  if (v == 'edit') onEditStock();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit stock')],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [Icon(Icons.delete_outline, size: 18), SizedBox(width: 8), Text('Delete')],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.08), blurRadius: 5)],
                  ),
                  child: const Icon(Icons.more_horiz, color: Colors.purple, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8)],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          height: 1.0,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// lib/screens/my_products_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Change if your bucket name is different.
const String kProductImagesBucket = 'product-images';

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
          .select('*')
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
          type: PostgresChangeFilterType.eq, column: 'seller_id', value: _uid),
      callback: (_) => _scheduleRefresh(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'products',
      filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq, column: 'seller_id', value: _uid),
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
    final v = data['image_urls'] ?? data['imageurl'] ?? data['image_url'];
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('My Products'),
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Error: $_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red)),
              ),
            ),
          ],
        )
            : _items.isEmpty
            ? ListView(
          children: const [
            SizedBox(height: 40),
            Center(child: Text('You haven’t published any products yet.')),
            SizedBox(height: 8),
          ],
        )
            : _MyProductsGrid(
          products: _items,
          onDelete: _deleteProduct,
        ),
      ),
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
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

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '').toString();
    final price = data['price'];
    final category = (data['category'] ?? '').toString();
    final urls =
    _extractImageUrls(data['image_urls'] ?? data['imageurl'] ?? data['image_url']);
    final img = urls.isNotEmpty ? urls.first : null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // TODO: navigate to your product detail/edit screen
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
                          color: Colors.grey.shade200,
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
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          price == null ? '' : '฿ ${price.toString()}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // overflow menu
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    final choice = await showMenu<String>(
                      context: context,
                      position: const RelativeRect.fromLTRB(1000, 60, 12, 0),
                      items: const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    );
                    if (choice == 'delete') onDelete();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(6.0),
                    child: Icon(Icons.more_vert, size: 18, color: Colors.white),
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

/* ---------------------------- CATEGORY BADGE ------------------------------- */

class _CategoryValueBadge extends StatelessWidget {
  final String text;
  const _CategoryValueBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

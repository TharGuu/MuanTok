// lib/screens/promotion_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'product_detail_screen.dart';

/* ------------------------------ Lucid tokens ------------------------------ */
const _kPurple = Color(0xFF7C3AED);
const _kShadow = Color(0x14000000);

/* ------------------------------- Screen ----------------------------------- */

class PromotionScreen extends StatefulWidget {
  final int eventId;      // which promo/event we're viewing
  final String eventName; // title to show in the app bar

  const PromotionScreen({
    super.key,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  // ----- UI controllers/state -----
  final TextEditingController _searchCtrl = TextEditingController();

  String _selectedSort = 'Price: Low → High';
  String _selectedCategory = 'All';

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _allItems = []; // raw from DB for THIS event
  List<Map<String, dynamic>> _filteredItems = [];

  // These should match your DB product.category
  static const List<String> _categories = <String>[
    'All',
    'Electronics',
    'Beauty',
    'Fashion',
    'Sport',
    'Food',
    'Other',
  ];

  static const List<String> _sortOptions = <String>[
    'Price: Low → High',
    'Price: High → Low',
    'Rating: High → Low',
    'Rating: Low → High',
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFiltersLocally);
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyFiltersLocally);
    _searchCtrl.dispose();
    super.dispose();
  }

  // 1) Fetch all products for THIS promo/event from Supabase
  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // listProductsByEvent(eventId: ...) is defined in SupabaseService
      final products = await SupabaseService.listProductsByEvent(
        eventId: widget.eventId,
      );

      // Normalize: compute effective price once so sort is consistent
      for (final p in products) {
        final price = _asNum(p['price']);
        final pct = _asNum(p['discount_percent']);
        final effective = pct > 0 ? (price * (100 - pct)) / 100 : price;
        p['effective_price'] = effective;
      }

      setState(() {
        _allItems = products;
      });

      _applyFiltersLocally();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // 2) Apply text search, category filter, and sort (price/rating)
  void _applyFiltersLocally() {
    final q = _searchCtrl.text.trim().toLowerCase();

    // category filter
    final catFiltered = _selectedCategory == 'All'
        ? _allItems
        : _allItems.where((p) {
      final cat = (p['category'] ?? '').toString();
      return cat == _selectedCategory;
    }).toList();

    // text search filter
    final searched = catFiltered.where((p) {
      if (q.isEmpty) return true;
      final name = (p['name'] ?? '').toString().toLowerCase();
      final desc = (p['description'] ?? '').toString().toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList();

    // sort
    searched.sort((a, b) {
      switch (_selectedSort) {
        case 'Price: Low → High':
          return _asNum(a['effective_price']).compareTo(_asNum(b['effective_price']));
        case 'Price: High → Low':
          return _asNum(b['effective_price']).compareTo(_asNum(a['effective_price']));
        case 'Rating: High → Low':
          return _ratingOf(b).compareTo(_ratingOf(a));
        case 'Rating: Low → High':
          return _ratingOf(a).compareTo(_ratingOf(b));
      }
      return 0;
    });

    if (mounted) {
      setState(() {
        _filteredItems = searched;
      });
    }
  }

  // ---------------------------- Small helpers -----------------------------
  num _asNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  double _ratingOf(Map<String, dynamic> p) {
    final v = p['rating'] ?? p['avg_rating'] ?? p['avgRating'] ?? 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  String _fmtBaht(num value) {
    final s = value.toStringAsFixed(2);
    return s.endsWith('00') ? value.toStringAsFixed(0) : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        titleSpacing: 0,
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: Row(
          children: [
            const Icon(Icons.local_fire_department, color: Colors.red),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                widget.eventName,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ---------- Filters / Search ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SEARCH BAR
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(.4),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Search in this promotion...',
                          ),
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        GestureDetector(
                          onTap: () => _searchCtrl.clear(),
                          child: const Icon(Icons.close, size: 18),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // CATEGORY + SORT
                Row(
                  children: [
                    // CATEGORY DROPDOWN
                    Expanded(
                      child: _FilterDropdown<String>(
                        label: 'Category',
                        value: _selectedCategory,
                        values: _categories,
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() => _selectedCategory = val);
                          _applyFiltersLocally();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),

                    // SORT DROPDOWN (now includes rating)
                    Expanded(
                      child: _FilterDropdown<String>(
                        label: 'Sort',
                        value: _selectedSort,
                        values: _sortOptions,
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() => _selectedSort = val);
                          _applyFiltersLocally();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ---------- RESULT GRID / LOADING / ERROR ----------
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _ErrorRetry(message: _error!, onRetry: _fetch)
                : _filteredItems.isEmpty
                ? const _EmptyState()
                : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.62, // tall enough; avoids overflow
              ),
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final product = _filteredItems[index];
                return _EventProductCard(product: product);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/* ────────────────────────── REUSABLE WIDGETS ────────────────────────── */

class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> values;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down),
          onChanged: onChanged,
          items: values
              .map(
                (v) => DropdownMenuItem<T>(
              value: v,
              child: Text(
                v.toString(),
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
              .toList(),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No products in this promotion.',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
          'Error loading products',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ]),
    );
  }
}

/* ───────────── PRODUCT CARD FOR EVENT GRID (with ⭐ rating) ───────────── */

class _EventProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const _EventProductCard({required this.product});

  num _asNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  String _fmtBaht(num value) {
    final s = value.toStringAsFixed(2);
    return s.endsWith('00') ? value.toStringAsFixed(0) : s;
  }

  num _discounted(num price, num pct) {
    if (pct <= 0) return price;
    return (price * (100 - pct)) / 100;
  }

  List<String> _extractImageUrls(dynamic v) {
    if (v is List) {
      return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    } else if (v is String && v.isNotEmpty) {
      return [v];
    }
    return const [];
  }

  double _ratingOf(Map<String, dynamic> p) {
    final v = p['rating'] ?? p['avg_rating'] ?? p['avgRating'] ?? 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = (product['name'] ?? '').toString();
    final category = (product['category'] ?? '').toString();

    final price = _asNum(product['price']);
    final pct = _asNum(product['discount_percent']);
    final hasDiscount = pct > 0 && price > 0;
    final eff = _discounted(price, pct);

    final rating = _ratingOf(product);

    final sellerName = (product['seller']?['full_name'] ??
        product['seller_full_name'] ??
        product['full_name'] ??
        product['seller_name'] ??
        'Unknown Seller')
        .toString();

    final urls = _extractImageUrls(
      product['image_urls'] ?? product['imageurl'] ?? product['image_url'],
    );
    final firstImageUrl = urls.isNotEmpty ? urls.first : null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(
                productId: product['id'] as int,
                initialData: product,
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor.withOpacity(.4)),
            boxShadow: const [BoxShadow(color: _kShadow, blurRadius: 8, offset: Offset(0, 4))],
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.2,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: firstImageUrl != null && firstImageUrl.isNotEmpty
                            ? Image.network(firstImageUrl, fit: BoxFit.cover)
                            : Container(
                          color: Colors.grey.shade300,
                          child: const Center(
                            child: Icon(Icons.image_not_supported),
                          ),
                        ),
                      ),
                    ),
                    if (category.isNotEmpty)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: _ChipBadge(
                          text: category,
                          bg: Colors.black.withOpacity(.75),
                          fg: Colors.white,
                        ),
                      ),
                    if (hasDiscount)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _ChipBadge(
                          text: '-${pct.toString()}%',
                          bg: Colors.red,
                          fg: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Name
              Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 4),

              // ⭐ Rating row (purple) — NEW
              _StarRating(rating: rating, size: 13, showNumber: true, color: _kPurple),

              const SizedBox(height: 6),

              // Price
              hasDiscount
                  ? Row(
                children: [
                  Text(
                    '฿ ${_fmtBaht(eff)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '฿ ${_fmtBaht(price)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              )
                  : Text(
                '฿ ${_fmtBaht(price)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                ),
              ),

              const SizedBox(height: 6),

              // Seller
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    size: 14,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(.7),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      sellerName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(.8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------------ Star rating ------------------------------- */

class _StarRating extends StatelessWidget {
  final double rating;        // 0..5
  final double size;          // icon size
  final bool showNumber;      // show numeric score
  final Color color;          // star color

  const _StarRating({
    super.key,
    required this.rating,
    this.size = 12,
    this.showNumber = true,
    this.color = _kPurple,
  });

  @override
  Widget build(BuildContext context) {
    final r = rating.clamp(0, 5).toDouble();
    final stars = <Widget>[];
    for (int i = 1; i <= 5; i++) {
      final icon = r >= i
          ? Icons.star_rounded
          : (r >= i - 0.5 ? Icons.star_half_rounded : Icons.star_border_rounded);
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
            ),
          ),
        ],
      ],
    );
  }
}

/* ------------------------------- Chip badge ------------------------------- */

class _ChipBadge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _ChipBadge({
    required this.text,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
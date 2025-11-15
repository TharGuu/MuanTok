// lib/screens/promotion_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'product_detail_screen.dart';

/* ------------------------------ Lucid tokens ------------------------------ */
const _kPurple = Color(0xFF7C3AED);
const _kPurpleSoftA = Color(0xFFF3E8FF);
const _kPurpleSoftB = Color(0xFFEDE9FE);
const _kBg = Color(0xFFF5F3FF);
const _kSurface = Colors.white;
const _kText = Color(0xFF111827);
const _kMuted = Color(0xFF6B7280);
const _kBorder = Color(0xFFE5E7EB);
const _kShadow = Color(0x14000000);

/* ------------------------------- Screen ----------------------------------- */

class PromotionScreen extends StatefulWidget {
  final int eventId; // which promo/event we're viewing
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
          return _asNum(a['effective_price'])
              .compareTo(_asNum(b['effective_price']));
        case 'Price: High → Low':
          return _asNum(b['effective_price'])
              .compareTo(_asNum(a['effective_price']));
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
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _kBg,
        foregroundColor: _kText,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_kPurple, Color(0xFFFB7185)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kPurple.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.eventName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Limited Time Event',
                    style: TextStyle(
                      fontSize: 11,
                      color: _kMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ---------- Filters / Search card ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SEARCH BAR
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [_kPurpleSoftA, _kPurpleSoftB],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: _kPurple,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            textInputAction: TextInputAction.search,
                            cursorColor: _kPurple,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Search in this promotion...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: _kMuted,
                              ),
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              color: _kText,
                            ),
                          ),
                        ),
                        if (_searchCtrl.text.isNotEmpty)
                          GestureDetector(
                            onTap: () => _searchCtrl.clear(),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: _kMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // CATEGORY + SORT
                  Row(
                    children: [
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
                      const SizedBox(width: 10),
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
          ),

          const SizedBox(height: 12),

          // ---------- RESULT GRID / LOADING / ERROR ----------
          Expanded(
            child: _loading
                ? const Center(
              child: CircularProgressIndicator(color: _kPurple),
            )
                : _error != null
                ? _ErrorRetry(message: _error!, onRetry: _fetch)
                : _filteredItems.isEmpty
                ? const _EmptyState()
                : GridView.builder(
              padding:
              const EdgeInsets.fromLTRB(16, 0, 16, 16),
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
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
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 12,
          color: _kMuted,
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        filled: true,
        fillColor: _kSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _kBorder),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _kPurple, width: 1.3),
        ),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down_rounded, color: _kMuted),
          onChanged: onChanged,
          items: values
              .map(
                (v) => DropdownMenuItem<T>(
              value: v,
              child: Text(
                v.toString(),
                style: const TextStyle(
                  fontSize: 13,
                  color: _kText,
                ),
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(
          Icons.inbox_rounded,
          size: 40,
          color: _kMuted,
        ),
        SizedBox(height: 8),
        Text(
          'No products in this promotion',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _kText,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Try another keyword or category.',
          style: TextStyle(
            fontSize: 12,
            color: _kMuted,
          ),
        ),
      ],
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.red, size: 24),
          const SizedBox(height: 6),
          const Text(
            'Error loading products',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: _kMuted),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text(
              'Retry',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
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
      return v
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
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
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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
            color: _kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
            boxShadow: const [
              BoxShadow(
                color: _kShadow,
                blurRadius: 15,
                offset: Offset(0, 8),
              )
            ],
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
                        borderRadius: BorderRadius.circular(10),
                        child: firstImageUrl != null &&
                            firstImageUrl.isNotEmpty
                            ? Image.network(firstImageUrl, fit: BoxFit.cover)
                            : Container(
                          color: _kPurpleSoftB,
                          child: const Center(
                            child: Icon(
                              Icons.image_rounded,
                              color: _kMuted,
                            ),
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
                          bg: const Color(0xFFEF4444),
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _kText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 4),

              // ⭐ Rating row (purple)
              _StarRating(
                rating: rating,
                size: 13,
                showNumber: true,
                color: _kPurple,
              ),

              const SizedBox(height: 6),

              // Price
              hasDiscount
                  ? Row(
                children: [
                  Text(
                    '฿ ${_fmtBaht(eff)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '฿ ${_fmtBaht(price)}',
                    style: const TextStyle(
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                      color: _kMuted,
                    ),
                  ),
                ],
              )
                  : Text(
                '฿ ${_fmtBaht(price)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFDC2626),
                ),
              ),

              const SizedBox(height: 6),

              // Seller
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.storefront_rounded,
                    size: 14,
                    color: _kMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      sellerName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _kMuted,
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
  final double rating; // 0..5
  final double size; // icon size
  final bool showNumber; // show numeric score
  final Color color; // star color

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
              color: _kText,
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
      padding:
      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
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
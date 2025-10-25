// lib/screens/promotion_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

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
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFiltersLocally);
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // 1. fetch all products for THIS promo/event from Supabase
  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // We already have this helper in supabase_service.dart:
      // listProductsByEvent(eventId: ...)
      final products = await SupabaseService.listProductsByEvent(
        eventId: widget.eventId,
        // local sort later anyway, so orderBy doesn't matter a ton
      );

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

  // 2. apply text search, category filter, price sort
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

    // sort by price
    searched.sort((a, b) {
      final paRaw = a['price'];
      final pbRaw = b['price'];
      final pa = paRaw is num ? paRaw : num.tryParse('$paRaw') ?? 0;
      final pb = pbRaw is num ? pbRaw : num.tryParse('$pbRaw') ?? 0;

      if (_selectedSort == 'Price: Low → High') {
        return pa.compareTo(pb);
      } else {
        return pb.compareTo(pa);
      }
    });

    if (mounted) {
      setState(() {
        _filteredItems = searched;
      });
    }
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
                          onTap: () {
                            _searchCtrl.clear();
                          },
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
                          setState(() {
                            _selectedCategory = val;
                          });
                          _applyFiltersLocally();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),

                    // SORT DROPDOWN
                    Expanded(
                      child: _FilterDropdown<String>(
                        label: 'Sort',
                        value: _selectedSort,
                        values: _sortOptions,
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            _selectedSort = val;
                          });
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
                ? _ErrorRetry(
              message: _error!,
              onRetry: _fetch,
            )
                : _filteredItems.isEmpty
                ? const _EmptyState()
                : GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16,
              ),
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.7,
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
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
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

class _EventProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const _EventProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = (product['name'] ?? '').toString();
    final category = (product['category'] ?? '').toString();

    // base price
    final priceRaw = product['price'];
    final priceNum =
    priceRaw is num ? priceRaw : num.tryParse('$priceRaw') ?? 0;
    final priceStr = priceNum.toString();

    // injected from SupabaseService.listProductsByEvent()
    final discountPercentNum =
    (product['discount_percent'] ?? 0) is num
        ? (product['discount_percent'] ?? 0) as num
        : num.tryParse(
        (product['discount_percent'] ?? '0').toString()) ??
        0;

    final sellerName = (product['seller']?['full_name'] ??
        product['seller_full_name'] ??
        'Unknown Seller')
        .toString();

    // first image
    String? firstImageUrl;
    final imgs = product['image_urls'];
    if (imgs is List && imgs.isNotEmpty) {
      firstImageUrl = imgs.first?.toString();
    } else if (imgs is String && imgs.isNotEmpty) {
      firstImageUrl = imgs;
    }

    // price after discount
    final discountedPrice =
    _calcDiscountedPrice(priceNum, discountPercentNum);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withOpacity(.4),
        ),
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
                    child: firstImageUrl != null &&
                        firstImageUrl.isNotEmpty
                        ? Image.network(
                      firstImageUrl,
                      fit: BoxFit.cover,
                    )
                        : Container(
                      color: Colors.grey.shade300,
                      child: const Center(
                        child: Icon(Icons.image_not_supported),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: _ChipBadge(
                    text: category,
                    bg: Colors.black.withOpacity(.75),
                    fg: Colors.white,
                  ),
                ),
                if (discountPercentNum > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _ChipBadge(
                      text: '-${discountPercentNum.toString()}%',
                      bg: Colors.red,
                      fg: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          if (discountPercentNum > 0)
            Row(
              children: [
                Text(
                  '฿ ${discountedPrice.toString()}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '฿ $priceStr',
                  style: theme.textTheme.bodySmall?.copyWith(
                    decoration: TextDecoration.lineThrough,
                    color: theme.textTheme.bodySmall?.color
                        ?.withOpacity(.6),
                    fontSize: 11,
                  ),
                ),
              ],
            )
          else
            Text(
              '฿ $priceStr',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
          const SizedBox(height: 6),
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
                    color: theme.textTheme.bodySmall?.color
                        ?.withOpacity(.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  num _calcDiscountedPrice(num price, num discountPct) {
    if (discountPct <= 0) return price;
    final discountAmount = price * (discountPct / 100);
    final discounted = price - discountAmount;
    return discounted.round(); // nice clean integer baht
  }
}

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

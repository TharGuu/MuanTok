import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'product_detail_screen.dart';

class EventProductsScreen extends StatefulWidget {
  final int eventId;
  const EventProductsScreen({super.key, required this.eventId});

  @override
  State<EventProductsScreen> createState() => _EventProductsScreenState();
}

class _EventProductsScreenState extends State<EventProductsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  // dropdown filters
  String _selectedSort = 'Price: Low → High';
  String _selectedCategory = 'All';

  // data
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  // category options (must match DB values exactly)
  static const List<String> _categories = <String>[
    'All',
    'Electronics',
    'Beauty',
    'Fashion',
    'Sport',
    'Food',
    'Other',
  ];

  // sort options
  static const List<String> _sortOptions = <String>[
    'Price: Low → High',
    'Price: High → Low',
  ];

  @override
  void initState() {
    super.initState();
    _fetch();
    _searchCtrl.addListener(_applyFiltersLocally);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyFiltersLocally);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // pull ALL products that belong to ANY active event
      // each product already has a discount_percent injected
      final allEventProducts =
      await SupabaseService.listAllEventProductsFlattened();

      // apply category filter (local)
      final filteredByCategory = _selectedCategory == 'All'
          ? allEventProducts
          : allEventProducts.where((p) {
        final cat = (p['category'] ?? '').toString();
        return cat == _selectedCategory;
      }).toList();

      if (!mounted) return;
      setState(() {
        _items = filteredByCategory;
      });

      _applyFiltersLocally();
    } catch (e) {
      if (!mounted) return;
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

  void _applyFiltersLocally() {
    if (mounted) {
      setState(() {
        // just trigger rebuild so _visibleItems recomputes
      });
    }
  }

  List<Map<String, dynamic>> get _visibleItems {
    final q = _searchCtrl.text.trim().toLowerCase();

    // text match
    final filtered = _items.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final desc = (p['description'] ?? '').toString().toLowerCase();
      if (q.isEmpty) return true;
      return name.contains(q) || desc.contains(q);
    }).toList();

    // sort local by price asc/desc
    filtered.sort((a, b) {
      final paRaw = a['price'];
      final pbRaw = b['price'];
      final pa = paRaw is num ? paRaw : num.tryParse(paRaw?.toString() ?? '0') ?? 0;
      final pb = pbRaw is num ? pbRaw : num.tryParse(pbRaw?.toString() ?? '0') ?? 0;

      if (_selectedSort == 'Price: Low → High') {
        return pa.compareTo(pb);
      } else {
        return pb.compareTo(pa);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleItems = _visibleItems;

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
            Text(
              'Event Products',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filters / Search
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
                            hintText: 'Search event deals...',
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

                // CATEGORY + SORT ROW
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
                          _fetch(); // refetch list based on new category
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

          // CONTENT
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _ErrorRetry(
              message: _error!,
              onRetry: _fetch,
            )
                : visibleItems.isEmpty
                ? const _EmptyState()
                : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.7,
              ),
              itemCount: visibleItems.length,
              itemBuilder: (context, index) {
                final product = visibleItems[index];
                return _EventProductCard(product: product);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/* ────────────────────────── SMALL WIDGETS ────────────────────────── */

// Filter Dropdown widget
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

// Empty State widget
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No event products found.',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }
}

// Error Retry widget
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

// Event Product Card widget
class _EventProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const _EventProductCard({required this.product});

  num _parseNum(dynamic v) {
    if (v is num) return v;
    if (v is String) {
      final d = double.tryParse(v);
      if (d != null) return d;
    }
    return 0;
  }

  String _fmtBaht(num value) {
    final s = value.toStringAsFixed(2);
    return s.endsWith('00') ? value.toStringAsFixed(0) : s;
  }

  num _calcDiscountedPrice(num price, num discountPct) {
    if (discountPct <= 0) return price;
    final discountAmount = price * (discountPct / 100);
    final discounted = price - discountAmount;
    return discounted.round(); // nice integer baht
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = (product['name'] ?? '').toString();
    final category = (product['category'] ?? '').toString();

    final priceNum = _parseNum(product['price']);
    final discountPercentNum = _parseNum(product['discount_percent']);

    final hasDiscount = discountPercentNum > 0 && priceNum > 0;
    final discountedPrice = _calcDiscountedPrice(priceNum, discountPercentNum);

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
                        child: firstImageUrl != null && firstImageUrl.isNotEmpty
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
                    // Category badge
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
                    // Discount badge
                    if (hasDiscount)
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

              // Product name
              Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 6),

              // Price row
              hasDiscount
                  ? Row(
                children: [
                  Text(
                    '฿ ${_fmtBaht(discountedPrice)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '฿ ${_fmtBaht(priceNum)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              )
                  : Text(
                '฿ ${_fmtBaht(priceNum)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),

              const SizedBox(height: 6),

              // Seller row
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
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
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

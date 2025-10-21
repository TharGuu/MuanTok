// lib/screens/shop_screen.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/* -------------------------------------------------------------------------- */
/*                               CATEGORY MODEL                               */
/* -------------------------------------------------------------------------- */

class _Category {
  final String key;   // value in DB 'category' column
  final String label; // UI text
  final IconData icon;
  const _Category(this.key, this.label, this.icon);
}

// Keep in sync with your DB values
const _categories = <_Category>[
  _Category('Electronics', 'Electronics', Icons.electrical_services_rounded),
  _Category('Beauty',      'Beauty',      Icons.spa_rounded),
  _Category('Fashion',     'Fashion',     Icons.checkroom_rounded),
  _Category('Sport',       'Sport',       Icons.sports_soccer_rounded),
  _Category('Food',        'Food',        Icons.fastfood_rounded),
];

/* -------------------------------------------------------------------------- */
/*                                 SHOP SCREEN                                */
/* -------------------------------------------------------------------------- */

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  String selectedTab = 'Buy'; // Buy | Sell

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Content
          Positioned.fill(
            top: safe.top + 64,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: selectedTab == 'Buy'
                  ? const _BuyHome()
                  : SellForm(
                key: const ValueKey('sell-form'),
                onSubmit: (product) async {
                  try {
                    final userId = SupabaseService.requireUserId();

                    final toUpload = product.images
                        .map((e) => ImageToUpload(bytes: e.bytes, fileName: e.name))
                        .toList();

                    final urls = await SupabaseService.uploadProductImages(
                      images: toUpload,
                      userId: userId,
                    );

                    final inserted = await SupabaseService.insertProduct(
                      sellerId: userId,
                      name: product.name,
                      description: product.description,
                      category: product.category,
                      price: product.price,
                      stock: product.stock,
                      imageUrls: urls,
                    );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('✅ ${inserted['name']} listed!')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('❌ $e')),
                      );
                    }
                  }
                },
              ),
            ),
          ),

          // Top bar (Buy/Sell toggle + Search + Profile)
          Positioned(
            top: safe.top + 10,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
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
                    const Icon(Icons.search, color: Colors.white, size: 30, shadows: [Shadow(blurRadius: 2)]),
                    const SizedBox(width: 16),
                    CircleAvatar(radius: 15, backgroundColor: Colors.grey.shade400),
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

  // Coupons (local state; persist in DB per-user if you want)
  final List<_Coupon> _coupons = [
    _Coupon('c1', '฿50 OFF', 'Min. spend ฿300'),
    _Coupon('c2', 'Free Ship', 'Nationwide'),
    _Coupon('c3', '10% OFF', 'Cap ฿100'),
    _Coupon('c4', 'Buy 1 Get 1', 'Selected items'),
  ];

  RealtimeChannel? _channel;
  StreamSubscription<void>? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchRecommended();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchRecommended() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // latest 6 from Supabase products
      final list = await SupabaseService.listProducts(
        limit: 6,
        offset: 0,
        orderBy: 'created_at',
        ascending: false,
      );
      setState(() => _recommended = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
    _debounce = Stream<void>.periodic(const Duration(milliseconds: 250)).take(1).listen((_) {
      if (mounted) _fetchRecommended();
    });
  }

  void _openCategory(BuildContext context, _Category c) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CategoryProductsScreen(category: c.key, label: c.label, icon: c.icon)),
    );
  }

  void _openViewAll() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AllProductsScreen()));
  }

  void _claimCoupon(_Coupon coupon) {
    if (coupon.claimed) return;
    setState(() => coupon.claimed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('🎉 Coupon claimed: ${coupon.title}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _fetchRecommended,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 8),

          // Categories carousel (tap -> category screen)
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

          // Coupons with Claim button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Coupons',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _coupons.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _CouponCard(
                coupon: _coupons[i],
                onClaim: () => _claimCoupon(_coupons[i]),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Event title + Poster
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Event',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 140,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF111111), Color(0xFF2D2D2D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: const [
                    Positioned(
                      top: 16, left: 16,
                      child: Text('12.12 DECEMBER SALE',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    Positioned(
                      left: 16, bottom: 14,
                      child: Text('Up to 70% OFF • Limited time',
                          style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ),
                    Positioned(
                      right: -10, bottom: -10,
                      child: Icon(Icons.local_fire_department_rounded, color: Colors.orangeAccent, size: 120),
                    )
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Recommended header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Recommended for you',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
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
          border: Border.all(color: selected ? Colors.black : Colors.grey.shade300, width: 1.2),
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
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
            if (showSwipeHint) ...[
              const SizedBox(height: 4),
              Text('Tap →',
                  style: TextStyle(color: fg.withOpacity(0.7), fontSize: 12)),
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
        crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.72,
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
    final urls = _extractImageUrls(data['image_urls'] ?? data['imageurl'] ?? data['image_url']);
    final img = urls.isNotEmpty ? urls.first : null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // TODO: navigate to a product detail page
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: img == null
                  ? Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
              )
                  : Image.network(img, fit: BoxFit.cover),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
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
      ),
    );
  }
}

/* --------------------------- CATEGORY PRODUCTS ---------------------------- */

class CategoryProductsScreen extends StatefulWidget {
  final String category;
  final String label;
  final IconData icon;
  const CategoryProductsScreen({super.key, required this.category, required this.label, required this.icon});

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
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
      final list = await SupabaseService.listProducts(
        category: widget.category,
        limit: 60,
        offset: 0,
        orderBy: 'created_at',
        ascending: false,
      );
      setState(() => _items = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
            ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
            : _items.isEmpty
            ? const Center(child: Text('No products in this category.'))
            : _ProductGrid(products: _items),
      ),
    );
  }
}

/* ------------------------------ VIEW ALL SCREEN --------------------------- */

class AllProductsScreen extends StatefulWidget {
  const AllProductsScreen({super.key});

  @override
  State<AllProductsScreen> createState() => _AllProductsScreenState();
}

class _AllProductsScreenState extends State<AllProductsScreen> {
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
      final list = await SupabaseService.listProducts(
        limit: 120,
        offset: 0,
        orderBy: 'created_at',
        ascending: false,
      );
      setState(() => _items = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
        title: const Text('All Products'),
      ),
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
            : _items.isEmpty
            ? const Center(child: Text('No products yet.'))
            : _ProductGrid(products: _items),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                   SELL FORM                                */
/* -------------------------------------------------------------------------- */

class PickedImage {
  final Uint8List bytes;
  final String name; // keep extension for MIME
  PickedImage(this.bytes, this.name);
}

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

class SellForm extends StatefulWidget {
  final Future<void> Function(ProductInput product) onSubmit;
  const SellForm({super.key, required this.onSubmit});
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _addFromGallery() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 2000);
      if (files.isEmpty) return;
      for (final f in files) {
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) continue;
        _images.add(PickedImage(bytes, f.name));
      }
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gallery pick failed: $e')));
    }
  }

  Future<void> _addFromCamera() async {
    try {
      final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2000);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) return;
      setState(() => _images.add(PickedImage(bytes, f.name)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera failed: $e')));
    }
  }

  void _removeAt(int index) => setState(() => _images.removeAt(index));

  void _openFullScreen(int startIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenGallery(images: _images, initialIndex: startIndex),
      ),
    );
  }

  Future<void> _submit() async {
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add product photos.')));
      return;
    }
    if (_formKey.currentState?.validate() != true) return;

    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;

    // default to first category if none chosen
    final category = _category ?? _categories.first.key;

    final product = ProductInput(
      images: List.unmodifiable(_images),
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      category: category,
      price: price,
      stock: stock,
    );

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(product);
      if (!mounted) return;
      // reset
      setState(() {
        _images.clear();
        _nameCtrl.clear();
        _descCtrl.clear();
        _priceCtrl.clear();
        _stockCtrl.text = '1';
        _category = null;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Photos + buttons
              Row(
                children: [
                  const Text('Photos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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

              // Thumbnail grid
              if (_images.isEmpty)
                Container(
                  height: 160,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text('Add multiple photos', style: TextStyle(color: Colors.grey.shade700)),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _images.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8,
                  ),
                  itemBuilder: (context, i) {
                    final p = _images[i];
                    return GestureDetector(
                      onTap: () => _openFullScreen(i),
                      onLongPress: () => _removeAt(i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(p.bytes, fit: BoxFit.cover),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 16),

              _LightInput(
                controller: _nameCtrl,
                label: 'Product name',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Product name is required' : null,
              ),
              const SizedBox(height: 12),

              _LightInput(
                controller: _descCtrl,
                label: 'Description',
                maxLines: 4,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Description is required' : null,
              ),
              const SizedBox(height: 12),

              // Category dropdown (same 5 as Buy)
              _LightDropdown(
                value: _category == null ? null : _categories.firstWhere((c) => c.key == _category).label,
                items: _categories.map((c) => c.label).toList(),
                label: 'Category',
                onChanged: (val) {
                  final found = _categories.firstWhere((c) => c.label == val);
                  setState(() => _category = found.key);
                },
                validator: (v) => (v == null || v.isEmpty) ? 'Select a category' : null,
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _LightInput(
                      controller: _priceCtrl,
                      label: 'Price',
                      prefixText: '฿ ',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
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
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.publish_outlined),
                  label: Text(_submitting ? 'Publishing...' : 'Publish'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
  const FullscreenGallery({super.key, required this.images, this.initialIndex = 0});

  @override
  State<FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<FullscreenGallery> {
  late final PageController _ctrl = PageController(initialPage: widget.initialIndex);

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
                child: Center(child: Image.memory(widget.images[i].bytes, fit: BoxFit.contain)),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
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

  const _CouponCard({required this.coupon, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final claimed = coupon.claimed;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: claimed ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: claimed ? Colors.green.shade200 : Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + icon
          Row(
            children: [
              Icon(
                claimed ? Icons.verified_rounded : Icons.local_offer_rounded,
                color: claimed ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  coupon.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            coupon.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: claimed ? null : onClaim,
              style: ElevatedButton.styleFrom(
                backgroundColor: claimed ? Colors.green.shade600 : Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(claimed ? 'Claimed' : 'Claim'),
            ),
          ),
        ],
      ),
    );
  }
}

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
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: state.value,
            isExpanded: true,
            items: items
                .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
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

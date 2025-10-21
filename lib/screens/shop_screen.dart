// lib/screens/shop_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/supabase_service.dart';

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
          Positioned.fill(
            top: safe.top + 64,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: selectedTab == 'Buy'
                  ? const _BuyPlaceholder()
                  : SellForm(
                key: const ValueKey('sell-form'),
                onSubmit: (product) async {
                  try {
                    final userId = SupabaseService.requireUserId();

                    // Build batch uploads
                    final toUpload = product.images
                        .map((e) => ImageToUpload(bytes: e.bytes, fileName: e.name))
                        .toList();

                    // Upload all images
                    final urls = await SupabaseService.uploadProductImages(
                      images: toUpload,
                      userId: userId,
                    );

                    // Insert product with multiple image URLs
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

class _BuyPlaceholder extends StatelessWidget {
  const _BuyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('🛒 Browse Items to Buy',
          style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600)),
    );
  }
}

/* ------------------------------- SELL FORM -------------------------------- */

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
  final _categories = const [
    'Electronics',
    'Fashion',
    'Beauty',
    'Sports',
    'Other',
  ];

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

  void _removeAt(int index) {
    setState(() => _images.removeAt(index));
  }

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

    final product = ProductInput(
      images: List.unmodifiable(_images),
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      category: _category ?? 'Other',
      price: price,
      stock: stock,
    );

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(product);

      if (!mounted) return;
      // reset form
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
              // Photos header + add buttons
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

              // Grid of thumbnails (tap to view full, long-press to remove)
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

              // Form fields
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

              Row(
                children: [
                  Expanded(
                    child: _LightDropdown(
                      value: _category,
                      items: _categories,
                      label: 'Category',
                      onChanged: (val) => setState(() => _category = val),
                      validator: (v) => (v == null || v.isEmpty) ? 'Select a category' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
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

/* --------------------------- Light-themed inputs --------------------------- */

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

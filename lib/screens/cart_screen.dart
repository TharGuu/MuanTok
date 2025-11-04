// lib/screens/cart_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'product_detail_screen.dart';
import 'checkout_screen.dart';

/// ---------------------------------------------------------------------------
/// Lucid (Purple) Theme Tokens
/// ---------------------------------------------------------------------------
const kPurple = Color(0xFF7C3AED);   // primary (deep purple)
const kPurpleDark = Color(0xFF5B21B6);
const kLilac = Color(0xFFD8BEE5);    // accent lilac (matches your other screens)
const kCard = Color(0xFFF9F7FB);     // soft card bg
const kBorder = Color(0xFFE7DFF3);   // subtle border
const kInk = Color(0xFF1F1F1F);

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  // each item: { product: {...}, qty: int }
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Please sign in to view your cart.';
        _items = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await SupabaseService.fetchCartItems();
      if (!mounted) return;
      setState(() => _items = List<Map<String, dynamic>>.from(list));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /* ----------------------------- Pricing helpers ---------------------------- */

  num _parseNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  int _discountPercent(Map<String, dynamic> p) =>
      _parseInt(p['discount_percent']); // 0 if none

  num _discountedUnit(Map<String, dynamic> p) {
    final price = _parseNum(p['price']);
    final pct = _discountPercent(p);
    if (price <= 0 || pct <= 0) return price;
    final discounted = price - (price * (pct / 100));
    return discounted.round(); // clean baht
  }

  String _fmtBaht(num v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('00') ? v.toStringAsFixed(0) : s;
  }

  num get _subtotal {
    num total = 0;
    for (final row in _items) {
      final p = (row['product'] ?? {}) as Map<String, dynamic>;
      final qty = _parseInt(row['qty']);
      total += _discountedUnit(p) * qty;
    }
    return total;
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

  /* --------------------------- Quantity operations -------------------------- */

  Future<void> _inc(int productId) async {
    final row = _items.firstWhere(
          (e) => ((e['product'] ?? {}) as Map)['id'] == productId,
      orElse: () => {},
    );
    if (row.isEmpty) return;

    final p = (row['product'] ?? {}) as Map<String, dynamic>;
    final stock = _parseInt(p['stock']); // 0 if missing
    final current = _parseInt(row['qty']);
    final next = current + 1;

    if (stock > 0 && next > stock) {
      if (!mounted) return;
      _toast('Only $stock in stock.');
      return;
    }

    await SupabaseService.updateCartQty(productId: productId, qty: next);
    await _fetch();
  }

  Future<void> _dec(int productId) async {
    final row = _items.firstWhere(
          (e) => ((e['product'] ?? {}) as Map)['id'] == productId,
      orElse: () => {},
    );
    if (row.isEmpty) return;

    final current = _parseInt(row['qty']);
    final next = current - 1;

    if (next <= 0) {
      await SupabaseService.removeFromCart(productId: productId);
    } else {
      await SupabaseService.updateCartQty(productId: productId, qty: next);
    }
    await _fetch();
  }

  Future<void> _remove(int productId) async {
    await SupabaseService.removeFromCart(productId: productId);
    await _fetch();
  }

  Future<void> _clear() async {
    await SupabaseService.clearCart();
    await _fetch();
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

  /* ---------------------------------- UI ----------------------------------- */

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
        ? const _EmptyCart()
        : RefreshIndicator(
      color: kPurple,
      onRefresh: _fetch,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 140),
        itemBuilder: (context, i) {
          final row = _items[i];
          final p =
          (row['product'] ?? {}) as Map<String, dynamic>;
          final pid = p['id'] as int?;
          if (pid == null) return const SizedBox.shrink();

          final name = (p['name'] ?? '').toString();
          final img = _firstImage(p['image_urls']);
          final price = _parseNum(p['price']);
          final pct = _discountPercent(p);
          final unit = _discountedUnit(p);
          final qty = _parseInt(row['qty']);
          final stock = _parseInt(p['stock']);
          final outOfStock = stock <= 0;
          final reachedMax = !outOfStock && qty >= stock;
          final canInc =
          !(outOfStock || (stock > 0 && qty >= stock));

          // small warning text
          String? warn;
          if (outOfStock) {
            warn = 'Unavailable';
          } else if (reachedMax) {
            final remaining = stock - qty;
            warn = remaining <= 0
                ? 'You reached the maximum available.'
                : 'Only $remaining left.';
          }

          return _CartCard(
            imageUrl: img,
            title: name,
            price: price,
            discountPercent: pct,
            discountedUnit: unit,
            qty: qty,
            stock: stock,
            warning: warn,
            onDec: () => _dec(pid),
            onInc: () {
              if (canInc) {
                _inc(pid);
              } else {
                final remaining = stock - qty;
                final msg = outOfStock
                    ? 'Unavailable'
                    : (remaining <= 0
                    ? 'Only $stock in stock.'
                    : 'Only $remaining left.');
                _toast(msg);
              }
            },
            onRemove: () => _remove(pid),
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
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: _items.length,
      ),
    );

    return WillPopScope(
      onWillPop: () async {
        // Always go back to the first (Shop) screen
        Navigator.of(context).popUntil((r) => r.isFirst);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('My Cart'),
          centerTitle: true,
          leading: IconButton(
            tooltip: 'Back to Home',
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                Navigator.of(context).popUntil((r) => r.isFirst),
          ),
          actions: [
            if (_items.isNotEmpty)
              TextButton(
                onPressed: _clear,
                child: const Text(
                  'Clear',
                  style: TextStyle(color: Colors.white),
                ),
              ),
          ],
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [kPurple, kPurpleDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        body: body,
        bottomNavigationBar: _items.isEmpty
            ? null
            : _SubtotalBar(
          subtotalText: '฿ ${_fmtBaht(_subtotal)}',
          onCheckout: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CheckoutScreen()),
            );
          },
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Cards & Widgets (Lucid style)
/// ---------------------------------------------------------------------------

class _CartCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final num price;
  final int discountPercent;
  final num discountedUnit;
  final int qty;
  final int stock;
  final String? warning;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onRemove;
  final VoidCallback onOpenDetail;

  const _CartCard({
    required this.imageUrl,
    required this.title,
    required this.price,
    required this.discountPercent,
    required this.discountedUnit,
    required this.qty,
    required this.stock,
    required this.warning,
    required this.onDec,
    required this.onInc,
    required this.onRemove,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final outOfStock = stock <= 0;
    final hasDiscount = discountPercent > 0 && price > 0;

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
                    // title
                    Text(
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
                    const SizedBox(height: 6),

                    // price row
                    hasDiscount
                        ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ⬇️ discounted price in RED
                        Text(
                          '฿ ${_fmt(discountedUnit)}',
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
                        // ⬇️ percentage chip in RED
                        _DiscountChip(percent: discountPercent),
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

                    // stock + warning
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
                        const Spacer(),
                        IconButton(
                          tooltip: 'Remove',
                          icon:
                          const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: onRemove,
                        ),
                      ],
                    ),

                    if (warning != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5E5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          warning!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8A4B00),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // qty controls
                    Row(
                      children: [
                        _QtyButton(icon: Icons.remove, onTap: onDec),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '$qty',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: kInk,
                            ),
                          ),
                        ),
                        _QtyButton(icon: Icons.add, onTap: onInc),
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

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Always handle taps so they don't bubble up to ListTile.onTap
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kLilac, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: kPurple.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: kPurpleDark),
      ),
    );
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
        color: Colors.red.shade600, // solid red
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

class _SubtotalBar extends StatelessWidget {
  final String subtotalText;
  final VoidCallback onCheckout;
  const _SubtotalBar({
    required this.subtotalText,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: kBorder)),
        color: Colors.white,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: kCard,
            border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: kPurple.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Subtotal',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtotalText,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: kInk,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onCheckout,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Checkout'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    elevation: 0,
                    backgroundColor: kPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 60),
        Icon(Icons.shopping_cart_outlined,
            size: 72, color: kPurple.withOpacity(.35)),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Your cart is empty',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: kInk,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text('Discover products and add them to your cart.',
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

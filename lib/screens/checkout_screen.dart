// lib/screens/checkout_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Cards feature
import '../features/profile/payment_cards_screen.dart';
import '../services/card_service.dart'; // PaymentCardLite, CardService

// Profile edit (for address)
import 'edit_profile_screen.dart';
import '../models/user_profile.dart';

// Success screen
import 'payment_success_screen.dart';

/* ------------------------------ Lucid Theme ------------------------------ */

const kPrimary = Color(0xFF7C3AED); // Purple core
const kPrimaryLiteA = Color(0xFFF2ECFF);
const kPrimaryLiteB = Color(0xFFEDE7FF);
const kText = Color(0xFF1F2937);
const kMuted = Color(0xFF6B7280);
const kDanger = Color(0xFFE11D48);
const kWarn = Color(0xFFFFA000);
const kBgTop = Color(0xFFF8F5FF);
const kBgBottom = Color(0xFFFDFBFF);
const kGlass = Color(0xFFFFFFFF);

BoxDecoration glassCard([double radius = 18]) => BoxDecoration(
  color: kGlass.withOpacity(.9),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: const Color(0x11000000)),
  boxShadow: const [
    BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 6))
  ],
);

TextStyle sectionTitle(BuildContext c) =>
    Theme.of(c).textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: .2,
    );

/* ------------------------------------------------------------------------ */

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _items = [];
  String? _shipName, _shipPhone, _shipAddress;

  List<Map<String, dynamic>> _coupons = [];
  Map<String, dynamic>? _selectedCoupon;

  // CONSTANT delivery fee
  num _deliveryFee = 120;
  static const double _vatRate = 0.07;

  // Payment state
  String _paymentMethod = 'qr'; // 'qr' | 'card' | 'cod'

  // --- Saved cards state ---
  List<PaymentCardLite> _cards = const [];
  int? _selectedCardId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /* ----------------------- Coupon helpers (VALIDATION) ------------------- */

  bool _isCouponActiveAndUnexpired(Map<String, dynamic> c) {
    if (c['is_active'] != true) return false;
    final raw = c['expires_at'];
    if (raw != null && raw.toString().isNotEmpty) {
      final dt = DateTime.tryParse(raw.toString());
      if (dt != null && dt.isBefore(DateTime.now())) return false;
    }
    return true;
  }

  /// Ensure the currently selected coupon is **still valid and unused**.
  /// Returns false and clears the selection if already used/invalid.
  Future<bool> _ensureCouponStillUnused() async {
    final uid = _sb.auth.currentUser?.id;
    final c = _selectedCoupon;
    if (uid == null || c == null) return true;

    // active + not expired?
    if (!_isCouponActiveAndUnexpired(c)) {
      if (mounted) {
        setState(() => _selectedCoupon = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This coupon is no longer valid.')),
        );
      }
      return false;
    }

    // still unused?
    final cpIdStr = '${c['id']}';
    final row = await _sb
        .from('user_coupons')
        .select('used_at')
        .eq('user_id', uid)
        .eq('coupon_id', cpIdStr)
        .maybeSingle();

    final usedAt = row is Map<String, dynamic> ? row['used_at'] : null;
    final alreadyUsed = usedAt != null && '$usedAt'.isNotEmpty;
    if (alreadyUsed) {
      if (mounted) {
        setState(() => _selectedCoupon = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This coupon was already used.')),
        );
      }
      return false;
    }
    return true;
  }

  /// Mark the selected coupon as used (call **after** checkout succeeds).
  Future<void> _markSelectedCouponUsed() async {
    final uid = _sb.auth.currentUser?.id;
    final c = _selectedCoupon;
    if (uid == null || c == null) return;

    final String cpIdStr = '${c['id']}';

    // Prefer RPC if you created it; fallback to guarded update
    try {
      await _sb.rpc('mark_user_coupon_used', params: {
        'p_user': uid,
        'p_coupon': cpIdStr,
      });
    } catch (_) {
      await _sb
          .from('user_coupons')
          .update({'used_at': DateTime.now().toIso8601String()})
          .eq('user_id', uid)
          .eq('coupon_id', cpIdStr)
          .filter('used_at', 'is', null);
    }
  }

  /* ------------------------------ Bootstrap ------------------------------ */

  Future<void> _bootstrap() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _loading = false;
          _error = 'Please sign in to continue to checkout.';
          _items = const [];
        });
        return;
      }
      setState(() {
        _loading = true;
        _error = null;
      });

      // Pull cart with product + event info
      final rows = await _sb.from('cart_items').select(r'''
id, qty,
product:products!cart_items_product_id_fkey(
  id, name, price, stock, image_urls, discount_percent, is_event,
  product_events(
    discount_pct,
    events(active, ends_at)
  )
)
''').eq('user_id', uid);

      final prof = await _sb
          .from('users')
          .select('id, full_name, phone, address, avatar_url, bio')
          .eq('id', uid)
          .maybeSingle();

      // Claimed coupons -> only those still UNUSED, ACTIVE, and NOT EXPIRED
      final claimed = await _sb
          .from('user_coupons')
          .select(
        'used_at, coupon_id, coupons(id, title, code, discount_type, discount_value, min_spend, expires_at, is_active)',
      )
          .eq('user_id', uid)
          .filter('used_at', 'is', null); // DB-level filter: unused only

      bool _isCouponValidNow(Map<String, dynamic> c) {
        if (c['is_active'] != true) return false;
        final raw = c['expires_at'];
        if (raw != null && raw.toString().isNotEmpty) {
          final dt = DateTime.tryParse(raw.toString());
          if (dt != null && dt.isBefore(DateTime.now())) return false;
        }
        return true;
      }

      final filteredCoupons = (claimed as List? ?? [])
          .map<Map<String, dynamic>>(
              (row) => (row['coupons'] ?? {}) as Map<String, dynamic>)
          .where(_isCouponValidNow)
          .toList();

      // Saved cards
      final cards = await CardService.listMyCards();

      setState(() {
        _items = (rows as List?)?.cast<Map<String, dynamic>>() ?? [];

        if (prof is Map<String, dynamic>) {
          String? _nz(dynamic v) {
            final s = v?.toString().trim();
            return (s == null || s.isEmpty) ? null : s;
          }
          _shipName = _nz(prof['full_name']);
          _shipPhone = _nz(prof['phone']);
          _shipAddress = _nz(prof['address']);
        }

        // keep selection only if it still exists in the new list
        if (_selectedCoupon != null) {
          final selId = '${_selectedCoupon!['id']}';
          if (!filteredCoupons.any((c) => '${c['id']}' == selId)) {
            _selectedCoupon = null;
          }
        }
        _coupons = filteredCoupons;

        _cards = cards;
        if (_selectedCardId == null && _cards.isNotEmpty) {
          _selectedCardId = _cards.first.id;
        }

        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load checkout data: $e';
      });
    }
  }

  Future<void> _reloadCards() async {
    try {
      final cards = await CardService.listMyCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        if (_cards.isEmpty) {
          _selectedCardId = null;
        } else if (_selectedCardId == null ||
            !_cards.any((c) => c.id == _selectedCardId)) {
          _selectedCardId = _cards.first.id;
        }
      });
    } catch (_) {}
  }

  Future<void> _openManageCards() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PaymentCardsScreen()),
    );
    await _reloadCards();
  }

  /* ------------------------------ helpers ------------------------------ */

  int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final i = int.tryParse(v);
      if (i != null) return i;
      final d = double.tryParse(v);
      if (d != null) return d.toInt();
    }
    return 0;
  }

  num _parseNum(dynamic v) {
    if (v is num) return v;
    if (v is String) {
      final d = double.tryParse(v);
      if (d != null) return d;
    }
    return 0;
  }

  String _fmtBaht(num v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('00') ? v.toStringAsFixed(0) : s;
  }

  /// Highest active event discount; fallback to product discount when is_event
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
      final bool isEvent = product['is_event'] == true ||
          (product['is_event'] is String &&
              product['is_event'].toString().toLowerCase() == 'true');
      final int? pct = (product['discount_percent'] is num)
          ? (product['discount_percent'] as num).toInt()
          : (product['discount_percent'] is String
          ? int.tryParse(product['discount_percent'])
          : null);
      if (isEvent && pct != null && pct > 0) best = pct;
    }
    return best;
  }

  num _discountedUnit(Map<String, dynamic> p) {
    final price = _parseNum(p['price']);
    final pct = _bestActiveDiscountPercent(p) ?? 0;
    if (price <= 0 || pct <= 0) return price;
    final discounted = price - (price * (pct / 100));
    return discounted.round();
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

  num get _couponDiscount {
    final c = _selectedCoupon;
    if (c == null || !_isCouponActiveAndUnexpired(c)) return 0;

    final type = (c['discount_type'] ?? '').toString();
    final value = _parseNum(c['discount_value']);
    final minSpend = _parseNum(c['min_spend']);
    final subtotal = _subtotal;

    if (subtotal <= 0) return 0;
    if (minSpend > 0 && subtotal < minSpend) return 0;

    if (type == 'percent') {
      final d = subtotal * (value / 100.0);
      return d.round();
    }
    if (type == 'amount') {
      return value;
    }
    return 0;
  }

  num get _vatBase => (_subtotal - _couponDiscount).clamp(0, double.infinity);
  num get _vat => (_vatBase * _vatRate).round();
  num get _grandTotal => (_vatBase + _vat + _deliveryFee).round();

  void _selectCoupon(Map<String, dynamic>? coupon) =>
      setState(() => _selectedCoupon = coupon);
  void _changePayment(String m) =>
      setState(() => _paymentMethod = m);

  Future<void> _navigateEditAddress() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;

    final prof = await _sb
        .from('users')
        .select('id, full_name, phone, address, avatar_url, bio')
        .eq('id', uid)
        .maybeSingle();

    if (!mounted) return;

    if (prof is Map<String, dynamic>) {
      try {
        String _s(dynamic v) => v?.toString() ?? '';
        String? _nz(dynamic v) {
          final s = v?.toString().trim();
          return (s == null || s.isEmpty) ? null : s;
        }
        final init = UserProfile(
          id: _s(prof['id']),
          fullName: _nz(prof['full_name']),
          phone: _nz(prof['phone']),
          address: _nz(prof['address']),
          avatarUrl: _nz(prof['avatar_url']),
          bio: _nz(prof['bio']),
          followersCount: 0,
          followingCount: 0,
          productsCount: 0,
        );
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => EditProfileScreen(initialProfile: init)));
        final updated = await _sb
            .from('users')
            .select('full_name, phone, address')
            .eq('id', _s(prof['id']))
            .maybeSingle();
        if (!mounted) return;
        if (updated is Map<String, dynamic>) {
          _shipName = _nz(updated['full_name']);
          _shipPhone = _nz(updated['phone']);
          _shipAddress = _nz(updated['address']);
          setState(() {});
        }
      } catch (_) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EditProfileScreen(
              initialProfile: UserProfile(
                  id: uid, followersCount: 0, followingCount: 0, productsCount: 0),
            ),
          ),
        );
        await _bootstrap();
      }
    }
  }

  /* ----------------------- Cart validation helpers ----------------------- */

  List<Map<String, dynamic>> get _outOfStockItems {
    final bad = <Map<String, dynamic>>[];
    for (final row in _items) {
      final p = (row['product'] ?? {}) as Map<String, dynamic>;
      final stock = _parseInt(p['stock']);
      if (stock <= 0) bad.add(row);
    }
    return bad;
  }

  List<Map<String, dynamic>> get _qtyExceedsStock {
    final bad = <Map<String, dynamic>>[];
    for (final row in _items) {
      final p = (row['product'] ?? {}) as Map<String, dynamic>;
      final stock = _parseInt(p['stock']);
      final qty = _parseInt(row['qty']);
      if (stock > 0 && qty > stock) bad.add(row);
    }
    return bad;
  }

  bool get _hasShipping =>
      (_shipName?.isNotEmpty ?? false) &&
          (_shipPhone?.isNotEmpty ?? false) &&
          (_shipAddress?.isNotEmpty ?? false);

  bool get _cartValid =>
      _items.isNotEmpty &&
          _outOfStockItems.isEmpty &&
          _qtyExceedsStock.isEmpty;

  bool get _canCheckout =>
      _hasShipping &&
          _cartValid &&
          !(_paymentMethod == 'card' &&
              (_selectedCardId == null || _cards.isEmpty));

  String? get _blockingReason {
    if (!_hasShipping) {
      return 'Please add your name, phone and shipping address.';
    }
    if (_outOfStockItems.isNotEmpty) {
      final names = _outOfStockItems
          .map((r) => ((r['product'] ?? {})['name'] ?? 'Unknown').toString())
          .take(3)
          .join(', ');
      return 'Out of stock: $names';
    }
    if (_qtyExceedsStock.isNotEmpty) {
      final names = _qtyExceedsStock
          .map((r) {
        final p = (r['product'] ?? {}) as Map<String, dynamic>;
        final n = (p['name'] ?? 'Unknown').toString();
        final s = _parseInt(p['stock']);
        return '$n (left $s)';
      })
          .take(3)
          .join(', ');
      return 'Quantity exceeds stock: $names';
    }
    if (_paymentMethod == 'card' &&
        (_selectedCardId == null || _cards.isEmpty)) {
      return 'Select or add a card.';
    }
    return null;
  }

  // ---- finalize + go success (calls Supabase RPC) ----
  Future<void> _finalizeAndGoSuccess() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;

    // Client last-guard
    if (!_canCheckout) {
      final why = _blockingReason ?? 'Please review your cart and shipping.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(why)));
      return;
    }

    // Verify selected coupon is *still* valid and unused
    final ok = await _ensureCouponStillUnused();
    if (!ok) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: kPrimary)),
    );

    try {
      final int? cpId = (_selectedCoupon?['id'] is num)
          ? (_selectedCoupon!['id'] as num).toInt()
          : int.tryParse('${_selectedCoupon?['id']}');

      await _sb.rpc('finalize_cart_checkout', params: {
        'p_user': uid,
        'p_coupon_id': cpId,
      });

      if (mounted) Navigator.of(context).pop(); // close loader

      // Mark claim as used
      await _markSelectedCouponUsed();

      // Clean local state
      if (mounted) {
        setState(() {
          _items = [];
          _selectedCoupon = null;
        });
      }

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PaymentSuccessScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close loader
      final msg = e.toString().contains('OUT_OF_STOCK')
          ? 'Some items are out of stock. Please review your cart.'
          : 'Checkout failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final warnLines = <String>[];
    if (!_hasShipping) warnLines.add('Shipping address incomplete.');
    if (_outOfStockItems.isNotEmpty) {
      final names = _outOfStockItems
          .map((r) => ((r['product'] ?? {})['name'] ?? 'Unknown').toString())
          .take(3)
          .join(', ');
      warnLines.add('Out of stock: $names');
    }
    if (_qtyExceedsStock.isNotEmpty) {
      final names = _qtyExceedsStock
          .map((r) {
        final p = (r['product'] ?? {}) as Map<String, dynamic>;
        final n = (p['name'] ?? 'Unknown').toString();
        final s = _parseInt(p['stock']);
        return '$n (left $s)';
      })
          .take(3)
          .join(', ');
      warnLines.add('Quantity exceeds stock: $names');
    }
    if (_paymentMethod == 'card' &&
        (_selectedCardId == null || _cards.isEmpty)) {
      warnLines.add('Select or add a card.');
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kBgTop, kBgBottom]),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: kText,
          title: ShaderMask(
            shaderCallback: (r) =>
                const LinearGradient(colors: [kPrimary, Color(0xFF9B8AFB)])
                    .createShader(r),
            child: const Text('Checkout',
                style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(
              child: CircularProgressIndicator(color: kPrimary))
              : _error != null
              ? _ErrorBox(error: _error!)
              : _items.isEmpty
              ? const _Empty()
              : _Content(
            items: _items,
            // warnings
            warnings: warnLines,
            shippingReady: _hasShipping,

            coupons: _coupons,
            selectedCoupon: _selectedCoupon,
            onSelectCoupon: _selectCoupon,
            shipName: _shipName,
            shipPhone: _shipPhone,
            shipAddress: _shipAddress,
            subtotal: _subtotal,
            couponDiscount: _couponDiscount,
            vat: _vat,
            vatRate: _vatRate,
            deliveryFee: _deliveryFee,
            grandTotal: _grandTotal,
            paymentMethod: _paymentMethod,
            onChangePayment: _changePayment,
            onEditAddress: _navigateEditAddress,

            // cards
            cards: _cards,
            selectedCardId: _selectedCardId,
            onSelectCard: (id) =>
                setState(() => _selectedCardId = id),
            onManageCards: _openManageCards,

            // pay
            canPay: _canCheckout,
            onPay: () async {
              if (!_canCheckout) {
                final why = _blockingReason ??
                    'Please review your cart and shipping.';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(why)),
                );
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Processing payment • ${_paymentMethod.toUpperCase()}'
                        '${_paymentMethod == 'card' ? ' • card #$_selectedCardId' : ''} • ฿ ${_fmtBaht(_grandTotal)}',
                  ),
                  backgroundColor: kPrimary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
              await _finalizeAndGoSuccess();
            },
          ),
        ),
      ),
    );
  }
}

/* ------------------------------- Widgets -------------------------------- */

class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: glassCard(16).copyWith(
          color: const Color(0xFFFFF5F7),
          border: Border.all(color: const Color(0x26E11D48)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: kDanger),
            const SizedBox(width: 10),
            Expanded(
                child: Text(error,
                    style: const TextStyle(color: kDanger, height: 1.2))),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 60),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(24),
          decoration: glassCard(),
          child: Column(
            children: [
              Icon(Icons.shopping_bag_outlined,
                  size: 72, color: kPrimary.withOpacity(.35)),
              const SizedBox(height: 12),
              const Text('No items to checkout',
                  style:
                  TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: kText)),
              const SizedBox(height: 8),
              const Text('Add something to your cart first.',
                  style: TextStyle(color: kMuted)),
            ],
          ),
        ),
        const SizedBox(height: 60),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  final List<String> warnings;           // NEW: warnings
  final bool shippingReady;              // NEW: flag for address completeness

  final List<Map<String, dynamic>> coupons;
  final Map<String, dynamic>? selectedCoupon;
  final void Function(Map<String, dynamic>?) onSelectCoupon;

  final String? shipName, shipPhone, shipAddress;
  final VoidCallback onEditAddress;

  final num subtotal, couponDiscount, vat, deliveryFee, grandTotal;
  final double vatRate;

  final String paymentMethod;
  final void Function(String) onChangePayment;

  // cards props
  final List<PaymentCardLite> cards;
  final int? selectedCardId;
  final void Function(int?) onSelectCard;
  final VoidCallback onManageCards;

  final bool canPay;                     // NEW: disables pay button
  final VoidCallback onPay;              // pay callback

  const _Content({
    required this.items,
    required this.warnings,
    required this.shippingReady,
    required this.coupons,
    required this.selectedCoupon,
    required this.onSelectCoupon,
    required this.shipName,
    required this.shipPhone,
    required this.shipAddress,
    required this.onEditAddress,
    required this.subtotal,
    required this.couponDiscount,
    required this.vat,
    required this.vatRate,
    required this.deliveryFee,
    required this.grandTotal,
    required this.paymentMethod,
    required this.onChangePayment,
    required this.cards,
    required this.selectedCardId,
    required this.onSelectCard,
    required this.onManageCards,
    required this.canPay,
    required this.onPay,
  });

  int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final i = int.tryParse(v);
      if (i != null) return i;
      final d = double.tryParse(v);
      if (d != null) return d.toInt();
    }
    return 0;
  }

  num _parseNum(dynamic v) {
    if (v is num) return v;
    if (v is String) {
      final d = double.tryParse(v);
      if (d != null) return d;
    }
    return 0;
  }

  int? _bestActiveDiscountPercent(Map<String, dynamic> product) {
    final now = DateTime.now();
    int? best;

    final rel = product['product_events'];
    if (rel is List) {
      for (final row in rel.whereType<Map>()) {
        final m = row.cast<String, dynamic>();
        final dpRaw = m['discount_pct'];
        final int? pct = (dpRaw is num)
            ? dpRaw.toInt()
            : (dpRaw is String ? int.tryParse(dpRaw) : null);

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
      final bool isEvent =
          ie == true || (ie is String && ie.toString().toLowerCase() == 'true');
      final int? pct = (dp is num)
          ? dp.toInt()
          : (dp is String ? int.tryParse(dp) : null);
      if (isEvent && pct != null && pct > 0) best = pct;
    }
    return best;
  }

  num _discountedUnit(Map<String, dynamic> p) {
    final price = _parseNum(p['price']);
    final pct = _bestActiveDiscountPercent(p) ?? 0;
    if (price <= 0 || pct <= 0) return price;
    final discounted = price - (price * (pct / 100));
    return discounted.round();
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

  String _fmtBaht(num v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('00') ? v.toStringAsFixed(0) : s;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        /* Warnings (if any) */
        if (warnings.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: glassCard(14).copyWith(
              color: const Color(0xFFFFFBF0),
              border: Border.all(color: const Color(0x33FFA000)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: kWarn),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: warnings
                        .map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $w',
                        style: const TextStyle(color: kText),
                      ),
                    ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),

        /* Address */
        Container(
          decoration: glassCard(),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                  radius: 18,
                  backgroundColor: kPrimary,
                  child: Icon(Icons.location_on, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(
                child: (shipName?.isNotEmpty == true ||
                    shipPhone?.isNotEmpty == true ||
                    shipAddress?.isNotEmpty == true)
                    ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shipName?.isNotEmpty == true)
                      Text(shipName!,
                          style:
                          const TextStyle(fontWeight: FontWeight.w800)),
                    if (shipPhone?.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(shipPhone!,
                          style: const TextStyle(color: kMuted)),
                    ],
                    if (shipAddress?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(shipAddress!,
                          style: const TextStyle(
                              color: kText, height: 1.3)),
                    ],
                  ],
                )
                    : const Text(
                    'No address set. Tap Edit to add your shipping address.',
                    style: TextStyle(color: kMuted)),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onEditAddress, child: const Text('Edit')),
            ],
          ),
        ),

        const SizedBox(height: 16),

        /* Items */
        Row(
          children: [
            const Icon(Icons.shopping_basket_rounded, color: kPrimary, size: 20),
            const SizedBox(width: 8),
            Text('Items', style: sectionTitle(context)),
          ],
        ),
        const SizedBox(height: 8),
        ...items.map((row) {
          final product = (row['product'] ?? {}) as Map<String, dynamic>;
          final name = (product['name'] ?? 'Unknown').toString();
          final price = _parseNum(product['price']);
          final pct = _bestActiveDiscountPercent(product) ?? 0;
          final unit = _discountedUnit(product);
          final qty = _parseInt(row['qty']);
          final img = _firstImage(product['image_urls']);
          final stock = _parseInt(product['stock']);
          final invalidQty = stock > 0 && qty > stock;

          return _ItemTile(
            imageUrl: img,
            title: name,
            originalPrice: price,
            discountPercent: pct,
            unitPrice: unit,
            qty: qty,
            stock: stock,
            invalidQty: invalidQty,
          );
        }),

        const SizedBox(height: 16),

        /* Coupon */
        Row(
          children: [
            const Icon(Icons.confirmation_number_outlined,
                color: kPrimary, size: 20),
            const SizedBox(width: 8),
            Text('Coupon', style: sectionTitle(context)),
          ],
        ),
        const SizedBox(height: 8),
        _CouponCarouselPicker(
          coupons: coupons,
          selected: selectedCoupon,
          onSelect: onSelectCoupon,
        ),

        const SizedBox(height: 16),

        /* Payment */
        Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                color: kPrimary, size: 20),
            const SizedBox(width: 8),
            Text('Payment Method', style: sectionTitle(context)),
          ],
        ),
        const SizedBox(height: 8),
        _PaymentSlider(value: paymentMethod, onChanged: onChangePayment),

        if (paymentMethod == 'qr') ...[
          const SizedBox(height: 10),
          _QrPayPanel(total: grandTotal),
        ] else if (paymentMethod == 'card') ...[
          const SizedBox(height: 10),
          _CardPicker(
            cards: cards,
            selectedCardId: selectedCardId,
            onSelect: onSelectCard,
            onManage: onManageCards,
          ),
        ] else if (paymentMethod == 'cod') ...[
          const SizedBox(height: 10),
          Container(
            decoration: glassCard(),
            padding: const EdgeInsets.all(14),
            child: const Text(
              'Cash on Delivery selected. Please prepare the exact amount for the courier.',
              style: TextStyle(color: kText),
            ),
          ),
        ],

        const SizedBox(height: 16),

        /* Summary (purple table) */
        Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: kPrimary, size: 20),
            const SizedBox(width: 8),
            Text('Summary', style: sectionTitle(context)),
          ],
        ),
        const SizedBox(height: 8),
        _SummaryCard(
          subtotal: subtotal,
          couponDiscount: couponDiscount,
          vat: vat,
          vatRate: vatRate,
          deliveryFee: deliveryFee,
          grandTotal: grandTotal,
          onChangeDeliveryFee: (_) {}, // not editable
        ),

        const SizedBox(height: 12),

        // Pay bar that scrolls with content
        _PayBarInline(
          totalText: '฿ ${_fmtBaht(grandTotal)}',
          onPay: onPay,
          enabled: canPay,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/* ---------------------------- Item + Coupon ----------------------------- */

class _ItemTile extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final num originalPrice;
  final int discountPercent;
  final num unitPrice;
  final int qty;

  final int stock;          // NEW
  final bool invalidQty;    // NEW

  const _ItemTile({
    required this.imageUrl,
    required this.title,
    required this.originalPrice,
    required this.discountPercent,
    required this.unitPrice,
    required this.qty,
    required this.stock,
    required this.invalidQty,
  });

  String _fmtBaht(num v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('00') ? v.toStringAsFixed(0) : s;
  }

  @override
  Widget build(BuildContext context) {
    final hasDiscount = discountPercent > 0 && originalPrice > 0;
    final isOos = stock <= 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimaryLiteA, kPrimaryLiteB],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimary.withOpacity(.20)),
        boxShadow: [
          BoxShadow(
              color: kPrimary.withOpacity(.08),
              blurRadius: 16,
              offset: const Offset(0, 8))
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: imageUrl == null
                      ? Icon(Icons.image_not_supported_outlined,
                      color: kPrimary.withOpacity(.45))
                      : Image.network(imageUrl!,
                      width: 70, height: 70, fit: BoxFit.cover),
                ),
                if (isOos)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: kDanger,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      alignment: Alignment.center,
                      child: const Text(
                        'OUT OF STOCK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: kText)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('฿ ${_fmtBaht(unitPrice)}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: hasDiscount ? kDanger : kText)),
                    if (hasDiscount) ...[
                      const SizedBox(width: 8),
                      Text('฿ ${_fmtBaht(originalPrice)}',
                          style: const TextStyle(
                              color: kMuted,
                              decoration: TextDecoration.lineThrough)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: kDanger,
                            borderRadius: BorderRadius.circular(999)),
                        child: Text('-$discountPercent%',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                    const Spacer(),
                    Text('x$qty', style: const TextStyle(color: kMuted)),
                  ],
                ),
                if (invalidQty && !isOos) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.error_outline, size: 14, color: kWarn),
                      const SizedBox(width: 6),
                      Text(
                        'Only $stock left in stock',
                        style: const TextStyle(color: kWarn, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------ Coupon Carousel (no remove) ------------------- */

class _CouponCarouselPicker extends StatefulWidget {
  final List<Map<String, dynamic>> coupons;
  final Map<String, dynamic>? selected;
  final void Function(Map<String, dynamic>?) onSelect;

  const _CouponCarouselPicker({
    required this.coupons,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<_CouponCarouselPicker> createState() => _CouponCarouselPickerState();
}

class _CouponCarouselPickerState extends State<_CouponCarouselPicker> {
  late final PageController _page = PageController(viewportFraction: 0.86);
  int _index = 0;

  String _subtitle(Map<String, dynamic> c) {
    final type = (c['discount_type'] ?? '').toString();
    final val = c['discount_value'];
    final code = (c['code'] ?? '').toString();
    final expires = (c['expires_at'] ?? '').toString();

    String typeTxt;
    if (type == 'percent') {
      typeTxt = 'Save $val%';
    } else if (type == 'amount') {
      typeTxt = 'Save ฿$val';
    } else {
      typeTxt = 'Coupon';
    }

    final parts = <String>[
      if (code.isNotEmpty) 'Code: $code',
      typeTxt,
      if (expires.isNotEmpty) 'Ends: $expires',
    ];
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.coupons.isEmpty) {
      return Container(
        decoration: glassCard(),
        padding: const EdgeInsets.all(14),
        child: const Text(
          'No claimed coupons. Claim some in Buy → Coupons.',
          style: TextStyle(color: kMuted),
        ),
      );
    }

    final selectedId = widget.selected?['id']?.toString();

    return Container(
      decoration: glassCard(),
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: Column(
        children: [
          SizedBox(
            height: 140,
            child: PageView.builder(
              controller: _page,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: widget.coupons.length,
              itemBuilder: (_, i) {
                final c = widget.coupons[i];
                final isSelected = c['id']?.toString() == selectedId;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _CouponSlideCard(
                    title: (c['title'] ?? 'Coupon').toString(),
                    subtitle: _subtitle(c),
                    selected: isSelected,
                    onTap: () {
                      widget.onSelect(c); // always select (no deselect)
                      setState(() {});
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.coupons.length,
                  (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 6,
                width: _index == i ? 18 : 6,
                decoration: BoxDecoration(
                  color: _index == i ? kPrimary : const Color(0x22000000),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CouponSlideCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _CouponSlideCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimaryLiteA, kPrimaryLiteB],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: kPrimary.withOpacity(selected ? .6 : .25),
            width: selected ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withOpacity(selected ? .15 : .08),
            blurRadius: selected ? 18 : 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kPrimary.withOpacity(.25)),
                    ),
                    child:
                    const Icon(Icons.local_offer_rounded, color: kPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: kText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: kMuted, fontSize: 12, height: 1.2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                        selected ? Colors.black : const Color(0x22000000),
                      ),
                    ),
                    child: Text(
                      selected ? 'Selected' : 'Use',
                      style: TextStyle(
                        color: selected ? Colors.white : kText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Icon(Icons.check,
                      size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* --------------------------- Payment: Lucid UI -------------------------- */

class _PaymentSlider extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;
  const _PaymentSlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [
      ('qr', Icons.qr_code_2_rounded, 'QR Pay'),
      ('card', Icons.credit_card_rounded, 'Card'),
      ('cod', Icons.local_shipping_rounded, 'COD'),
    ];

    return Container(
      decoration: glassCard(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final per =
          ((constraints.maxWidth - (gap * 2)) / 3).floorToDouble();

          Widget chip(String key, IconData icon, String label) {
            final selected = key == value;
            return SizedBox(
              width: per,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color:
                  selected ? kPrimary.withOpacity(.12) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color:
                      selected ? kPrimary : const Color(0x22000000)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChanged(key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon,
                            size: 18,
                            color: selected ? kPrimary : kText),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: selected ? kPrimary : kText),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return Row(
            children: [
              chip(options[0].$1, options[0].$2, options[0].$3),
              const SizedBox(width: gap),
              chip(options[1].$1, options[1].$2, options[1].$3),
              const SizedBox(width: gap),
              chip(options[2].$1, options[2].$2, options[2].$3),
            ],
          );
        },
      ),
    );
  }
}

class _CardPicker extends StatelessWidget {
  final List<PaymentCardLite> cards;
  final int? selectedCardId;
  final void Function(int?) onSelect;
  final VoidCallback onManage;

  const _CardPicker({
    required this.cards,
    required this.selectedCardId,
    required this.onSelect,
    required this.onManage,
  });

  String _mask(String? last4) =>
      last4 == null || last4.isEmpty ? '••••' : last4;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: glassCard(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select a card',
              style:
              TextStyle(fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 8),
          if (cards.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [kPrimary, Color(0xFF9B8AFB)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 4))
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.credit_card, color: Colors.white),
                  SizedBox(height: 10),
                  Text('No saved cards yet',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onManage,
              icon: const Icon(Icons.add),
              label: const Text('Add new card'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kPrimary),
                foregroundColor: kPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ] else ...[
            ...cards.map((c) {
              final selected = c.id == selectedCardId;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color:
                  selected ? kPrimary.withOpacity(.06) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color:
                      selected ? kPrimary : const Color(0x22000000)),
                ),
                child: RadioListTile<int>(
                  value: c.id,
                  groupValue: selectedCardId,
                  onChanged: onSelect,
                  dense: true,
                  activeColor: kPrimary,
                  title: Text(
                    '${(c.brand ?? 'Card').toUpperCase()}  •••• ${_mask(c.last4)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: kText),
                  ),
                  subtitle: Text(
                    '${(c.holder ?? '').isEmpty ? '—' : c.holder}  ·  '
                        '${(c.expMonth ?? 0).toString().padLeft(2, '0')}/${(c.expYear ?? 0) % 100}',
                    style: const TextStyle(color: kMuted, fontSize: 12),
                  ),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onManage,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Manage cards'),
                style:
                TextButton.styleFrom(foregroundColor: kPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ------------------------------- QR Panel ------------------------------- */

class _QrPayPanel extends StatelessWidget {
  final num total;
  const _QrPayPanel({required this.total});

  String _fmtBaht(num v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('00') ? v.toStringAsFixed(0) : s;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: glassCard(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Please scan here',
            style:
            TextStyle(fontWeight: FontWeight.w800, color: kPrimary),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/banners/qr_payment.png',
              width: 220,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 220,
                height: 220,
                color: Colors.white,
                alignment: Alignment.center,
                child: const Icon(Icons.qr_code_2_rounded,
                    size: 120, color: kPrimary),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Total amount: ฿ ${_fmtBaht(total)}',
            style: const TextStyle(
                fontWeight: FontWeight.w900, color: kPrimary),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------- Summary -------------------------------- */

class _SummaryCard extends StatelessWidget {
  final num subtotal, couponDiscount, vat, deliveryFee, grandTotal;
  final double vatRate;
  final void Function(num) onChangeDeliveryFee; // kept for compatibility

  const _SummaryCard({
    required this.subtotal,
    required this.couponDiscount,
    required this.vat,
    required this.vatRate,
    required this.deliveryFee,
    required this.grandTotal,
    required this.onChangeDeliveryFee,
  });

  String _fmtBaht(num v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('00') ? v.toStringAsFixed(0) : s;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [kPrimary, Color(0xFF9B8AFB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 6))
        ],
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Column(
          children: [
            _row('Subtotal', '฿ ${_fmtBaht(subtotal)}'),
            _row('Coupon',
                couponDiscount > 0 ? '- ฿ ${_fmtBaht(couponDiscount)}' : '—'),
            _row('VAT (${(vatRate * 100).toStringAsFixed(0)}%)',
                '฿ ${_fmtBaht(vat)}'),
            _row('Delivery Fee', '฿ ${_fmtBaht(deliveryFee)}'),
            const SizedBox(height: 8),
            Divider(
                color: Colors.white.withOpacity(.3),
                height: 18,
                thickness: 1),
            Row(
              children: [
                const Expanded(
                    child: Text('Total',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16))),
                Text('฿ ${_fmtBaht(grandTotal)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(.9)))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

/* ------------------------ Pay Bar (scrolls inline) ----------------------- */

class _PayBarInline extends StatelessWidget {
  final String totalText;
  final VoidCallback onPay;
  final bool enabled; // NEW
  const _PayBarInline({
    required this.totalText,
    required this.onPay,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : .6,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient:
            const LinearGradient(colors: [kPrimary, Color(0xFF9B8AFB)]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(0, 6))
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      const TextSpan(
                          text: 'Total\n',
                          style:
                          TextStyle(color: Colors.white70, fontSize: 12)),
                      TextSpan(
                          text: totalText,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: onPay,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Pay now'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: Colors.white,
                  foregroundColor: kPrimary,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

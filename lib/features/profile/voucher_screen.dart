// lib/features/profile/voucher_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
/* ------------------------------ Lucid Theme ------------------------------ */
const _kPrimary = Color(0xFF7C3AED); // Purple core
const _kPrimary2 = Color(0xFF9B8AFB);
const _kText = Color(0xFF1F2937);
const _kMuted = Color(0xFF6B7280);
const _kBgTop = Color(0xFFF8F5FF);
const _kBgBottom = Color(0xFFFDFBFF);

BoxDecoration _glass([double r = 16]) => BoxDecoration(
  color: Colors.white.withOpacity(.92),
  borderRadius: BorderRadius.circular(r),
  border: Border.all(color: const Color(0x11000000)),
  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 6))],
);

/* ------------------------------ Public Screen ---------------------------- */

enum VoucherTab { available, history }

class VoucherScreen extends StatefulWidget {
  final VoucherTab initialTab;
  const VoucherScreen({super.key, this.initialTab = VoucherTab.available});

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  /// Raw rows from `user_coupons` joined with `coupons`.
  /// Each row normalized into:
  /// {
  ///   'id': <coupon id>,
  ///   'title': ...,
  ///   'code': ...,
  ///   'discount_type': 'percent' | 'amount',
  ///   'discount_value': num,
  ///   'min_spend': num?,
  ///   'expires_at': String/DateTime?,
  ///   'is_active': bool?,
  ///   'claimed_at': String/DateTime?,
  ///   'used_at': String/DateTime?, // from user_coupons
  /// }
  List<Map<String, dynamic>> _vouchers = [];

  VoucherTab _tab = VoucherTab.available;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _fetch();
  }

  Future<void> _fetch() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Please sign in to view your vouchers.';
      });
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final rows = await _sb
          .from('user_coupons')
          .select('''
            id, user_id, coupon_id, claimed_at, used_at,
            coupons(
              id, title, code, discount_type, discount_value, min_spend,
              expires_at, is_active
            )
          ''')
          .eq('user_id', uid)
          .order('claimed_at', ascending: false);

      final list = <Map<String, dynamic>>[];
      if (rows is List) {
        for (final r in rows.whereType<Map>()) {
          final c = (r['coupons'] ?? {}) as Map<String, dynamic>;
          Map<String, dynamic> n = {};
          T? _as<T>(dynamic v) => v is T ? v : null;
          String? _s(dynamic v) => v?.toString();

          n['id'] = _as<int>(c['id']) ?? int.tryParse(_s(c['id']) ?? '');
          n['title'] = _s(c['title']) ?? 'Coupon';
          n['code'] = _s(c['code']) ?? '';
          n['discount_type'] = _s(c['discount_type']) ?? '';
          n['discount_value'] = _num(c['discount_value']);
          n['min_spend'] = _num(c['min_spend']);
          n['expires_at'] = c['expires_at'];
          n['is_active'] = c['is_active'] == true ||
              (_s(c['is_active'])?.toLowerCase() == 'true');

          n['claimed_at'] = r['claimed_at'];
          n['used_at'] = r['used_at'];

          list.add(n);
        }
      }

      setState(() {
        _vouchers = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load vouchers: $e';
        _loading = false;
      });
    }
  }

  bool _isExpired(Map<String, dynamic> m) {
    final raw = m['expires_at'];
    DateTime? dt;
    if (raw is String) dt = DateTime.tryParse(raw);
    if (raw is DateTime) dt = raw;
    if (dt == null) return false;
    return DateTime.now().isAfter(dt);
  }

  bool _isUsed(Map<String, dynamic> m) {
    final used = m['used_at'];
    if (used == null) return false;
    if (used is String) return used.isNotEmpty;
    return true;
  }

  List<Map<String, dynamic>> get _available =>
      _vouchers.where((v) => !_isUsed(v) && !_isExpired(v) && (v['is_active'] == true)).toList();

  List<Map<String, dynamic>> get _usedExpired =>
      _vouchers.where((v) => _isUsed(v) || _isExpired(v) || v['is_active'] != true).toList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [_kBgTop, _kBgBottom],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: _kText,
          title: ShaderMask(
            shaderCallback: (r) =>
                const LinearGradient(colors: [_kPrimary, _kPrimary2]).createShader(r),
            child: const Text('My Coupons',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _fetch,
            ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : _error != null
              ? _ErrorBox(error: _error!)
              : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final available = _available;
    final usedExpired = _usedExpired;

    return Column(
      children: [
        const SizedBox(height: 12),
        _TabSwitcher(
          value: _tab,
          onChanged: (t) => setState(() => _tab = t),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: (_tab == VoucherTab.available)
              ? (available.isEmpty
              ? const _EmptyState(
            title: 'No vouchers yet',
            caption: 'Claim vouchers in the shop and they’ll appear here.',
          )
              : _VoucherList(
            title: 'Available',
            vouchers: available,
            primaryPurple: _kPrimary,
          ))
              : (usedExpired.isEmpty
              ? const _EmptyState(
            title: 'Nothing here',
            caption: 'Your used or expired vouchers will show up here.',
          )
              : _VoucherList(
            title: 'Used & expired',
            vouchers: usedExpired,
            primaryPurple: _kPrimary,
          )),
        ),
      ],
    );
  }
}

/* -------------------------------- Widgets -------------------------------- */

class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: _glass(16).copyWith(
          color: const Color(0xFFFFF5F7),
          border: Border.all(color: const Color(0x26E11D48)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFE11D48)),
            const SizedBox(width: 10),
            Expanded(child: Text(error, style: const TextStyle(color: Color(0xFFE11D48), height: 1.2))),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String caption;
  const _EmptyState({required this.title, required this.caption});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _glass(18),
          child: Column(
            children: [
              Icon(Icons.local_offer_outlined, size: 64, color: _kPrimary.withOpacity(.35)),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _kText)),
              const SizedBox(height: 6),
              Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: _kMuted)),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _TabSwitcher extends StatelessWidget {
  final VoucherTab value;
  final ValueChanged<VoucherTab> onChanged;
  const _TabSwitcher({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x22000000)),
      ),
      child: Row(
        children: [
          _chip('Available', value == VoucherTab.available, () => onChanged(VoucherTab.available)),
          const SizedBox(width: 6),
          _chip('History', value == VoucherTab.history, () => onChanged(VoucherTab.history)),
        ],
      ),
    );
  }

  Widget _chip(String text, bool selected, VoidCallback onTap) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? _kPrimary.withOpacity(.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _kPrimary : Colors.transparent),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? _kPrimary : _kText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoucherList extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> vouchers;
  final Color primaryPurple;

  const _VoucherList({
    required this.title,
    required this.vouchers,
    required this.primaryPurple,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Row(
          children: [
            const Icon(Icons.local_offer_rounded, color: _kPrimary, size: 20),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
            )),
          ],
        ),
        const SizedBox(height: 10),
        ...vouchers.map((c) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _VoucherCard(coupon: c),
        )),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _VoucherCard extends StatelessWidget {
  final Map<String, dynamic> coupon;
  const _VoucherCard({required this.coupon});

  bool get _used => coupon['used_at'] != null && coupon['used_at'].toString().isNotEmpty;
  bool get _expired {
    final raw = coupon['expires_at'];
    DateTime? dt;
    if (raw is String) dt = DateTime.tryParse(raw);
    if (raw is DateTime) dt = raw;
    if (dt == null) return false;
    return DateTime.now().isAfter(dt);
  }

  String _subtitle() {
    final type = (coupon['discount_type'] ?? '').toString();
    final val = _num(coupon['discount_value']);
    final code = (coupon['code'] ?? '').toString();
    final expires = (coupon['expires_at'] ?? '').toString();

    final parts = <String>[];
    if (code.isNotEmpty) parts.add('Code: $code');
    if (type == 'percent') {
      parts.add('Save ${_fmtNoTrailing(val)}%');
    } else if (type == 'amount') {
      parts.add('Save ฿${_fmtNoTrailing(val)}');
    } else {
      parts.add('Coupon');
    }
    if (expires.isNotEmpty) parts.add('Ends: $expires');
    return parts.join(' • ');
  }

  Future<void> _onTap(BuildContext context, bool isAvailable) async {
    if (!isAvailable) return; // history is read-only
    final code = (coupon['code'] ?? '').toString();
    if (code.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: code));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Coupon code "$code" copied'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coupon selected'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUsed = _used;
    final isExpired = _expired;
    final isAvailable = !isUsed && !isExpired && (coupon['is_active'] == true);
    final iconColor = isAvailable ? _kPrimary : Colors.grey;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _onTap(context, isAvailable), // tap = use logic (no button)
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF2ECFF), Color(0xFFEDE7FF)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kPrimary.withOpacity(.20)),
            boxShadow: [BoxShadow(color: _kPrimary.withOpacity(.08), blurRadius: 16, offset: Offset(0, 8))],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      height: 42, width: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kPrimary.withOpacity(.25)),
                      ),
                      child: Icon(Icons.local_offer_rounded, color: iconColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (coupon['title'] ?? 'Coupon').toString(),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, color: _kText),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _subtitle(),
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _kMuted, fontSize: 12, height: 1.2),
                          ),
                        ],
                      ),
                    ),
                    // 👉 removed the trailing "Use" / "Used" / "Expired" chip entirely
                  ],
                ),
              ),
              if (isUsed || isExpired)
                Positioned(
                  right: 10, top: 10,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isUsed ? Colors.black87 : Colors.redAccent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Icon(isUsed ? Icons.check : Icons.timer_off, size: 14, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


/* --------------------------------- Utils --------------------------------- */

num _num(dynamic v) {
  if (v is num) return v;
  if (v is String) {
    final d = double.tryParse(v);
    if (d != null) return d;
  }
  return 0;
}

String _fmtNoTrailing(num v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('00') ? v.toStringAsFixed(0) : s;
}

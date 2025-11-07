import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/order_service.dart';
import 'order_detail_screen.dart';

/* -------- Lucid tokens -------- */
const kPrimary  = Color(0xFF7C3AED);
const kText     = Color(0xFF1F2937);
const kMuted    = Color(0xFF6B7280);
const kLiteA    = Color(0xFFF2ECFF);
const kLiteB    = Color(0xFFEDE7FF);
const kBgTop    = Color(0xFFF8F5FF);
const kBgBottom = Color(0xFFFDFBFF);

BoxDecoration glassCard([double r = 16]) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(r),
  border: Border.all(color: const Color(0x15000000)),
  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 8))],
);

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key});
  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<OrderLite> _orders = [];
  final Map<int, List<Map<String, dynamic>>> _itemsByOrder = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });

      final data = await OrderService.listMyOrders();
      _orders = data;

      _itemsByOrder.clear();
      if (_orders.isNotEmpty) {
        final ids = _orders.map((e) => e.id).toList();
        List<Map<String, dynamic>> rows = const [];
        if (ids.isNotEmpty) {
          final idList = '(${ids.join(',')})';
          final res = await _sb
              .from('order_items')
              .select(r'''
order_id, product_id, name, thumbnail_url, qty, unit_price,
products:products!order_items_product_id_fkey(image_urls)
''')
              .filter('order_id', 'in', idList);
          rows = (res as List).cast<Map<String, dynamic>>();
        }
        for (final r in rows) {
          final oid = (r['order_id'] as int);
          (_itemsByOrder[oid] ??= []).add(r);
        }
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /* ------------------------------ UI helpers ----------------------------- */

  Color _statusBg(String s){
    switch(s.toLowerCase()){
      case 'paid': return const Color(0xFFDCFCE7);
      case 'placed':
      case 'processing': return const Color(0xFFFFFBEB);
      case 'shipped': return const Color(0xFFE0E7FF);
      case 'delivered': return const Color(0xFFEFF6FF);
      case 'cancelled':
      case 'refunded': return const Color(0xFFFFEEF0);
      default: return const Color(0xFFF3F4F6);
    }
  }
  Color _statusFg(String s){
    switch(s.toLowerCase()){
      case 'paid': return const Color(0xFF15803D);
      case 'placed':
      case 'processing': return const Color(0xFF92400E);
      case 'shipped': return const Color(0xFF3730A3);
      case 'delivered': return const Color(0xFF1D4ED8);
      case 'cancelled':
      case 'refunded': return const Color(0xFFB91C1C);
      default: return const Color(0xFF374151);
    }
  }

  String _fmtBaht(num v){
    final s = v.toStringAsFixed(2);
    return s.endsWith('00') ? v.toStringAsFixed(0) : s;
  }

  // Pick thumbnail_url; if null, fall back to joined products.image_urls[0]
  String? _thumbFrom(Map<String, dynamic> it) {
    final t = it['thumbnail_url'];
    if (t is String && t.trim().isNotEmpty) return t;

    final prod = it['products'];
    if (prod is Map<String, dynamic>) {
      final imgs = prod['image_urls'];
      if (imgs is List && imgs.isNotEmpty) {
        final v = imgs.first;
        if (v != null && v.toString().trim().isNotEmpty) return v.toString();
      }
      if (imgs is String && imgs.trim().isNotEmpty) return imgs;
    }
    return null;
  }

  Widget _thumb(String? url, {double size = 72, double radius = 14}){
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x22000000)),
        gradient: const LinearGradient(colors:[kLiteA,kLiteB]),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null || url.isEmpty
          ? Icon(Icons.image_rounded, color: kPrimary.withOpacity(.35), size: size * .55)
          : Image.network(url, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: kPrimary.withOpacity(.35), size: size * .55)),
    );
  }

  @override
  Widget build(BuildContext context){
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kBgTop, kBgBottom]),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: kText,
          title: ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors:[kPrimary, Color(0xFF9B8AFB)]).createShader(r),
            child: const Text('My Orders', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ),
        body: RefreshIndicator(
          color: kPrimary,
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kPrimary))
              : _error != null
              ? ListView(padding: const EdgeInsets.all(16), children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ])
              : _orders.isEmpty
              ? ListView(children: const [
            SizedBox(height: 80),
            Center(child: Text('No orders yet', style: TextStyle(color: kMuted))),
          ])
              : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: _orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i){
              final o = _orders[i];
              final items = _itemsByOrder[o.id] ?? const [];

              String? firstThumb() =>
                  items.isNotEmpty ? _thumbFrom(items.first) : null;

              final firstName = items.isNotEmpty ? (items.first['name'] ?? '').toString() : '';
              final more = (items.length > 1) ? items.length - 1 : 0;

              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: ()=>Navigator.of(context).push(
                    MaterialPageRoute(builder: (_)=>OrderDetailScreen(orderId:o.id))
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: glassCard(18).copyWith(
                    gradient: const LinearGradient(colors: [kLiteA, kLiteB]),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Big preview
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _thumb(firstThumb(), size: 72, radius: 14),
                          if (more > 0)
                            Positioned(
                              right: -6, bottom: -6,
                              child: Container(
                                height: 24, width: 24,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: Text(
                                  '+$more',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),

                      // Text block
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              firstName.isEmpty ? 'Order' : firstName,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kText, fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    o.code,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: kMuted, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${o.createdAt.year}-${o.createdAt.month.toString().padLeft(2,'0')}-${o.createdAt.day.toString().padLeft(2,'0')}',
                                  style: const TextStyle(color: kMuted, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Text('฿ ${_fmtBaht(o.total)}',
                                    style: const TextStyle(color: kText, fontWeight: FontWeight.w900)),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal:10, vertical:6),
                                  decoration: BoxDecoration(
                                    color: _statusBg(o.status),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: const Color(0x11000000)),
                                  ),
                                  child: Text(
                                    o.status.replaceAll('_', ' ').toUpperCase(),
                                    style: TextStyle(color: _statusFg(o.status), fontWeight: FontWeight.w900, fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded, color: kText),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

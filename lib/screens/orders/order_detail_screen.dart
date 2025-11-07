// lib/screens/orders/order_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/order_service.dart'; // single writer

/* ------------------------------ Lucid Theme ------------------------------ */
const kPrimary = Color(0xFF7C3AED); // Purple
const kPrimaryB = Color(0xFF9B8AFB);
const kText = Color(0xFF1F2937);
const kMuted = Color(0xFF6B7280);
const kBgTop = Color(0xFFF8F5FF);
const kBgBottom = Color(0xFFFDFBFF);
const kLiteA = Color(0xFFF2ECFF);
const kLiteB = Color(0xFFEDE7FF);

BoxDecoration glassCard([double radius = 18]) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: const Color(0x11000000)),
  boxShadow: const [
    BoxShadow(color: Color(0x22000000), blurRadius: 16, offset: Offset(0, 8))
  ],
);

TextStyle _title(BuildContext c) => Theme.of(c).textTheme.titleMedium!.copyWith(
  fontWeight: FontWeight.w900,
  letterSpacing: .2,
  color: kText,
);

/* ------------------------------------------------------------------------ */

class OrderDetailScreen extends StatefulWidget {
  final int orderId;
  const OrderDetailScreen({super.key, required this.orderId});
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _loading = true;
  String? _error;
  OrderDetail? _detail;
  RealtimeChannel? _sub;

  // prevent double-submit on rating
  bool _submittingRating = false;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = OrderService.subscribeOrder(
      widget.orderId,
      onEventInsert: (row) {
        if (!mounted || _detail == null) return;
        setState(() => _detail!.events.add(row));
      },
      onStatusChange: (s) {
        if (!mounted || _detail == null) return;
        final d = _detail!;
        setState(() {
          _detail = OrderDetail(
            core: OrderLite(
              id: d.core.id,
              code: d.core.code,
              status: s,
              total: d.core.total,
              createdAt: d.core.createdAt,
            ),
            subtotal: d.subtotal,
            shippingFee: d.shippingFee,
            discount: d.discount,
            vat: d.vat,
            items: d.items,
            events: d.events,
            address: d.address,
          );
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final d = await OrderService.getOrderDetail(widget.orderId);
      setState(() {
        _detail = d;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'paid':
        return const Color(0xFF10B981);
      case 'packed':
        return kPrimary;
      case 'shipped':
        return const Color(0xFF2563EB);
      case 'delivered':
        return const Color(0xFF0EA5E9);
      case 'cancelled':
      case 'refunded':
        return const Color(0xFFE11D48);
      default:
        return kMuted;
    }
  }

  String _fmtBaht(num v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('00') ? v.toStringAsFixed(0) : s;
  }

  String _fmtDateTime(DateTime dt) => dt.toLocal().toString().split('.').first;

  /* ------------------------------- Rating UI ------------------------------ */

  Future<void> _openRateSheet(OrderItem it) async {
    // default to 5, clamp if present
    int temp = (it.myRating == null || it.myRating! < 1)
        ? 5
        : (it.myRating! > 5 ? 5 : it.myRating!);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0x22000000),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Rate this item',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: kText,
                      )),
                  const SizedBox(height: 6),
                  Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted)),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final on = i < temp;
                      return IconButton(
                        onPressed: () => setLocal(() => temp = i + 1),
                        icon: Icon(
                          on ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 32,
                          color: on ? kPrimary : const Color(0x33000000),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _submittingRating ? null : () => Navigator.pop(ctx, true),
                      child: _submittingRating
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Submit rating'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed == true) {
      try {
        setState(() => _submittingRating = true);

        // Insert once per (user_id, order_item_id)
        await OrderService.rateOrderItem(
          orderItemId: it.id,
          productId: it.productId,
          rating: temp,
          comment: null,
        );

        // Optimistic: mark this line as rated
        if (_detail != null) {
          final d = _detail!;
          final updated = d.items.map((x) {
            if (x.id == it.id) {
              return OrderItem(
                id: x.id,
                productId: x.productId,
                name: x.name,
                thumbnailUrl: x.thumbnailUrl,
                unitPrice: x.unitPrice,
                qty: x.qty,
                lineTotal: x.lineTotal,
                myRating: temp,      // set now
                avgRating: x.avgRating,
                ratingsCount: x.ratingsCount,
              );
            }
            return x;
          }).toList();
          setState(() {
            _detail = OrderDetail(
              core: d.core,
              subtotal: d.subtotal,
              shippingFee: d.shippingFee,
              discount: d.discount,
              vat: d.vat,
              items: updated,
              events: d.events,
              address: d.address,
            );
          });
        }

        // Pull latest average & count
        await _load();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Thanks for your rating!'),
          backgroundColor: kPrimary,
        ));
      } catch (e) {
        if (!mounted) return;
        final msg = e is PostgrestException ? e.message : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $msg')));
      } finally {
        if (mounted) setState(() => _submittingRating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            shaderCallback: (r) => const LinearGradient(colors: [kPrimary, kPrimaryB]).createShader(r),
            child: const Text('Order Detail', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.red))))
            : _detail == null
            ? const SizedBox.shrink()
            : _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final d = _detail!;
    final theme = Theme.of(context);
    final isDelivered = d.core.status.toLowerCase() == 'delivered';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          /* Header */
          Container(
            padding: const EdgeInsets.all(16),
            decoration: glassCard(18).copyWith(gradient: const LinearGradient(colors: [kLiteA, kLiteB])),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kPrimary.withOpacity(.15)),
                    boxShadow: [BoxShadow(color: kPrimary.withOpacity(.08), blurRadius: 14, offset: const Offset(0, 6))],
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: kPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.core.code, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: kText)),
                      const SizedBox(height: 6),
                      Text('Placed on ${_fmtDateTime(d.core.createdAt)}', style: theme.textTheme.bodySmall?.copyWith(color: kMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _statusColor(d.core.status).withOpacity(.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _statusColor(d.core.status).withOpacity(.25)),
                  ),
                  child: Text(
                    d.core.status.replaceAll('_', ' ').toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _statusColor(d.core.status),
                      fontWeight: FontWeight.w900,
                      letterSpacing: .3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          /* Tracking */
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            decoration: glassCard(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tracking', style: _title(context)),
                const SizedBox(height: 10),
                _TrackingListTimeline(currentStatus: d.core.status, createdAt: d.core.createdAt, events: d.events),
              ],
            ),
          ),

          const SizedBox(height: 16),

          /* Items */
          Text('Items', style: _title(context)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: glassCard(18),
            child: Column(
              children: d.items.map((it) {
                final img = it.thumbnailUrl;
                final alreadyRated = (it.myRating ?? 0) > 0;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: (img != null && img.isNotEmpty)
                            ? Image.network(img, width: 80, height: 80, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imgFallback())
                            : _imgFallback(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kText)),
                            const SizedBox(height: 4),
                            Text('฿ ${_fmtBaht(it.unitPrice)}  •  x${it.qty}', style: theme.textTheme.bodyMedium?.copyWith(color: kMuted)),
                            if ((it.avgRating ?? 0) > 0 && (it.ratingsCount ?? 0) > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.star_rounded, size: 16, color: kPrimary),
                                    const SizedBox(width: 4),
                                    Text('${(it.avgRating ?? 0).toStringAsFixed(1)} (${it.ratingsCount ?? 0})', style: const TextStyle(color: kMuted)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('฿ ${_fmtBaht(it.lineTotal)}', style: const TextStyle(fontWeight: FontWeight.w900, color: kText)),
                          const SizedBox(height: 6),
                          if (isDelivered && !alreadyRated)
                            OutlinedButton.icon(
                              onPressed: _submittingRating ? null : () => _openRateSheet(it),
                              icon: const Icon(Icons.star_border_rounded, size: 18),
                              label: const Text('Rate'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kPrimary,
                                side: const BorderSide(color: kPrimary),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                            )
                          else if (alreadyRated)
                            Row(
                              children: List.generate(
                                5,
                                    (i) => Icon(
                                  i < (it.myRating ?? 0) ? Icons.star_rounded : Icons.star_border_rounded,
                                  size: 18,
                                  color: kPrimary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          /* Summary */
          Text('Summary', style: _title(context)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPrimary, kPrimaryB], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 6))],
            ),
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white),
              child: Column(
                children: [
                  _sumRow('Subtotal', '฿ ${_fmtBaht(d.subtotal)}'),
                  _sumRow('Shipping', '฿ ${_fmtBaht(d.shippingFee)}'),
                  _sumRow('Discount', d.discount > 0 ? '- ฿ ${_fmtBaht(d.discount)}' : '—'),
                  const Divider(color: Colors.white30, height: 18),
                  _sumRow('VAT', '฿ ${_fmtBaht(d.vat)}'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                      Text('฿ ${_fmtBaht(d.core.total)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ],
                  )
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          /* Address */
          if (d.address != null) ...[
            Text('Shipping address', style: _title(context)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: glassCard(18),
              child: Text(
                [
                  d.address!['name'],
                  d.address!['phone'],
                  d.address!['line1'],
                  d.address!['line2'],
                  d.address!['district'],
                  d.address!['province'],
                  d.address!['postal'],
                ].where((e) => e != null && e.toString().trim().isNotEmpty).join(', '),
                style: const TextStyle(color: kText, height: 1.35),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sumRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(color: Colors.white.withOpacity(.9)))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Widget _imgFallback() => Container(
    width: 80,
    height: 80,
    color: Colors.white,
    alignment: Alignment.center,
    child: Icon(Icons.image, color: kPrimary.withOpacity(.35)),
  );
}

/* --------------------- Tracking List (dot • title • time) ---------------- */

class _TrackingListTimeline extends StatelessWidget {
  final String currentStatus; // orders.status
  final DateTime createdAt; // orders.created_at
  final List<dynamic> events; // [{event_type, created_at, note?}]

  const _TrackingListTimeline({
    required this.currentStatus,
    required this.createdAt,
    required this.events,
  });

  static const _steps = <Map<String, String>>[
    {'key': 'placed', 'title': 'PLACED', 'sub': 'Order created'},
    {'key': 'paid', 'title': 'PAID', 'sub': 'Payment confirmed'},
    {'key': 'packed', 'title': 'PACKED', 'sub': 'Seller packaging'},
    {'key': 'shipped', 'title': 'SHIPPED', 'sub': 'On the way'},
    {'key': 'delivered', 'title': 'DELIVERED', 'sub': 'Package delivered'},
  ];

  DateTime? _eventTime(String key) {
    if (key == 'placed') return createdAt;
    for (final e in events) {
      if (e is Map) {
        final t = (e['event_type'] ?? '').toString().toLowerCase();
        if (t == key && e['created_at'] != null) {
          final raw = e['created_at'];
          if (raw is String) return DateTime.tryParse(raw);
          if (raw is DateTime) return raw;
        }
      }
    }
    return null;
  }

  int _reachIndex() {
    final idx = _steps.indexWhere((m) => m['key'] == currentStatus.toLowerCase());
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _reachIndex();
    final theme = Theme.of(context);

    return Column(
      children: List.generate(_steps.length, (i) {
        final step = _steps[i];
        final reached = i <= idx;
        final t = _eventTime(step['key']!);

        Color dotColor;
        if (reached) {
          dotColor = (i == idx) ? kPrimary : const Color(0xFF10B981);
        } else {
          dotColor = const Color(0xFF9CA3AF);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                if (i != _steps.length - 1)
                  Container(
                    width: 2,
                    height: 30,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: i < idx ? dotColor.withOpacity(.5) : const Color(0x22000000),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step['title']!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: reached ? kText : kMuted,
                        letterSpacing: .3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(step['sub']!, style: theme.textTheme.bodySmall?.copyWith(color: reached ? kMuted : const Color(0xFF9CA3AF))),
                    if (t != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        t.toLocal().toString().split('.').first,
                        style: theme.textTheme.bodySmall?.copyWith(color: kMuted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

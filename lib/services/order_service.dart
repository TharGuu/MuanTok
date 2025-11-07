// lib/services/order_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

final _sb = Supabase.instance.client;

/* -------------------------------------------------------------------------- */
/* MODELS                                                                     */
/* -------------------------------------------------------------------------- */

class OrderLite {
  final int id;
  final String code;
  final String status;
  final num total;
  final DateTime createdAt;

  OrderLite({
    required this.id,
    required this.code,
    required this.status,
    required this.total,
    required this.createdAt,
  });

  factory OrderLite.fromJson(Map<String, dynamic> j) => OrderLite(
    id: (j['id'] as num).toInt(),
    code: (j['code'] ?? 'ORD-${j['id']}') as String,
    status: (j['status'] ?? 'placed') as String,
    total: (j['total'] ?? 0) as num,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

class OrderPreview extends OrderLite {
  final String? firstItemName;
  final String? firstItemThumb;

  OrderPreview({
    required super.id,
    required super.code,
    required super.status,
    required super.total,
    required super.createdAt,
    this.firstItemName,
    this.firstItemThumb,
  });

  factory OrderPreview.fromJoined(Map<String, dynamic> j) {
    String? _str(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    String? name;
    String? thumb;

    final items = j['order_items'];
    if (items is List && items.isNotEmpty) {
      final m = (items.first ?? {}) as Map<String, dynamic>;
      name = _str(m['name']);
      thumb = _str(m['thumbnail_url']);
    }

    return OrderPreview(
      id: (j['id'] as num).toInt(),
      code: (j['code'] ?? 'ORD-${j['id']}') as String,
      status: (j['status'] ?? 'placed') as String,
      total: (j['total'] ?? 0) as num,
      createdAt: DateTime.parse(j['created_at'] as String),
      firstItemName: name,
      firstItemThumb: thumb,
    );
  }
}

class OrderItem {
  final int id;
  final int productId;
  final String name;
  final String? thumbnailUrl;
  final num unitPrice;
  final int qty;
  final num lineTotal;

  // ratings
  final int? myRating;       // this user's stars for THIS order item (1..5)
  final double? avgRating;   // global avg for product (from view)
  final int? ratingsCount;   // global count for product (from view)

  OrderItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.qty,
    required this.lineTotal,
    this.thumbnailUrl,
    this.myRating,
    this.avgRating,
    this.ratingsCount,
  });

  // Not used in current flow, but kept for completeness.
  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
    id: (j['id'] as num).toInt(),
    productId: (j['product_id'] as num).toInt(),
    name: j['name'] as String,
    thumbnailUrl: j['thumbnail_url'] as String?,
    unitPrice: (j['unit_price'] ?? 0) as num,
    qty: (j['qty'] ?? 0) as int,
    lineTotal: (j['line_total'] ?? 0) as num,
    myRating: j['my_rating'] as int?,
    // If you ever SELECT with aliases, accept both:
    avgRating: (j['rating'] as num? ?? j['avg_rating'] as num?)?.toDouble(),
    ratingsCount:
    (j['rating_count'] as num? ?? j['ratings_count'] as num?)?.toInt(),
  );
}

class OrderDetail {
  final OrderLite core;
  final num subtotal, shippingFee, discount, vat;
  final List<OrderItem> items;
  /// Each event map: { event_type, note, location, created_at }
  final List<Map<String, dynamic>> events;
  final Map<String, dynamic>? address;

  OrderDetail({
    required this.core,
    required this.subtotal,
    required this.shippingFee,
    required this.discount,
    required this.vat,
    required this.items,
    required this.events,
    required this.address,
  });
}

/* -------------------------------------------------------------------------- */
/* SERVICE                                                                    */
/* -------------------------------------------------------------------------- */

class OrderService {
  static const _orders = 'orders';
  static const _items = 'order_items';
  static const _events = 'order_status_events';

  static Future<List<OrderLite>> listMyOrders({int limit = 50}) async {
    final rows = await _sb
        .from(_orders)
        .select('id, code, status, total, created_at')
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((e) => OrderLite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<OrderPreview>> listMyOrdersPreview({int limit = 50}) async {
    final rows = await _sb
        .from(_orders)
        .select(
      '''
          id, code, status, total, created_at,
          order_items!inner(id, name, thumbnail_url)
          ''',
    )
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((e) => OrderPreview.fromJoined(e as Map<String, dynamic>))
        .toList();
  }

  // ---- helper: fetch rating stats for products from the view (new columns) --
  static Future<Map<int, Map<String, num>>> _fetchRatingStatsByProductIds(
      List<int> productIds) async {
    if (productIds.isEmpty) return {};
    final rows = await _sb
        .from('product_rating_stats')
        .select('product_id, rating, rating_count')
        .inFilter('product_id', productIds);

    final out = <int, Map<String, num>>{};
    for (final r in rows as List) {
      final m = (r as Map).cast<String, dynamic>();
      final pid = (m['product_id'] as num).toInt();
      final avg = (m['rating'] as num?) ?? 0;
      final cnt = (m['rating_count'] as num?) ?? 0;
      out[pid] = {'avg': avg, 'count': cnt};
    }
    return out;
  }

  static Future<OrderDetail> getOrderDetail(int orderId) async {
    final uid = _sb.auth.currentUser?.id;

    final o = await _sb
        .from(_orders)
        .select(
      'id, code, status, total, subtotal, shipping_fee, discount, vat, address, created_at',
    )
        .eq('id', orderId)
        .single();

    final rawItems = await _sb
        .from(_items)
        .select(
      'id, product_id, name, thumbnail_url, unit_price, qty, line_total',
    )
        .eq('order_id', orderId);

    final itemIds = (rawItems as List)
        .map((e) => (e as Map<String, dynamic>)['id'])
        .whereType<int>()
        .toList();

    final productIds = (rawItems)
        .map((e) => (e as Map<String, dynamic>)['product_id'])
        .whereType<int>()
        .toList();

    // My ratings (per order-item) for this user
    List myRows = [];
    if (uid != null && itemIds.isNotEmpty) {
      myRows = await _sb
          .from('product_ratings')
          .select('order_item_id, stars')
          .eq('user_id', uid)
          .inFilter('order_item_id', itemIds);
    }

    // Global stats for these products (use new column names)
    final statsMap = await _fetchRatingStatsByProductIds(productIds);

    final myByItemId = <int, int>{};
    for (final r in myRows) {
      final m = r as Map<String, dynamic>;
      final oid = (m['order_item_id'] as num?)?.toInt();
      final stars = (m['stars'] as num?)?.toInt();
      if (oid != null && stars != null) {
        myByItemId[oid] = stars;
      }
    }

    final items = (rawItems).map<OrderItem>((raw) {
      final j = raw as Map<String, dynamic>;
      final oid = (j['id'] as num).toInt();
      final pid = (j['product_id'] as num).toInt();

      final stats = statsMap[pid];
      final avg = (stats?['avg'] ?? 0).toDouble();
      final cnt = (stats?['count'] ?? 0).toInt();

      return OrderItem(
        id: oid,
        productId: pid,
        name: j['name'] as String,
        thumbnailUrl: j['thumbnail_url'] as String?,
        unitPrice: (j['unit_price'] ?? 0) as num,
        qty: (j['qty'] ?? 0) as int,
        lineTotal: (j['line_total'] ?? 0) as num,
        myRating: myByItemId[oid],   // per purchase
        avgRating: avg,              // global (from view)
        ratingsCount: cnt,           // global (from view)
      );
    }).toList();

    final ev = await _sb
        .from(_events)
        .select('status, note, location, created_at')
        .eq('order_id', orderId)
        .order('created_at');

    final normalizedEvents = (ev as List).map<Map<String, dynamic>>((e) {
      final m = (e as Map<String, dynamic>);
      return {
        'event_type': (m['status'] ?? '').toString(),
        'note': m['note'],
        'location': m['location'],
        'created_at': m['created_at'],
      };
    }).toList();

    final core = OrderLite.fromJson(o as Map<String, dynamic>);
    return OrderDetail(
      core: core,
      subtotal: (o['subtotal'] ?? 0) as num,
      shippingFee: (o['shipping_fee'] ?? 0) as num,
      discount: (o['discount'] ?? 0) as num,
      vat: (o['vat'] ?? 0) as num,
      items: items,
      events: normalizedEvents,
      address: o['address'] as Map<String, dynamic>?,
    );
  }

  /// Insert a rating exactly once per (user_id, order_item_id).
  /// If the row already exists, the INSERT is ignored (no editing).
// Replace the whole method in OrderService with this:
  static Future<void> rateOrderItem({
    required int orderItemId,
    required int productId,
    required int rating, // 1..5
    String? comment,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw 'Not signed in';
    if (rating < 1 || rating > 5) throw 'Rating must be 1..5';

    // New rule: one row per (user_id, order_item_id)
    // We also store product_id so the stats view can GROUP BY product_id.
    await _sb.from('product_ratings').upsert(
      {
        'order_item_id': orderItemId,
        'product_id': productId,
        'user_id': uid,
        'stars': rating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      },
      onConflict: 'user_id,order_item_id',
      // If you want to prevent editing once submitted, keep this TRUE.
      // If you want to allow changing the rating for the same purchase, set FALSE.
      ignoreDuplicates: true,
    );
  }



  static RealtimeChannel subscribeOrder(
      int orderId, {
        void Function(Map<String, dynamic> row)? onEventInsert,
        void Function(String newStatus)? onStatusChange,
      }) {
    final ch = _sb.channel('order-$orderId');

    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: _events,
      callback: (payload) {
        final row = payload.newRecord;
        if (row == null) return;
        final rid = row['order_id'];
        if (rid is int && rid == orderId) {
          final normalized = {
            'event_type': (row['status'] ?? '').toString(),
            'note': row['note'],
            'location': row['location'],
            'created_at': row['created_at'],
          };
          onEventInsert?.call(normalized);
        }
      },
    );

    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: _orders,
      callback: (payload) {
        final row = payload.newRecord;
        if (row == null) return;
        final rid = row['id'];
        if (rid is int && rid == orderId) {
          final ns = (row['status'] as String?) ?? '';
          if (ns.isNotEmpty) onStatusChange?.call(ns);
        }
      },
    );

    ch.subscribe();
    return ch;
  }
}

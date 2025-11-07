// lib/services/supabase_service.dart
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final SupabaseClient _client = Supabase.instance.client;

class _Config {
  static const String productsTable = 'products';
  static const String usersTable = 'users';
  static const String storageBucketProducts = 'product-images';
  static const String eventsTable = 'events';
  static const String productEventsTable = 'product_events';
  static const String commentsTable = 'product_comment'; // MUST match your table name
  static const String cartItemsTable = 'cart_items';
  static const String ratingsTable = 'product_ratings'; // one rating per user per product
  static const String defaultOrderBy = 'id';

  /// IMPORTANT: change this if your FK name differs in Supabase.
  static const String cartItemsProductFK = 'cart_items_product_id_fkey';
}

/* -------------------------------------------------------------------------- */
/* SIMPLE MODELS USED IN UI                                                   */
/* -------------------------------------------------------------------------- */

class ImageToUpload {
  final Uint8List bytes;
  final String fileName;
  const ImageToUpload({required this.bytes, required this.fileName});
}

class EventInfo {
  final int id;
  final String name;
  final DateTime? endsAt;
  final String? bannerUrl;
  final bool active;

  const EventInfo({
    required this.id,
    required this.name,
    required this.endsAt,
    required this.bannerUrl,
    required this.active,
  });

  factory EventInfo.fromMap(Map<String, dynamic> row) {
    DateTime? _parseDt(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return EventInfo(
      id: (row['id'] as num).toInt(),
      name: (row['name'] ?? '').toString(),
      endsAt: _parseDt(row['ends_at']),
      bannerUrl: row['banner_image_url']?.toString(),
      active: row['active'] == true,
    );
  }

  String get endsAtDisplay {
    if (endsAt == null) return '';
    const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final m = (endsAt!.month >= 1 && endsAt!.month <= 12) ? names[endsAt!.month - 1] : '';
    return '$m ${endsAt!.day}, ${endsAt!.year}';
  }
}

/* -------------------------------------------------------------------------- */
/* SERVICE                                                                    */
/* -------------------------------------------------------------------------- */

class SupabaseService {
  SupabaseService._();

  /* ---------------------------- AUTH UTILITIES --------------------------- */

  static User? get currentUser => _client.auth.currentUser;
  static String? get currentUserId => _client.auth.currentUser?.id;

  static bool get isAdmin {
    final m = _client.auth.currentUser?.appMetadata ?? {};
    final v = m['is_admin'];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }

  static String requireUserId() {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('Not logged in');
    }
    return uid;
  }

  /* ------------------------------ IMAGE UPLOAD --------------------------- */

  static Future<String> uploadProductImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final path = 'uploads/$fileName';
      await _client.storage.from(_Config.storageBucketProducts).uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );
      final publicUrl =
      _client.storage.from(_Config.storageBucketProducts).getPublicUrl(path);
      return publicUrl;
    } on StorageException catch (e, st) {
      debugPrint('uploadProductImage StorageException: ${e.message}\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('uploadProductImage unknown error: $e\n$st');
      rethrow;
    }
  }

  static Future<List<String>> uploadProductImages({
    List<ImageToUpload>? images,
    String? userId,
  }) async {
    final list = images ?? <ImageToUpload>[];
    final urls = <String>[];
    for (final img in list) {
      final prefix = (userId != null && userId.isNotEmpty) ? 'user_$userId/' : '';
      final fileName = '$prefix${img.fileName}';
      final url = await uploadProductImage(bytes: img.bytes, fileName: fileName);
      urls.add(url);
    }
    return urls;
  }

  /* ------------------------------ PRODUCTS ------------------------------- */

  static Future<Map<String, dynamic>> _insertProductRow({
    required String name,
    required String description,
    required String category,
    required num price,
    required int stock,
    required List<String> imageUrls,
    required bool isEventLegacy,
    required num discountPercentLegacy,
    required String sellerId,
  }) async {
    try {
      final insertPayload = {
        'name': name,
        'description': description,
        'category': category,
        'price': price,
        'stock': stock,
        'image_urls': imageUrls,
        // legacy cols so old UI doesn't explode
        'is_event': isEventLegacy,
        'discount_percent': discountPercentLegacy,
        'seller_id': sellerId,
      };

      final row = await _client
          .from(_Config.productsTable)
          .insert(insertPayload)
          .select('''
            id,
            name,
            description,
            category,
            price,
            stock,
            image_urls,
            is_event,
            discount_percent,
            seller_id,
            rating,
            rating_count
          ''')
          .single();

      return (row as Map).cast<String, dynamic>();
    } on PostgrestException catch (e, st) {
      debugPrint('_insertProductRow PostgrestException: ${e.message}\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('_insertProductRow unknown error: $e\n$st');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> createProduct({
    required String name,
    required String description,
    required String category,
    required num price,
    required int stock,
    required List<String> imageUrls,
    bool isEvent = false,
    num discountPercent = 0,
    required String sellerId,
  }) {
    return _insertProductRow(
      name: name,
      description: description,
      category: category,
      price: price,
      stock: stock,
      imageUrls: imageUrls,
      isEventLegacy: isEvent,
      discountPercentLegacy: discountPercent,
      sellerId: sellerId,
    );
  }

  static Future<Map<String, dynamic>> insertProduct({
    required String name,
    required String description,
    required String category,
    required num price,
    required int stock,
    required List<String> imageUrls,
    bool isEvent = false,
    num discountPercent = 0,
    required String sellerId,
  }) {
    return createProduct(
      name: name,
      description: description,
      category: category,
      price: price,
      stock: stock,
      imageUrls: imageUrls,
      isEvent: isEvent,
      discountPercent: discountPercent,
      sellerId: sellerId,
    );
  }

  static num _numOrZero(dynamic v) {
    if (v is num) return v;
    if (v is String) {
      final p = num.tryParse(v);
      if (p != null) return p;
    }
    return 0;
  }

  static int _intOrZero(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  /// Return best discount_pct for each product from product_events.
  static Future<Map<int, int>> fetchBestDiscountMapForProducts(
      List<int> productIds,
      ) async {
    if (productIds.isEmpty) return {};

    try {
      final data = await _client
          .from(_Config.productEventsTable)
          .select('product_id, discount_pct')
          .inFilter('product_id', productIds);

      final bestMap = <int, int>{};
      for (final row in (data as List)) {
        final map = (row as Map).cast<String, dynamic>();
        final pid = (map['product_id'] as num?)?.toInt();
        if (pid == null) continue;

        final dp = map['discount_pct'];
        final pct = dp is int
            ? dp
            : dp is num
            ? dp.toInt()
            : int.tryParse(dp?.toString() ?? '0') ?? 0;

        if (!bestMap.containsKey(pid) || pct > bestMap[pid]!) {
          bestMap[pid] = pct;
        }
      }
      return bestMap;
    } catch (e, st) {
      debugPrint('fetchBestDiscountMapForProducts error: $e\n$st');
      return {};
    }
  }

  /// listProducts used by recommended / category / all.
  static Future<List<Map<String, dynamic>>> listProducts({
    int limit = 20,
    int offset = 0,
    String? category,
    bool? isEvent, // legacy compatibility flag (checks products.is_event)
    String orderBy = _Config.defaultOrderBy,
    bool ascending = false,
  }) async {
    try {
      const selectClause = '''
        id,
        name,
        description,
        category,
        price,
        stock,
        image_urls,
        is_event,
        discount_percent,
        seller_id,
        rating,
        rating_count,
        seller:users!products_seller_id_fkey(full_name)
      ''';

      PostgrestFilterBuilder query =
      _client.from(_Config.productsTable).select(selectClause);

      if (category != null && category.isNotEmpty) {
        query = query.eq('category', category);
      }
      if (isEvent != null) {
        // NOTE: this only filters legacy products.is_event
        query = query.eq('is_event', isEvent);
      }

      final data = await query
          .order(orderBy, ascending: ascending)
          .range(offset, offset + limit - 1);

      final list = (data as List)
          .map<Map<String, dynamic>>((row) => (row as Map).cast<String, dynamic>())
          .toList();

      for (final p in list) {
        _normalizeSeller(p);
      }

      // Enrich with best discount from product_events
      final productIds = list.map((p) => p['id']).whereType<int>().toList();
      final bestMap = await fetchBestDiscountMapForProducts(productIds);
      for (final p in list) {
        final pid = p['id'] as int?;
        if (pid != null && bestMap.containsKey(pid)) {
          p['discount_percent'] = bestMap[pid];
          p['is_event'] = true;
        }
      }

      return list;
    } on PostgrestException catch (e, st) {
      debugPrint('listProducts PostgrestException: ${e.message}\n$st');
      throw StateError('Fetch failed: ${e.message}');
    } catch (e, st) {
      debugPrint('listProducts unknown error: $e\n$st');
      throw StateError('Fetch failed (unknown): $e');
    }
  }

  static Future<List<Map<String, dynamic>>> listMyProducts({
    int limit = 120,
    int offset = 0,
    String orderBy = _Config.defaultOrderBy,
    bool ascending = false,
  }) async {
    final uid = currentUserId;
    if (uid == null) return [];

    try {
      const sel = '''
        id, name, description, category, price, stock,
        image_urls, is_event, discount_percent, seller_id, rating, rating_count
      ''';

      final data = await _client
          .from(_Config.productsTable)
          .select(sel)
          .eq('seller_id', uid)
          .order(orderBy, ascending: ascending)
          .range(offset, offset + limit - 1);

      return (data as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } on PostgrestException catch (e, st) {
      debugPrint('listMyProducts PostgrestException: ${e.message}\n$st');
      return [];
    } catch (e, st) {
      debugPrint('listMyProducts unknown error: $e\n$st');
      return [];
    }
  }

  static Future<void> updateProductStock({
    required int productId,
    required int stock,
  }) async {
    await _client.from(_Config.productsTable).update({'stock': stock}).eq('id', productId);
  }

  static Future<List<Map<String, dynamic>>> listAllEventProductsFlattened() async {
    try {
      final data = await _client
          .from(_Config.productEventsTable)
          .select('''
            discount_pct,
            products:products (
              id,
              name,
              description,
              category,
              price,
              stock,
              image_urls,
              seller_id,
              rating,
              rating_count,
              seller:users!products_seller_id_fkey(full_name)
            )
          ''');

      final result = <Map<String, dynamic>>[];
      for (final row in data as List) {
        final mapRow = (row as Map).cast<String, dynamic>();
        final prod = Map<String, dynamic>.from(
            (mapRow['products'] ?? <String, dynamic>{}) as Map);

        final dPct = mapRow['discount_pct'];
        final discount = dPct is int
            ? dPct
            : dPct is num
            ? dPct.toInt()
            : int.tryParse('${dPct ?? 0}') ?? 0;

        prod['discount_percent'] = discount;
        prod['is_event'] = true;

        _normalizeSeller(prod);
        result.add(prod);
      }

      return result;
    } on PostgrestException catch (e, st) {
      debugPrint('listAllEventProductsFlattened PostgrestException: ${e.message}\n$st');
      throw StateError('Fetch failed: ${e.message}');
    } catch (e, st) {
      debugPrint('listAllEventProductsFlattened unknown error: $e\n$st');
      throw StateError('Fetch failed (unknown): $e');
    }
  }

  static Future<List<Map<String, dynamic>>> listProductsByEvent({
    required int eventId,
    String orderBy = 'price',
    bool ascending = true,
  }) async {
    try {
      final data = await _client
          .from(_Config.productEventsTable)
          .select('''
            discount_pct,
            products:products (
              id,
              name,
              description,
              category,
              price,
              stock,
              image_urls,
              seller_id,
              rating,
              rating_count,
              seller:users!products_seller_id_fkey(full_name)
            )
          ''')
          .eq('event_id', eventId);

      final result = <Map<String, dynamic>>[];
      for (final row in data as List) {
        final mapRow = (row as Map).cast<String, dynamic>();
        final prod = Map<String, dynamic>.from(
            (mapRow['products'] ?? <String, dynamic>{}) as Map);

        final dPct = mapRow['discount_pct'];
        final discount = dPct is int
            ? dPct
            : dPct is num
            ? dPct.toInt()
            : int.tryParse('${dPct ?? 0}') ?? 0;

        prod['discount_percent'] = discount;
        prod['is_event'] = true;
        _normalizeSeller(prod);

        result.add(prod);
      }

      result.sort((a, b) {
        final pa = (a['price'] ?? 0) as num;
        final pb = (b['price'] ?? 0) as num;
        return ascending ? pa.compareTo(pb) : pb.compareTo(pa);
      });

      return result;
    } on PostgrestException catch (e, st) {
      debugPrint('listProductsByEvent PostgrestException: ${e.message}\n$st');
      throw StateError('Fetch failed: ${e.message}');
    } catch (e, st) {
      debugPrint('listProductsByEvent unknown error: $e\n$st');
      throw StateError('Fetch failed (unknown): $e');
    }
  }

  static Future<void> attachProductToEvent({
    required int productId,
    required int eventId,
    required int discountPct,
  }) async {
    try {
      await _client.from(_Config.productEventsTable).insert({
        'product_id': productId,
        'event_id': eventId,
        'discount_pct': discountPct,
      });
    } on PostgrestException catch (e, st) {
      debugPrint('attachProductToEvent PostgrestException: ${e.message}\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('attachProductToEvent unknown error: $e\n$st');
      rethrow;
    }
  }

  /* ------------------------------ EVENTS --------------------------------- */

  static Future<List<EventInfo>> fetchActiveEvents() async {
    try {
      final data = await _client
          .from(_Config.eventsTable)
          .select('id, name, ends_at, banner_image_url, active')
          .eq('active', true)
          .order('id');

      return (data as List)
          .map((row) => EventInfo.fromMap((row as Map).cast<String, dynamic>()))
          .toList();
    } on PostgrestException catch (e, st) {
      debugPrint('fetchActiveEvents PostgrestException: ${e.message}\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('fetchActiveEvents unknown error: $e\n$st');
      rethrow;
    }
  }

  static Future<String?> fetchActiveEventBannerForProduct(int productId) async {
    try {
      final rows = await _client
          .from(_Config.productEventsTable)
          .select('''
            discount_pct,
            events:events (
              id,
              name,
              active,
              banner_image_url
            )
          ''')
          .eq('product_id', productId)
          .eq('events.active', true);

      if (rows is! List || rows.isEmpty) return null;

      rows.sort((a, b) {
        final apctRaw = (a as Map)['discount_pct'];
        final bpctRaw = (b as Map)['discount_pct'];
        final apct = apctRaw is num ? apctRaw.toInt() : int.tryParse(apctRaw?.toString() ?? '0') ?? 0;
        final bpct = bpctRaw is num ? bpctRaw.toInt() : int.tryParse(bpctRaw?.toString() ?? '0') ?? 0;
        return bpct.compareTo(apct); // desc
      });

      final top = (rows.first as Map).cast<String, dynamic>();
      final evMap = top['events'];
      if (evMap is Map) {
        final banner = evMap['banner_image_url'];
        if (banner != null && banner.toString().trim().isNotEmpty) {
          return banner.toString().trim();
        }
      }
      return null;
    } on PostgrestException catch (e, st) {
      debugPrint('fetchActiveEventBannerForProduct PostgrestException: ${e.message}\n$st');
      return null;
    } catch (e, st) {
      debugPrint('fetchActiveEventBannerForProduct unknown error: $e\n$st');
      return null;
    }
  }

  /* ----------------------------- PRODUCT DETAIL --------------------------- */

  static Future<Map<String, dynamic>> fetchProductDetail(int productId) async {
    final row = await _client
        .from(_Config.productsTable)
        .select('''
          id,
          name,
          description,
          category,
          price,
          stock,
          image_urls,
          seller_id,
          rating,
          rating_count,
          seller:users!products_seller_id_fkey(full_name)
        ''')
        .eq('id', productId)
        .single();

    final p = (row as Map).cast<String, dynamic>();

    // attach best event discount
    final best = await fetchBestDiscountMapForProducts([productId]);
    p['discount_percent'] = best[productId] ?? 0;

    // normalize seller
    final sellerMap = p['seller'];
    if (sellerMap is Map && sellerMap['full_name'] != null) {
      p['seller_name'] = sellerMap['full_name'];
      p['seller_full_name'] = sellerMap['full_name'];
    }
    _normalizeSeller(p);

    // IMPORTANT: override rating with client-side aggregate from product_ratings
    final agg = await fetchRatingAggregate(productId);
    p['rating'] = agg['avg'] ?? 0;
    p['rating_count'] = agg['count'] ?? 0;

    return p;
  }

  static Future<List<Map<String, dynamic>>> listProductsForEvent({
    required int eventId,
    int limit = 120,
    int offset = 0,
  }) async {
    final rows = await _client
        .from(_Config.productEventsTable)
        .select('''
          product_id,
          discount_pct,
          products!inner(
            id, name, description, category, price, stock,
            image_urls,
            seller_id,
            rating,
            rating_count,
            seller:users!products_seller_id_fkey(full_name)
          )
        ''')
        .eq('event_id', eventId)
        .order('product_id', ascending: false)
        .range(offset, offset + limit - 1);

    final List<Map<String, dynamic>> out = [];
    for (final r in (rows as List)) {
      final map = (r as Map).cast<String, dynamic>();
      final product = Map<String, dynamic>.from((map['products'] ?? {}) as Map);
      if (product.isEmpty) continue;

      final dp = map['discount_pct'];
      final discount = dp is int
          ? dp
          : dp is num
          ? dp.toInt()
          : int.tryParse('${dp ?? 0}') ?? 0;

      final m = Map<String, dynamic>.from(product);
      m['event_discount_percent'] = discount;
      _normalizeSeller(m);
      out.add(m);
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> fetchProductEvents(int productId) async {
    final rows = await _client
        .from(_Config.productEventsTable)
        .select('''
          discount_pct,
          events (
            id,
            name,
            ends_at,
            active,
            banner_image_url
          )
        ''')
        .eq('product_id', productId);

    final list = <Map<String, dynamic>>[];
    for (final r in (rows as List)) {
      final m = (r as Map).cast<String, dynamic>();
      final evMap = m['events'] as Map<String, dynamic>?;

      final pctRaw = m['discount_pct'];
      final pct = pctRaw is num ? pctRaw : num.tryParse('$pctRaw') ?? 0;

      list.add({
        'event_id': (evMap?['id'] as num?)?.toInt(),
        'event_name': evMap?['name'] ?? 'Event',
        'ends_at': evMap?['ends_at'],
        'discount_percent': pct,
        'active': evMap?['active'] == true,
        'banner_image_url': evMap?['banner_image_url'],
      });
    }
    return list;
  }

  /* ------------------------------ COMMENTS -------------------------------- */

  static Future<List<Map<String, dynamic>>> fetchProductCommentsLimited(
      int productId, {
        int limit = 10,
      }) async {
    final uid = _client.auth.currentUser?.id;

    final rows = await _client
        .from(_Config.commentsTable)
        .select('''
          id,
          product_id,
          user_id,
          content,
          created_at,
          users:user_id ( full_name )
        ''')
        .eq('product_id', productId)
        .order('created_at', ascending: false)
        .limit(limit);

    final out = <Map<String, dynamic>>[];
    for (final raw in rows as List) {
      final m = (raw as Map).cast<String, dynamic>();
      final author = m['users'] as Map<String, dynamic>?;
      out.add({
        'id': m['id'],
        'product_id': m['product_id'],
        'user_id': m['user_id'],
        'content': m['content'],
        'created_at': m['created_at'],
        'author_name': (author?['full_name'] ?? 'User').toString(),
        'is_mine': uid != null && uid == m['user_id'],
      });
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> fetchAllProductCommentsFull(
      int productId,
      ) async {
    final uid = _client.auth.currentUser?.id;

    final rows = await _client
        .from(_Config.commentsTable)
        .select('''
          id,
          product_id,
          user_id,
          content,
          created_at,
          users:user_id ( full_name )
        ''')
        .eq('product_id', productId)
        .order('created_at', ascending: false);

    final out = <Map<String, dynamic>>[];
    for (final raw in rows as List) {
      final m = (raw as Map).cast<String, dynamic>();
      final author = m['users'] as Map<String, dynamic>?;
      out.add({
        'id': m['id'],
        'product_id': m['product_id'],
        'user_id': m['user_id'],
        'content': m['content'],
        'created_at': m['created_at'],
        'author_name': (author?['full_name'] ?? 'User').toString(),
        'is_mine': uid != null && uid == m['user_id'],
      });
    }
    return out;
  }

  static Future<Map<String, dynamic>> addProductComment({
    required int productId,
    required String content,
  }) async {
    final uid = _client.auth.currentUser?.id;

    final rows = await _client
        .from(_Config.commentsTable)
        .insert({
      'product_id': productId,
      'user_id': uid,
      'content': content,
    })
        .select('''
          id,
          product_id,
          user_id,
          content,
          created_at,
          users:user_id(full_name)
        ''');

    final inserted = (rows.first as Map).cast<String, dynamic>();
    final author = inserted['users'] as Map<String, dynamic>?;

    return {
      'id': inserted['id'],
      'product_id': inserted['product_id'],
      'user_id': inserted['user_id'],
      'content': inserted['content'],
      'created_at': inserted['created_at'],
      'author_name': (author?['full_name'] ?? 'User').toString(),
      'is_mine': true,
    };
  }

  static Future<Map<String, dynamic>> editProductComment({
    required int commentId,
    required String content,
  }) async {
    final uid = requireUserId();

    final updatedList = await _client
        .from(_Config.commentsTable)
        .update({'content': content})
        .eq('id', commentId)
        .eq('user_id', uid)
        .select('''
          id,
          product_id,
          user_id,
          content,
          created_at,
          users:user_id ( full_name )
        ''')
        .limit(1);

    if (updatedList is! List || updatedList.isEmpty) {
      throw 'Update failed (not owner or not found)';
    }

    final row = (updatedList.first as Map).cast<String, dynamic>();
    final author = row['users'] as Map<String, dynamic>?;
    final authorDisplay = (author?['full_name'] ?? 'User').toString();

    return {
      'id': row['id'],
      'product_id': row['product_id'],
      'user_id': row['user_id'],
      'content': row['content'],
      'created_at': row['created_at'],
      'author_name': authorDisplay,
      'is_mine': true,
    };
  }

  static Future<bool> deleteProductComment(int commentId) async {
    final uid = requireUserId();
    await _client.from(_Config.commentsTable).delete().eq('id', commentId).eq('user_id', uid);
    return true;
  }

  /* ----------------------------- RATINGS ---------------------------------- */
  /// One rating per user per product (1..5).
  /// Client-side aggregation + realtime (no DB triggers required).

  /// Upsert (or manual) a user's rating for a product
  static Future<void> submitProductRating({
    required int productId,
    required int stars,
  }) async {
    final uid = requireUserId();
    if (stars < 1 || stars > 5) {
      throw ArgumentError('stars must be 1..5');
    }

    // Preferred path: requires UNIQUE(product_id, user_id) on product_ratings
    try {
      await _client.from(_Config.ratingsTable).upsert(
        {'product_id': productId, 'user_id': uid, 'stars': stars},
        onConflict: 'product_id,user_id',
      );
      return;
    } on PostgrestException {
      // Fall back if UNIQUE is missing (manual upsert without using an id column)
    }

    final exist = await _client
        .from(_Config.ratingsTable)
        .select('product_id')
        .match({'product_id': productId, 'user_id': uid})
        .maybeSingle();

    if (exist != null) {
      await _client
          .from(_Config.ratingsTable)
          .update({'stars': stars})
          .match({'product_id': productId, 'user_id': uid});
    } else {
      await _client.from(_Config.ratingsTable).insert(
        {'product_id': productId, 'user_id': uid, 'stars': stars},
      );
    }
  }

  /// Return my own rating (if any)
  static Future<int?> getMyRating({required int productId}) async {
    final uid = requireUserId();
    final row = await _client
        .from(_Config.ratingsTable)
        .select('stars')
        .match({'product_id': productId, 'user_id': uid})
        .maybeSingle();
    if (row == null) return null;
    final v = row['stars'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  static Future<void> deleteMyRating({required int productId}) async {
    final uid = requireUserId();
    await _client
        .from(_Config.ratingsTable)
        .delete()
        .match({'product_id': productId, 'user_id': uid});
  }

  /// Compute {avg, count} for a product from product_ratings.
  static Future<Map<String, num>> fetchRatingAggregate(int productId) async {
    final rows = await _client
        .from(_Config.ratingsTable)
        .select('stars')
        .eq('product_id', productId);

    if (rows is! List || rows.isEmpty) {
      return {'avg': 0, 'count': 0};
    }
    num sum = 0;
    int count = 0;
    for (final r in rows) {
      final v = (r as Map)['stars'];
      final s = (v is num) ? v.toDouble() : (num.tryParse('$v') ?? 0);
      if (s > 0) {
        sum += s;
        count++;
      }
    }
    final avg = count == 0 ? 0 : (sum / count);
    return {'avg': avg, 'count': count};
  }

  /// Subscribe to changes in product_ratings for a product and recompute {avg,count}.
  static RealtimeChannel subscribeRatingAggregate({
    required int productId,
    required void Function(num avg, num count) onChange,
  }) {
    final ch = _client.channel('product_ratings_$productId');

    Future<void> _recompute() async {
      try {
        final agg = await fetchRatingAggregate(productId);
        onChange(agg['avg'] ?? 0, agg['count'] ?? 0);
      } catch (_) {}
    }

    ch
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: _Config.ratingsTable,
        callback: (payload) {
          if ((payload.newRecord['product_id'] as int?) == productId) {
            _recompute();
          }
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: _Config.ratingsTable,
        callback: (payload) {
          if ((payload.newRecord['product_id'] as int?) == productId) {
            _recompute();
          }
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: _Config.ratingsTable,
        callback: (payload) {
          if ((payload.oldRecord['product_id'] as int?) == productId) {
            _recompute();
          }
        },
      )
      ..subscribe();

    // caller can trigger an initial compute if needed
    return ch;
  }

  /// Realtime subscription to the products table (generic row watcher)
  static RealtimeChannel subscribeProduct({
    required int productId,
    required void Function(Map<String, dynamic> newRow) onChange,
  }) {
    final ch = _client.channel('product_$productId');

    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: _Config.productsTable,
      callback: (payload) {
        final newRecDynamic = payload.newRecord;
        if (newRecDynamic == null) return;
        final newRec = (newRecDynamic as Map).cast<String, dynamic>();
        final id = newRec['id'];
        if (id is int && id == productId) {
          onChange(newRec);
        }
      },
    ).subscribe();

    return ch;
  }

  /* ----------------------------- DEBUG HELPERS ---------------------------- */

  static Future<Map<String, dynamic>?> getProductById(int productId) async {
    try {
      const selectClause = '''
        id,
        name,
        description,
        category,
        price,
        stock,
        image_urls,
        is_event,
        discount_percent,
        seller_id,
        rating,
        rating_count,
        seller:users!products_seller_id_fkey(full_name)
      ''';

      final row = await _client
          .from(_Config.productsTable)
          .select(selectClause)
          .eq('id', productId)
          .single();

      final map = (row as Map).cast<String, dynamic>();
      _normalizeSeller(map);

      final bestMap = await fetchBestDiscountMapForProducts([productId]);
      if (bestMap[productId] != null) {
        map['discount_percent'] = bestMap[productId];
        map['is_event'] = true;
      }

      return map;
    } on PostgrestException catch (e, st) {
      debugPrint('getProductById PostgrestException: ${e.message}\n$st');
      return null;
    } catch (e, st) {
      debugPrint('getProductById unknown error: $e\n$st');
      return null;
    }
  }

  static Future<void> deleteProduct(int productId) async {
    try {
      await _client.from(_Config.productsTable).delete().eq('id', productId);
    } on PostgrestException catch (e, st) {
      debugPrint('deleteProduct PostgrestException: ${e.message}\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('deleteProduct unknown error: $e\n$st');
      rethrow;
    }
  }

  static void debugProductList(List<Map<String, dynamic>> products) {
    for (final p in products) {
      log('[PRODUCT] id=${p['id']} name=${p['name']} cat=${p['category']} price=${p['price']} '
          'seller=${p['seller']} discount=${p['discount_percent']} rating=${p['rating']} count=${p['rating_count']}');
    }
  }

  static void _normalizeSeller(Map<String, dynamic> p) {
    // prefer embedded object: seller:users!…(full_name)
    if (p['seller'] is Map) {
      final s = (p['seller'] as Map).cast<String, dynamic>();
      s['full_name'] ??= (p['seller_full_name'] ?? p['seller_name'] ?? 'Unknown Seller').toString();
      p['seller'] = s;
      return;
    }

    // fallback to legacy scalar strings
    final fallbackName = p['seller_full_name'] ?? p['seller_name'] ?? 'Unknown Seller';
    p['seller'] = {'full_name': fallbackName.toString()};
  }

  static Future<List<Map<String, dynamic>>> fetchProductsForEvent(int eventId) {
    return listProductsByEvent(eventId: eventId);
  }

  static Future<List<Map<String, dynamic>>> fetchRelatedProductsByCategory({
    required int productId,
    required String category,
    int limit = 8,
  }) async {
    final rows = await _client
        .from(_Config.productsTable)
        .select('''
          id,
          name,
          description,
          category,
          price,
          stock,
          image_urls,
          is_event,
          discount_percent,
          seller_id,
          rating,
          rating_count,
          seller:users!products_seller_id_fkey(full_name)
        ''')
        .eq('category', category)
        .neq('id', productId)
        .order('id', ascending: false)
        .limit(limit);

    final list = (rows as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    final productIds = list.map((p) => p['id']).whereType<int>().toList();
    final bestMap = await fetchBestDiscountMapForProducts(productIds);

    for (final p in list) {
      final pid = p['id'] as int?;
      if (pid != null && bestMap.containsKey(pid)) {
        p['discount_percent'] = bestMap[pid];
        p['is_event'] = true;
      }
      _normalizeSeller(p);
    }

    return list;
  }

  /* -------------------------------------------------------------------------- */
  /* FAVOURITES                                                                 */
  /* -------------------------------------------------------------------------- */

  static Future<void> addFavourite({required int productId}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not logged in');

    // Manual upsert (works even without a UNIQUE constraint)
    final exist = await _client
        .from('favourites')
        .select('user_id')
        .match({'user_id': uid, 'product_id': productId})
        .maybeSingle();

    if (exist == null) {
      await _client.from('favourites').insert({'user_id': uid, 'product_id': productId});
    }
  }

  static Future<void> removeFavourite({required int productId}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not logged in');
    await _client.from('favourites').delete().match({'user_id': uid, 'product_id': productId});
  }

  static Future<bool> isFavourited({required int productId}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;

    final rows = await _client
        .from('favourites')
        .select('user_id')
        .match({'user_id': uid, 'product_id': productId})
        .maybeSingle();

    return rows != null;
  }

  static Future<bool> toggleFavourite({required int productId}) async {
    final favNow = await isFavourited(productId: productId);
    if (favNow) {
      await removeFavourite(productId: productId);
      return false;
    } else {
      await addFavourite(productId: productId);
      return true;
    }
  }

  static Future<List<Map<String, dynamic>>> listMyFavourites() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];

    final rows = await _client
        .from('favourites')
        .select(
      'product:products('
          'id,name,description,category,price,stock,image_urls,'
          'discount_percent,is_event,seller_id,'
          'rating,rating_count,'
          'seller:users!products_seller_id_fkey(full_name)'
          ')',
    )
        .eq('user_id', uid)
        .order('created_at', ascending: false);

    if (rows is! List) return [];

    final products = <Map<String, dynamic>>[];
    for (final r in rows) {
      final prod = (r as Map)['product'];
      if (prod is Map) {
        final p = (prod as Map).cast<String, dynamic>();
        _normalizeSeller(p);
        products.add(p);
      }
    }

    final ids = products.map((p) => p['id']).whereType<int>().toList();
    final bestMap = await fetchBestDiscountMapForProducts(ids);
    for (final p in products) {
      final pid = p['id'] as int?;
      if (pid != null && bestMap.containsKey(pid)) {
        p['discount_percent'] = bestMap[pid];
        p['is_event'] = true;
      }
    }

    return products;
  }

  /* -------------------------------------------------------------------------- */
  /* CART (uses qty)                                                           */
  /* -------------------------------------------------------------------------- */

  /// Table: cart_items(user_id, product_id, qty, created_at)
  static Future<void> addToCart({required int productId, int qty = 1}) async {
    final uid = requireUserId();

    // Manual upsert (composite key; do not rely on an 'id' column)
    final exist = await _client
        .from(_Config.cartItemsTable)
        .select('qty')
        .match({'user_id': uid, 'product_id': productId})
        .maybeSingle();

    if (exist != null) {
      final newQty = ((exist['qty'] ?? 0) as num).toInt() + qty;
      await updateCartQty(productId: productId, qty: newQty);
    } else {
      await _client.from(_Config.cartItemsTable).insert({
        'user_id': uid,
        'product_id': productId,
        'qty': qty,
      });
    }
  }

  /// Update qty but never exceed product stock (caps at stock).
  static Future<void> updateCartQty({
    required int productId,
    required int qty,
  }) async {
    final uid = requireUserId();

    final prod = await _client
        .from(_Config.productsTable)
        .select('stock')
        .eq('id', productId)
        .single();

    final stock = ((prod['stock'] ?? 0) as num).toInt();
    final safeQty = qty < 1 ? 1 : (stock > 0 ? (qty > stock ? stock : qty) : 1);

    // Update by composite key
    final exist = await _client
        .from(_Config.cartItemsTable)
        .select('user_id')
        .match({'user_id': uid, 'product_id': productId})
        .maybeSingle();

    if (exist != null) {
      await _client
          .from(_Config.cartItemsTable)
          .update({'qty': safeQty})
          .match({'user_id': uid, 'product_id': productId});
    } else {
      await _client.from(_Config.cartItemsTable).insert({
        'user_id': uid,
        'product_id': productId,
        'qty': safeQty,
      });
    }
  }

  static Future<void> removeFromCart({required int productId}) async {
    final uid = requireUserId();
    await _client.from(_Config.cartItemsTable).delete().match({'user_id': uid, 'product_id': productId});
  }

  static Future<void> clearCart() async {
    final uid = requireUserId();
    await _client.from(_Config.cartItemsTable).delete().eq('user_id', uid);
  }

  /// Returns: [{ product: {... with discount_percent }, qty: int }]
  static Future<List<Map<String, dynamic>>> fetchCartItems() async {
    final uid = requireUserId();

    // Disambiguate the embed with the FK name after the "!"
    final selectCartWithProduct = '''
        qty,
        product:products!${_Config.cartItemsProductFK}(
          id,
          name,
          description,
          category,
          price,
          stock,
          image_urls,
          seller_id,
          rating,
          rating_count,
          seller:users!products_seller_id_fkey(full_name)
        )
      ''';

    final rows = await _client
        .from(_Config.cartItemsTable)
        .select(selectCartWithProduct)
        .eq('user_id', uid)
        .order('created_at', ascending: false);

    if (rows is! List) return [];

    final out = <Map<String, dynamic>>[];
    final ids = <int>[];
    for (final r in rows) {
      final m = (r as Map).cast<String, dynamic>();
      final prod = m['product'] as Map<String, dynamic>?;
      if (prod == null) continue;

      final p = Map<String, dynamic>.from(prod);
      _normalizeSeller(p);

      final pid = p['id'] as int?;
      if (pid != null) ids.add(pid);

      out.add({'product': p, 'qty': ((m['qty'] ?? 1) as num).toInt()});
    }

    if (ids.isNotEmpty) {
      final bestMap = await fetchBestDiscountMapForProducts(ids);
      for (final row in out) {
        final p = row['product'] as Map<String, dynamic>;
        final pid = p['id'] as int?;
        if (pid != null && bestMap.containsKey(pid)) {
          p['discount_percent'] = bestMap[pid];
          p['is_event'] = true;
        } else {
          p['discount_percent'] = 0;
        }
      }
    }

    return out;
  }
}

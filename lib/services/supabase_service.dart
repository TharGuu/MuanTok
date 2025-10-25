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

  static const String defaultOrderBy = 'id';
}

/* -------------------------------------------------------------------------- */
/* SIMPLE MODELS WE USE IN UI                                                 */
/* -------------------------------------------------------------------------- */

class ImageToUpload {
  final Uint8List bytes;
  final String fileName;
  const ImageToUpload({
    required this.bytes,
    required this.fileName,
  });
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
    return EventInfo(
      id: row['id'] as int,
      name: (row['name'] ?? '').toString(),
      endsAt: row['ends_at'] == null
          ? null
          : DateTime.tryParse(row['ends_at'].toString()),
      bannerUrl: row['banner_image_url']?.toString(),
      active: row['active'] == true,
    );
  }

  String get endsAtDisplay {
    if (endsAt == null) return '';
    final m = _monthShort(endsAt!.month);
    return '$m ${endsAt!.day}, ${endsAt!.year}';
  }

  static String _monthShort(int m) {
    const names = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    if (m < 1 || m > 12) return '';
    return names[m-1];
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

  static String requireUserId() {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('Not logged in');
    }
    return uid;
  }

  /* ------------------------------ IMAGES --------------------------------- */

  static Future<String> uploadProductImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final path = 'uploads/$fileName';

      await _client.storage
          .from(_Config.storageBucketProducts)
          .uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );

      final publicUrl = _client.storage
          .from(_Config.storageBucketProducts)
          .getPublicUrl(path);

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
      final prefix =
      (userId != null && userId.isNotEmpty) ? 'user_$userId/' : '';
      final fileName = '$prefix${img.fileName}';

      final url = await uploadProductImage(
        bytes: img.bytes,
        fileName: fileName,
      );
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
            seller_id
          ''')
          .single();

      return row as Map<String, dynamic>;
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

  // alias for backward compat
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

  /// Helper: get the highest discount_pct (best deal) from product_events
  /// for each product. Returns Map<product_id, bestDiscountPct>.
  ///
  /// 🔓 PUBLIC so search can also call it.
  static Future<Map<int, int>> fetchBestDiscountMapForProducts(
      List<int> productIds) async {
    if (productIds.isEmpty) return {};

    try {
      final data = await _client
          .from(_Config.productEventsTable)
          .select('product_id, discount_pct')
          .inFilter('product_id', productIds);

      final bestMap = <int, int>{};

      for (final row in (data as List)) {
        final pid = row['product_id'] as int?;
        if (pid == null) continue;

        final pctRaw = row['discount_pct'];
        final pct = pctRaw is int
            ? pctRaw
            : int.tryParse(pctRaw?.toString() ?? '0') ?? 0;

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

  /// listProducts:
  /// normal product fetch for category / all / recommended.
  /// After fetch, decorate with best event discount if available.
  static Future<List<Map<String, dynamic>>> listProducts({
    int limit = 20,
    int offset = 0,
    String? category,
    bool? isEvent, // legacy, caller may still pass this
    String orderBy = _Config.defaultOrderBy,
    bool ascending = false,
  }) async {
    try {
      const selectClause = r'''
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
        seller:users!products_seller_id_fkey(full_name)
      ''';

      PostgrestFilterBuilder query =
      _client.from(_Config.productsTable).select(selectClause);

      if (category != null && category.isNotEmpty) {
        query = query.eq('category', category);
      }

      if (isEvent != null) {
        // still allow old path (but new flow doesn't really use this)
        query = query.eq('is_event', isEvent);
      }

      final data = await query
          .order(orderBy, ascending: ascending)
          .range(offset, offset + limit - 1);

      final list = (data as List)
          .map<Map<String, dynamic>>((row) => row as Map<String, dynamic>)
          .toList();

      // normalize seller
      for (final p in list) {
        _normalizeSeller(p);
      }

      // inject best discount from product_events
      final productIds =
      list.map((p) => p['id']).whereType<int>().toList();
      final bestMap =
      await fetchBestDiscountMapForProducts(productIds);

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

  /// Fetch ALL products that are attached to ANY event (join product_events).
  /// We'll flatten results and decorate seller like normal.
  static Future<List<Map<String, dynamic>>>
  listAllEventProductsFlattened() async {
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
              seller:users!products_seller_id_fkey(full_name)
            )
          ''');

      final result = <Map<String, dynamic>>[];

      for (final row in data as List) {
        final mapRow = row as Map<String, dynamic>;
        final prod = Map<String, dynamic>.from(
          mapRow['products'] ?? <String, dynamic>{},
        );

        final dPct = mapRow['discount_pct'];
        prod['discount_percent'] =
        dPct is int ? dPct : int.tryParse('$dPct') ?? 0;
        prod['is_event'] = true; // mark so UI shows badge

        _normalizeSeller(prod);

        result.add(prod);
      }

      return result;
    } on PostgrestException catch (e, st) {
      debugPrint(
          'listAllEventProductsFlattened PostgrestException: ${e.message}\n$st');
      throw StateError('Fetch failed: ${e.message}');
    } catch (e, st) {
      debugPrint(
          'listAllEventProductsFlattened unknown error: $e\n$st');
      throw StateError('Fetch failed (unknown): $e');
    }
  }

  /// Fetch products for ONE specific event id.
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
              seller:users!products_seller_id_fkey(full_name)
            )
          ''')
          .eq('event_id', eventId);

      final result = <Map<String, dynamic>>[];

      for (final row in data as List) {
        final mapRow = row as Map<String, dynamic>;
        final prod = Map<String, dynamic>.from(
          mapRow['products'] ?? <String, dynamic>{},
        );

        final dPct = mapRow['discount_pct'];
        prod['discount_percent'] =
        dPct is int ? dPct : int.tryParse('$dPct') ?? 0;
        prod['is_event'] = true;
        _normalizeSeller(prod);

        result.add(prod);
      }

      // local sort by price
      result.sort((a, b) {
        final pa = (a['price'] ?? 0) as num;
        final pb = (b['price'] ?? 0) as num;
        if (ascending) {
          return pa.compareTo(pb);
        } else {
          return pb.compareTo(pa);
        }
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

  /// Attach product to an event after publish
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
      debugPrint(
          'attachProductToEvent PostgrestException: ${e.message}\n$st');
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
          .map((row) => EventInfo.fromMap(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e, st) {
      debugPrint('fetchActiveEvents PostgrestException: ${e.message}\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('fetchActiveEvents unknown error: $e\n$st');
      rethrow;
    }
  }

  /* ------------------------ OPTIONAL HELPERS ----------------------------- */

  static Future<Map<String, dynamic>?> getProductById(int productId) async {
    try {
      const selectClause = r'''
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
        seller:users!products_seller_id_fkey(full_name)
      ''';

      final row = await _client
          .from(_Config.productsTable)
          .select(selectClause)
          .eq('id', productId)
          .single();

      final map = row as Map<String, dynamic>;
      _normalizeSeller(map);

      // decorate w/ best discount
      final bestMap =
      await fetchBestDiscountMapForProducts([productId]);
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
      await _client
          .from(_Config.productsTable)
          .delete()
          .eq('id', productId);
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
      log(
        '[PRODUCT] id=${p['id']} '
            'name=${p['name']} '
            'cat=${p['category']} '
            'price=${p['price']} '
            'seller=${p['seller']} '
            'discount=${p['discount_percent']}',
      );
    }
  }

  /// Make sure product['seller'] is always { full_name: ... }
  static void _normalizeSeller(Map<String, dynamic> p) {
    if (p['seller'] == null) {
      final fallbackName = p['seller_full_name'];
      p['seller'] = {
        'full_name': fallbackName ?? 'Unknown Seller',
      };
    } else {
      if (p['seller'] is! Map<String, dynamic>) {
        p['seller'] = {
          'full_name': p['seller'].toString(),
        };
      } else {
        p['seller']['full_name'] ??= 'Unknown Seller';
      }
    }
  }

  /* ---------------------------------------------------------------------- */
  /* NEW: wrapper for PromotionScreen / EventProductsScreen                 */
  /* ---------------------------------------------------------------------- */

  /// This is what PromotionScreen expects.
  /// It just calls listProductsByEvent(...) and returns the same shape
  /// ProductCard / ProductGrid already understands.
  static Future<List<Map<String, dynamic>>> fetchProductsForEvent(
      int eventId) async {
    return listProductsByEvent(eventId: eventId);
  }
}

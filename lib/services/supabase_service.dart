// lib/services/supabase_service.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Configure names used across your app.
class _Config {
  static const String storageBucket = 'products';  // Storage bucket name
  static const String productsTable = 'products';  // DB table name
  // If your table doesn't have created_at, change to 'id'
  static const String defaultOrderBy = 'created_at';
}

/// A simple DTO for batch uploads.
class ImageToUpload {
  final Uint8List bytes;
  final String fileName; // keep extension for proper MIME
  ImageToUpload({required this.bytes, required this.fileName});
}

String _mimeFromName(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.heic')) return 'image/heic';
  if (n.endsWith('.jpeg') || n.endsWith('.jpg')) return 'image/jpeg';
  return 'application/octet-stream';
}

String _objectPath({required String userId, required String fileName}) {
  return 'users/$userId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
}

class SupabaseService {
  SupabaseService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Throws if no logged-in user. Returns the current user's id.
  static String requireUserId() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('You must be signed in to perform this action.');
    }
    return uid;
  }

  /* ---------------------------------------------------------------------- */
  /*                               UPLOADS                                  */
  /* ---------------------------------------------------------------------- */

  /// Upload a single image and return its public URL (for Public bucket)
  static Future<String> uploadProductImage({
    required Uint8List bytes,
    required String fileName,
    required String userId,
  }) async {
    final path = _objectPath(userId: userId, fileName: fileName);
    final contentType = _mimeFromName(fileName);

    try {
      await _client.storage.from(_Config.storageBucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: false),
      );
      // Public bucket → return public URL
      final url = _client.storage.from(_Config.storageBucket).getPublicUrl(path);
      debugPrint('Uploaded: $path → $url');
      return url;

      // If bucket is PRIVATE, use signed URLs instead:
      // final signed = await _client.storage.from(_Config.storageBucket).createSignedUrl(path, 3600);
      // return signed;
    } on StorageException catch (e, st) {
      debugPrint('Storage upload failed: ${e.message}\n$st');
      throw StateError('Upload failed: ${e.message}');
    } catch (e, st) {
      debugPrint('Unknown upload error: $e\n$st');
      throw StateError('Upload failed (unknown): $e');
    }
  }

  /// Upload **multiple** images and return their URLs in order.
  static Future<List<String>> uploadProductImages({
    required List<ImageToUpload> images,
    required String userId,
  }) async {
    final urls = <String>[];
    for (final img in images) {
      final url = await uploadProductImage(
        bytes: img.bytes,
        fileName: img.fileName,
        userId: userId,
      );
      urls.add(url);
    }
    return urls;
  }

  /* ---------------------------------------------------------------------- */
  /*                                INSERTS                                 */
  /* ---------------------------------------------------------------------- */

  /// Insert a product with **multiple** image URLs into `image_urls` (text[]).
  static Future<Map<String, dynamic>> insertProduct({
    required String sellerId,
    required String name,
    required String description,
    required String category,
    required double price,
    required int stock,
    required List<String> imageUrls, // <-- multiple
  }) async {
    try {
      final payload = {
        'seller_id': sellerId,
        'name': name,
        'description': description,
        'category': category,
        'price': price,
        'stock': stock,
        'image_urls': imageUrls, // <-- array column in DB
      };
      debugPrint('Insert payload keys: ${payload.keys.toList()}');

      final rows = await _client
          .from(_Config.productsTable)
          .insert(payload)
          .select()
          .limit(1);
      return rows.first as Map<String, dynamic>;
    } on PostgrestException catch (e, st) {
      debugPrint('Insert failed: ${e.message}\n$st');
      throw StateError('Insert failed: ${e.message}');
    } catch (e, st) {
      debugPrint('Unknown insert error: $e\n$st');
      throw StateError('Insert failed (unknown): $e');
    }
  }

  /// Convenience: insert with a **single** image URL (wraps into a list).
  static Future<Map<String, dynamic>> insertProductSingle({
    required String sellerId,
    required String name,
    required String description,
    required String category,
    required double price,
    required int stock,
    required String imageUrl, // single
  }) {
    return insertProduct(
      sellerId: sellerId,
      name: name,
      description: description,
      category: category,
      price: price,
      stock: stock,
      imageUrls: [imageUrl], // wrap
    );
  }

  /* ---------------------------------------------------------------------- */
  /*                               QUERIES                                  */
  /* ---------------------------------------------------------------------- */

  /// Browse products (optionally filter by category).
  static Future<List<Map<String, dynamic>>> listProducts({
    int limit = 20,
    int offset = 0,
    String? category,
    String orderBy = _Config.defaultOrderBy,
    bool ascending = false,
  }) async {
    try {
      final table = _client.from(_Config.productsTable);

      List<dynamic> rows;
      if (category != null && category.isNotEmpty) {
        rows = await table
            .select()
            .eq('category', category)
            .order(orderBy, ascending: ascending)
            .range(offset, offset + limit - 1);
      } else {
        rows = await table
            .select()
            .order(orderBy, ascending: ascending)
            .range(offset, offset + limit - 1);
      }

      return rows.map((e) => e as Map<String, dynamic>).toList();
    } on PostgrestException catch (e, st) {
      debugPrint('List products failed: ${e.message}\n$st');
      throw StateError('Fetch failed: ${e.message}');
    } catch (e, st) {
      debugPrint('Unknown fetch error: $e\n$st');
      throw StateError('Fetch failed (unknown): $e');
    }
  }

  /* ---------------------------------------------------------------------- */
  /*                                 DELETE                                  */
  /* ---------------------------------------------------------------------- */

  static Future<void> deleteProduct({required String productId}) async {
    try {
      await _client.from(_Config.productsTable).delete().eq('id', productId);
    } on PostgrestException catch (e, st) {
      debugPrint('Delete failed: ${e.message}\n$st');
      throw StateError('Delete failed: ${e.message}');
    } catch (e, st) {
      debugPrint('Unknown delete error: $e\n$st');
      throw StateError('Delete failed (unknown): $e');
    }
  }
}

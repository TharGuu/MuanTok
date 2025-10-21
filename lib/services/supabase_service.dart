// lib/services/supabase_service.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Configure names used across your app.
class _Config {
  static const String storageBucket = 'products'; // your Storage bucket name
  static const String productsTable = 'products'; // your DB table name
}

String _mimeFromName(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.heic')) return 'image/heic';
  if (n.endsWith('.jpeg') || n.endsWith('.jpg')) return 'image/jpeg';
  return 'application/octet-stream';
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

  /// Uploads product image bytes to Storage and returns a **public URL**.
  ///
  /// Make sure your Storage bucket is set to **Public** (or switch to signed URLs).
  static Future<String> uploadProductImage({
    required Uint8List bytes,
    required String fileName,
    required String userId,
  }) async {
    final path = 'users/$userId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final contentType = _mimeFromName(fileName);

    try {
      await _client.storage.from(_Config.storageBucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: contentType,
          upsert: false,
        ),
      );

      // Public bucket → return public URL
      final url = _client.storage.from(_Config.storageBucket).getPublicUrl(path);
      debugPrint('Uploaded to storage: $path → $url');
      return url;

      // If your bucket is PRIVATE, use this instead:
      // final signedUrl = await _client.storage
      //     .from(_Config.storageBucket)
      //     .createSignedUrl(path, 60 * 60);
      // return signedUrl;
    } on StorageException catch (e, st) {
      debugPrint('Storage upload failed: ${e.message}\n$st');
      throw StateError('Upload failed: ${e.message}');
    } catch (e, st) {
      debugPrint('Unknown upload error: $e\n$st');
      throw StateError('Upload failed (unknown): $e');
    }
  }

  /// Inserts a product row and returns the inserted row (map).
  ///
  /// Schema fields: seller_id, name, description, category, price, stock, image_url
  static Future<Map<String, dynamic>> insertProduct({
    required String sellerId,
    required String name,
    required String description,
    required String category,
    required double price,
    required int stock,
    required String imageUrl,
  }) async {
    try {
      final rows = await _client
          .from(_Config.productsTable)
          .insert({
        'seller_id': sellerId,
        'name': name,
        'description': description,
        'category': category,
        'price': price,
        'stock': stock,
        'image_url': imageUrl,
      })
          .select()
          .limit(1);
      final row = rows.first as Map<String, dynamic>;
      debugPrint('Inserted product: $row');
      return row;
    } on PostgrestException catch (e, st) {
      debugPrint('Insert failed: ${e.message}\n$st');
      throw StateError('Insert failed: ${e.message}');
    } catch (e, st) {
      debugPrint('Unknown insert error: $e\n$st');
      throw StateError('Insert failed (unknown): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Optional helpers (nice for your Buy tab or admin tools)
  // ---------------------------------------------------------------------------

  /// Returns latest products (public browse).
  static Future<List<Map<String, dynamic>>> listProducts({
    int limit = 20,
    int offset = 0,
    String? category, // filter by category if provided
    String orderBy = 'created_at',
    bool ascending = false,
  }) async {
    try {
      final table = _client.from(_Config.productsTable);

      // Build query in branches to avoid assigning different builder types.
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

  /// Deletes a product by id.
  /// (If you also want to delete the image from Storage, store the object path separately.)
  static Future<void> deleteProduct({
    required String productId,
  }) async {
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

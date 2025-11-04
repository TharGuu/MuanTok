// lib/services/voucher_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class VoucherService {
  static final SupabaseClient _sb = Supabase.instance.client;

  /// List active coupons. If [excludeAlreadyClaimed] is true, remove any coupons
  /// already claimed by the current user (client-side filter).
  static Future<List<Map<String, dynamic>>> fetchActiveCoupons({
    bool excludeAlreadyClaimed = false,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final rows = await _sb
        .from('coupons')
        .select(
      'id, code, title, description, image_url, discount_type, discount_value, min_spend, expires_at, is_active',
    )
        .eq('is_active', true)
    // keep if no expiry or expires in the future
        .or('expires_at.is.null,expires_at.gt.$nowIso')
        .order('id', ascending: false);

    final list = (rows as List).cast<Map<String, dynamic>>();
    if (!excludeAlreadyClaimed) return list;

    final uid = _sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return list;

    final claimedRows =
    await _sb.from('user_coupons').select('coupon_id').eq('user_id', uid);

    final claimed = <String>{
      for (final r in (claimedRows as List))
        if (r['coupon_id'] != null) r['coupon_id'].toString(),
    };

    return list.where((c) => !claimed.contains('${c['id']}')).toList();
  }

  /// Claim a coupon by its **numeric ID**.
  /// This matches code that calls: `VoucherService.claimCoupon(couponId)`.
  static Future<void> claimCoupon(int couponId) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw StateError('Please sign in to claim coupons.');
    }
    // Insert into user_coupons. Rely on unique (user_id, coupon_id) to block duplicates.
    await _sb.from('user_coupons').insert({
      'user_id': uid,
      'coupon_id': couponId.toString(), // coupon_id is text/varchar in your schema
    });
  }

  /// Claim a coupon by its **code** (e.g., "WELCOME50").
  static Future<void> claimCouponByCode(String code) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw StateError('Please sign in to claim coupons.');
    }
    if (code.trim().isEmpty) {
      throw StateError('Invalid coupon code.');
    }

    final rows = await _sb
        .from('coupons')
        .select('id, is_active, expires_at')
        .eq('code', code)
        .limit(1);

    if (rows is! List || rows.isEmpty) {
      throw StateError('Coupon not found.');
    }

    final c = rows.first as Map<String, dynamic>;
    final couponId = c['id']?.toString();
    if (couponId == null || couponId.isEmpty) {
      throw StateError('Coupon not found.');
    }

    if (c['is_active'] != true) {
      throw StateError('Coupon is not active.');
    }
    final expiresAtStr = c['expires_at']?.toString();
    if (expiresAtStr != null && expiresAtStr.isNotEmpty) {
      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        throw StateError('Coupon has expired.');
      }
    }

    await _sb.from('user_coupons').insert({
      'user_id': uid,
      'coupon_id': couponId, // text in your schema
    });
  }

  /// Optional: list the user’s claimed coupons with coupon row included.
  static Future<List<Map<String, dynamic>>> fetchMyClaimedCoupons() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return const [];

    final rows = await _sb
        .from('user_coupons')
        .select('coupon_id, claimed_at, coupons(*)')
        .eq('user_id', uid)
        .order('claimed_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>();
  }
}

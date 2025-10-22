// lib/services/voucher_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/coupon.dart';

class VoucherService {
  final SupabaseClient _sb = Supabase.instance.client;

  Future<List<Coupon>> fetchMyClaimedCoupons() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw 'User not authenticated';
    }

    final rows = await _sb
        .from('user_coupons')
        .select('''
          id,
          claimed_at,
          used_at,
          coupons:coupon_id(
            id,
            title,
            description,
            code,
            image_url,
            discount_type,
            discount_value,
            min_spend,
            expires_at,
            is_active
          )
        ''')
        .eq('user_id', uid)
        .order('claimed_at', ascending: false);

    final normalized = (rows as List)
        .map((uc) => {
      'user_coupons': {
        'id': uc['id'],
        'claimed_at': uc['claimed_at'],
        'used_at': uc['used_at'],
      },
      'coupons': uc['coupons'],
    })
        .toList();

    return normalized.map((r) => Coupon.fromJoinedRow(r)).toList();
  }

  Future<void> markUserCouponAsUsed(String userCouponId) async {
    await _sb
        .from('user_coupons')
        .update({'used_at': DateTime.now().toIso8601String()})
        .eq('id', userCouponId);
  }
}

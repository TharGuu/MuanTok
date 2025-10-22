// lib/models/coupon.dart
class Coupon {
  final String id;
  final String title;
  final String? description;
  final String? code;
  final String? imageUrl;
  final String discountType; // 'percent' or 'amount'
  final num discountValue;
  final num? minSpend;
  final DateTime? expiresAt;          // optional static expiry from coupons table
  final bool isActive;

  // From user_coupons
  final String userCouponId;          // row id in user_coupons
  final DateTime claimedAt;           // when user claimed
  final DateTime? usedAt;             // when user used

  const Coupon({
    required this.id,
    required this.title,
    this.description,
    this.code,
    this.imageUrl,
    required this.discountType,
    required this.discountValue,
    this.minSpend,
    this.expiresAt,
    required this.isActive,
    required this.userCouponId,
    required this.claimedAt,
    this.usedAt,
  });

  /// Auto-expire 1 month after claim if unused. If coupons.expires_at exists and is earlier,
  /// we respect the earlier date. So the effective expiry is the *earliest* of the two.
  DateTime get claimExpiry => claimedAt.add(const Duration(days: 30));
  DateTime? get effectiveExpiry {
    if (expiresAt == null) return claimExpiry;
    return expiresAt!.isBefore(claimExpiry) ? expiresAt : claimExpiry;
  }

  bool get isUsed => usedAt != null;

  bool get isExpired {
    if (isUsed) return false; // used is not "expired" in our UI status
    final eff = effectiveExpiry;
    return eff != null && DateTime.now().isAfter(eff);
  }

  bool get isAvailable => !isUsed && !isExpired && isActive;

  /// Build from the normalized row created in VoucherService.fetchMyClaimedCoupons()
  factory Coupon.fromJoinedRow(Map<String, dynamic> row) {
    final c = row['coupons'] as Map<String, dynamic>;
    final uc = row['user_coupons'] as Map<String, dynamic>;

    DateTime? _parseTs(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return Coupon(
      id: c['id'].toString(),
      title: (c['title'] ?? '').toString(),
      description: c['description']?.toString(),
      code: c['code']?.toString(),
      imageUrl: c['image_url']?.toString(),
      discountType: (c['discount_type'] ?? 'amount').toString(),
      discountValue: (c['discount_value'] is num)
          ? c['discount_value'] as num
          : num.tryParse(c['discount_value'].toString()) ?? 0,
      minSpend: (c['min_spend'] is num)
          ? c['min_spend'] as num
          : (c['min_spend'] != null ? num.tryParse(c['min_spend'].toString()) : null),
      expiresAt: _parseTs(c['expires_at']),
      isActive: (c['is_active'] as bool?) ?? true,
      userCouponId: uc['id'].toString(),
      claimedAt: _parseTs(uc['claimed_at']) ?? DateTime.now(),
      usedAt: _parseTs(uc['used_at']),
    );
  }
}

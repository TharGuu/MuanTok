// lib/services/card_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentCardLite {
  final int id;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final String holder;

  PaymentCardLite({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    required this.holder,
  });

  factory PaymentCardLite.fromMap(Map<String, dynamic> m) => PaymentCardLite(
    id: m['id'] is int ? m['id'] as int : int.parse('${m['id']}'),
    brand: (m['brand'] ?? '').toString(),
    last4: (m['last4'] ?? '').toString(),
    expMonth: m['exp_month'] is int
        ? m['exp_month'] as int
        : int.tryParse('${m['exp_month']}') ?? 0,
    expYear: m['exp_year'] is int
        ? m['exp_year'] as int
        : int.tryParse('${m['exp_year']}') ?? 0,
    holder: (m['holder'] ?? '').toString(),
  );
}

class CardService {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// List current user's cards (not soft-deleted).
  static Future<List<PaymentCardLite>> listMyCards() async {
    if (_sb.auth.currentUser == null) return [];
    final rows = await _sb
        .from('payment_cards')
        .select('id, brand, last4, exp_month, exp_year, holder, deleted_at')
        .order('created_at', ascending: false);

    final list = (rows as List).cast<Map<String, dynamic>>();
    final filtered = list.where((m) => m['deleted_at'] == null).toList();
    return filtered.map(PaymentCardLite.fromMap).toList();
  }

  /// Add a new card.
  /// `brand` is optional; we auto-detect from `number` if not provided.
  static Future<void> addCard({
    required String holder,
    String? brand,              // <- now optional
    required String number,     // PAN (spaces are fine)
    required int expMonth,
    required int expYear,
  }) async {
    if (_sb.auth.currentUser == null) {
      throw 'Not signed in';
    }

    final digits = number.replaceAll(RegExp(r'\s+'), '');
    if (digits.length < 12) throw 'Card number too short';
    final last4 = digits.substring(digits.length - 4);

    final normalizedBrand =
    (brand == null || brand.trim().isEmpty) ? _detectBrand(digits) : brand.toLowerCase();

    final payload = {
      'holder': holder,
      'brand': normalizedBrand,
      'last4': last4,
      'exp_month': expMonth,
      'exp_year': expYear,
      // If you don't have a trigger to set user_id, uncomment:
      // 'user_id': _sb.auth.currentUser!.id,
    };

    await _sb.from('payment_cards').insert(payload);
  }

  /// Hard delete (requires DELETE policy). If you use soft delete, swap to update deleted_at.
  static Future<void> deleteCard(int cardId) async {
    if (_sb.auth.currentUser == null) {
      throw 'Not signed in';
    }
    await _sb.from('payment_cards').delete().match({'id': cardId});

    // Soft delete alternative:
    // await _sb.from('payment_cards')
    //   .update({'deleted_at': DateTime.now().toIso8601String()})
    //   .match({'id': cardId});
  }

  /// Basic BIN pattern detection.
  static String _detectBrand(String digits) {
    // Order matters (more specific first)
    final d = digits;
    if (RegExp(r'^(34|37)\d{13}$').hasMatch(d)) return 'amex';
    if (RegExp(r'^(62|81)\d{14,17}$').hasMatch(d)) return 'unionpay';
    if (RegExp(r'^(6011|65|64[4-9])\d{12,15}$').hasMatch(d)) return 'discover';
    if (RegExp(r'^(352[8-9]|35[3-8]\d)\d{12}$').hasMatch(d)) return 'jcb';
    if (RegExp(r'^(30[0-5]|309|36|38|39)\d{12}$').hasMatch(d)) return 'diners';
    if (RegExp(r'^(5[1-5]\d{14}|2(2[2-9]\d{12}|[3-6]\d{13}|7[01]\d{12}|720\d{12}))$').hasMatch(d)) {
      return 'mastercard';
    }
    if (RegExp(r'^4\d{12}(\d{3})?(\d{3})?$').hasMatch(d)) return 'visa';
    return 'card';
  }
}

// lib/services/card_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

final _sb = Supabase.instance.client;

/// Lightweight card model (demo only — use processor tokens in production).
class PaymentCardLite {
  final int id;
  final String brand;
  final String last4;
  final String holder;
  final int expMonth;
  final int expYear;

  PaymentCardLite({
    required this.id,
    required this.brand,
    required this.last4,
    required this.holder,
    required this.expMonth,
    required this.expYear,
  });

  factory PaymentCardLite.fromMap(Map<String, dynamic> m) => PaymentCardLite(
    id: (m['id'] as num).toInt(),
    brand: (m['brand'] ?? 'Card').toString(),
    last4: (m['last4'] ?? '0000').toString(),
    holder: (m['holder'] ?? '').toString(),
    expMonth: (m['exp_month'] as num).toInt(),
    expYear: (m['exp_year'] as num).toInt(),
  );
}

class CardService {
  static String _requireUid() {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');
    return uid;
  }

  static Future<List<PaymentCardLite>> listMyCards() async {
    final uid = _requireUid();
    final rows = await _sb
        .from('payment_cards')
        .select('id, brand, last4, holder, exp_month, exp_year, deleted_at')
        .eq('user_id', uid)
        .isFilter('deleted_at', null)
        .order('id', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PaymentCardLite.fromMap)
        .toList();
  }

  static Future<PaymentCardLite> addCard({
    required String holder,
    required String number, // DEMO ONLY
    required int expMonth,
    required int expYear,
  }) async {
    final uid = _requireUid();

    String brandOf(String n) {
      if (n.startsWith('4')) return 'Visa';
      if (RegExp(r'^(5[1-5])').hasMatch(n)) return 'Mastercard';
      if (RegExp(r'^(34|37)').hasMatch(n)) return 'Amex';
      return 'Card';
    }

    final sanitized = number.replaceAll(RegExp(r'[\s-]'), '');
    final last4 = sanitized.length >= 4 ? sanitized.substring(sanitized.length - 4) : '0000';

    final inserted = await _sb.from('payment_cards').insert({
      'user_id': uid,
      'brand': brandOf(sanitized),
      'last4': last4,
      'holder': holder,
      'exp_month': expMonth,
      'exp_year': expYear,
    }).select('id, brand, last4, holder, exp_month, exp_year').single();

    return PaymentCardLite.fromMap(inserted as Map<String, dynamic>);
  }

  static Future<void> deleteCard(int id) async {
    final uid = _requireUid();
    await _sb
        .from('payment_cards')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id)
        .eq('user_id', uid);
  }
}

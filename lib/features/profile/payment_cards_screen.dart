// lib/features/profile/payment_cards_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/card_service.dart'; // exposes PaymentCardLite, CardService

const _kPrimary  = Color(0xFF7C3AED); // Lucid purple
const _kPrimary2 = Color(0xFF9B8AFB);
const _kText     = Color(0xFF1F2937);
const _kMuted    = Color(0xFF6B7280);

BoxDecoration _glass([double r = 16]) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(r),
  border: Border.all(color: const Color(0x11000000)),
  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 6))],
);

class PaymentCardsScreen extends StatefulWidget {
  const PaymentCardsScreen({super.key});
  @override
  State<PaymentCardsScreen> createState() => _PaymentCardsScreenState();
}

class _PaymentCardsScreenState extends State<PaymentCardsScreen> {
  bool _loading = true;
  String? _error;
  List<PaymentCardLite> _cards = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _cards = await CardService.listMyCards(); // <-- typed
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _addCard() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const _AddCardScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _deleteCard(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove card?'),
        content: const Text('This card will no longer appear at checkout.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await CardService.deleteCard(id); // <-- int
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Card removed')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _kText,
        title: ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [_kPrimary, _kPrimary2]).createShader(r),
          child: const Text('Payment Cards', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCard,
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add card'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
          ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
          : _cards.isEmpty
          ? Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: _glass(),
          child: const Text('No cards yet. Tap “Add card”.', style: TextStyle(color: _kMuted)),
        ),
      )
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: _cards.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final card = _cards[i];
          return Dismissible(
            key: ValueKey('card_${card.id}'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) async {
              await _deleteCard(card.id); // <-- int id
              return false; // we refresh inside
            },
            background: Container(
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 18),
              child: Icon(Icons.delete_outline, color: Colors.red.shade400),
            ),
            child: Container(
              decoration: _glass(),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _BrandBadge(brand: card.brand ?? 'Card'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${card.brand ?? 'Card'}  •••• ${card.last4 ?? '••••'}',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: _kText),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (card.holder ?? '').isEmpty ? '—' : (card.holder ?? ''),
                          style: const TextStyle(color: _kMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _kPrimary.withOpacity(.3)),
                      color: _kPrimary.withOpacity(.06),
                    ),
                    child: Text(
                      '${(card.expMonth ?? 0).toString().padLeft(2, '0')}/${(card.expYear ?? 0) % 100}',
                      style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  final String brand;
  const _BrandBadge({required this.brand});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_kPrimary, _kPrimary2]),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 6))],
      ),
      child: const Icon(Icons.credit_card, color: Colors.white),
    );
  }
}

/* ---------------------------- Add Card Screen ---------------------------- */

class _AddCardScreen extends StatefulWidget {
  const _AddCardScreen();

  @override
  State<_AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<_AddCardScreen> {
  final _form = GlobalKey<FormState>();
  final _holder = TextEditingController();
  final _number = TextEditingController();
  final _expMonth = TextEditingController();
  final _expYear = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _holder.dispose();
    _number.dispose();
    _expMonth.dispose();
    _expYear.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final month = int.parse(_expMonth.text);
      final year  = int.parse(_expYear.text);
      await CardService.addCard(
        number: _number.text.replaceAll(RegExp(r'\s+'), ''),
        holder: _holder.text.trim(),
        expMonth: month,
        expYear: year,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Card added')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _kText,
        title: ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [_kPrimary, _kPrimary2]).createShader(r),
          child: const Text('Add card', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            decoration: _glass(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Pretty placeholder card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_kPrimary, _kPrimary2]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.credit_card, color: Colors.white),
                      const SizedBox(height: 10),
                      Text(
                        _number.text.isEmpty ? '••••  ••••  ••••  ••••' : _number.text,
                        style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _holder.text.isEmpty ? 'NAME SURNAME' : _holder.text.toUpperCase(),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          Text(
                            (_expMonth.text.isEmpty || _expYear.text.isEmpty)
                                ? 'MM/YY'
                                : '${_expMonth.text.padLeft(2,'0')}/${(_expYear.text.length > 2 ? _expYear.text.substring(_expYear.text.length-2) : _expYear.text)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Form(
                  key: _form,
                  child: Column(
                    children: [
                      _Input(
                        controller: _holder,
                        label: 'Card holder name',
                        onChanged: (_) => setState(() {}),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      _Input(
                        controller: _number,
                        label: 'Card number',
                        keyboardType: TextInputType.number,
                        onChanged: (s) {
                          // simple grouping
                          final t = s.replaceAll(' ', '');
                          final grouped = t.replaceAllMapped(RegExp(r'.{1,4}'), (m) => '${m.group(0)} ').trimRight();
                          if (grouped != _number.text) {
                            final pos = grouped.length;
                            _number.value = TextEditingValue(text: grouped, selection: TextSelection.collapsed(offset: pos));
                          } else {
                            setState(() {});
                          }
                        },
                        validator: (v) {
                          final t = (v ?? '').replaceAll(' ', '');
                          if (t.length < 12 || t.length > 19) return 'Enter a valid card number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _Input(
                              controller: _expMonth,
                              label: 'Exp. month',
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                final n = int.tryParse(v ?? '');
                                if (n == null || n < 1 || n > 12) return '1–12';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _Input(
                              controller: _expYear,
                              label: 'Exp. year',
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                final n = int.tryParse(v ?? '');
                                if (n == null || n < DateTime.now().year) return 'YYYY';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Saving...' : 'Save card'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ----------------------------- Small input ----------------------------- */

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const _Input({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF2ECFF),
        labelStyle: const TextStyle(color: _kMuted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x229B8AFB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPrimary),
        ),
      ),
    );
  }
}

// lib/features/profile/voucher_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/coupon.dart';
import '../../services/voucher_service.dart';

enum VoucherTab { available, usedExpired }

class VoucherScreen extends StatefulWidget {
  final VoucherTab initialTab;
  const VoucherScreen({super.key, this.initialTab = VoucherTab.available});

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen>
    with SingleTickerProviderStateMixin {
  final VoucherService _voucherService = VoucherService();
  final _sb = Supabase.instance.client;

  late Future<List<Coupon>> _future;
  late TabController _tabController;

  Color get primaryPurple => const Color(0xFF673ab7);

  @override
  void initState() {
    super.initState();
    _future = _voucherService.fetchMyClaimedCoupons();
    _tabController =
        TabController(length: 2, vsync: this, initialIndex: widget.initialTab.index);
  }

  Future<void> _refresh() async {
    setState(() => _future = _voucherService.fetchMyClaimedCoupons());
  }

  @override
  Widget build(BuildContext context) {
    final _ = _sb.auth.currentUser != null; // isSelf not used but could be

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Coupons',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: primaryPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: primaryPurple,
          tabs: const [
            Tab(text: 'Available'),
            Tab(text: 'Used / Expired'),
          ],
        ),
      ),
      body: FutureBuilder<List<Coupon>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(primaryPurple)),
            );
          }
          if (snap.hasError) {
            return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error: ${snap.error}', textAlign: TextAlign.center),
                ));
          }
          final items = snap.data ?? [];
          final available = items.where((c) => c.isAvailable).toList();
          final usedExpired = items.where((c) => !c.isAvailable).toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            color: primaryPurple,
            child: TabBarView(
              controller: _tabController,
              children: [
                _VoucherList(
                  vouchers: available,
                  emptyText: 'No available coupons yet.',
                  primaryPurple: primaryPurple,
                  showApply: true,
                ),
                _VoucherList(
                  vouchers: usedExpired,
                  emptyText: 'No used or expired coupons.',
                  primaryPurple: primaryPurple,
                  showApply: false,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VoucherList extends StatelessWidget {
  final List<Coupon> vouchers;
  final String emptyText;
  final Color primaryPurple;
  final bool showApply;

  const _VoucherList({
    required this.vouchers,
    required this.emptyText,
    required this.primaryPurple,
    required this.showApply,
  });

  String _fmt(DateTime dt) => dt.toLocal().toString().split('.').first;

  @override
  Widget build(BuildContext context) {
    if (vouchers.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Text(emptyText, style: const TextStyle(color: Colors.grey))),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: vouchers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final c = vouchers[i];
        final expiry = c.effectiveExpiry;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: c.imageUrl != null && c.imageUrl!.isNotEmpty
                  ? Image.network(c.imageUrl!, width: 56, height: 56, fit: BoxFit.cover)
                  : Container(
                width: 56,
                height: 56,
                color: Colors.grey.shade200,
                child: const Icon(Icons.card_giftcard, color: Colors.black54),
              ),
            ),
            title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.description != null && c.description!.isNotEmpty)
                  Text(c.description!, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (c.code != null && c.code!.isNotEmpty) _Chip(text: 'Code: ${c.code!}'),
                    _Chip(text: c.discountType == 'percent' ? '−${c.discountValue}%' : '−${c.discountValue}'),
                    if (c.minSpend != null) _Chip(text: 'Min spend: ${c.minSpend}'),
                    _Chip(text: 'Claimed: ${_fmt(c.claimedAt)}'),
                    _Chip(text: expiry != null ? 'Expires: ${_fmt(expiry)}' : 'No expiry'),
                  ],
                ),
                const SizedBox(height: 6),
                if (!c.isAvailable)
                  Text(
                    c.isUsed ? 'Used on: ${_fmt(c.usedAt!)}' : 'Expired',
                    style: TextStyle(
                        color: c.isUsed ? Colors.blueGrey : Colors.red.shade400,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            isThreeLine: true,
            trailing: showApply
                ? ElevatedButton(
              onPressed: () => Navigator.pop(context, c),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPurple,
                minimumSize: const Size(82, 40),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Use'),
            )
                : null,
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

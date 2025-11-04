// lib/features/profile/voucher_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/voucher_service.dart';

/* ------------------------------ Lucid Theme ------------------------------ */

const kPrimary = Color(0xFF7C3AED); // Purple core
const kPrimary2 = Color(0xFF9B8AFB);
const kPrimaryLiteA = Color(0xFFF2ECFF);
const kPrimaryLiteB = Color(0xFFEDE7FF);
const kText = Color(0xFF1F2937);
const kMuted = Color(0xFF6B7280);
const kBgTop = Color(0xFFF8F5FF);
const kBgBottom = Color(0xFFFDFBFF);
const kGlass = Color(0xFFFFFFFF);

BoxDecoration glassCard([double radius = 16]) => BoxDecoration(
  color: kGlass.withOpacity(.92),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: const Color(0x11000000)),
  boxShadow: const [
    BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 6)),
  ],
);

TextStyle sectionTitle(BuildContext c) =>
    Theme.of(c).textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: .2,
      color: kText,
    );

/* ------------------------------------------------------------------------ */

enum VoucherTab { available, claimed }

class VoucherScreen extends StatefulWidget {
  final VoucherTab initialTab;
  const VoucherScreen({super.key, this.initialTab = VoucherTab.available});

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  late int _initialIndex;

  @override
  void initState() {
    super.initState();
    _initialIndex = widget.initialTab == VoucherTab.available ? 0 : 1;
  }

  @override
  Widget build(BuildContext context) {
<<<<<<< HEAD
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kBgTop, kBgBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
=======
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
>>>>>>> a47fc57d44d340f0ace8e6089c81a288485841a8
        ),
      ),
      child: DefaultTabController(
        length: 2,
        initialIndex: _initialIndex,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            elevation: 0,
            centerTitle: true,
            backgroundColor: Colors.transparent,
            foregroundColor: kText,
            title: ShaderMask(
              shaderCallback: (r) =>
                  const LinearGradient(colors: [kPrimary, kPrimary2]).createShader(r),
              child: const Text('Coupons',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _PillTabBar(
                  tabs: const [Text('Available'), Text('My coupons')],
                ),
              ),
            ),
          ),
          body: const TabBarView(
            physics: BouncingScrollPhysics(),
            children: [
              _AvailableCouponsTab(),
              _MyCouponsTab(),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------------------- Pretty pill TabBar --------------------------- */

class _PillTabBar extends StatelessWidget {
  final List<Widget> tabs;
  const _PillTabBar({required this.tabs});

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0x11000000)),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10)],
      ),
      child: TabBar(
        controller: controller,
        tabs: tabs,
        labelPadding: const EdgeInsets.symmetric(horizontal: 0),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: kPrimary.withOpacity(.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: kPrimary),
        ),
        labelColor: kPrimary,
        unselectedLabelColor: kText,
        splashBorderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

/* -------------------------- Available coupons tab -------------------------- */

class _AvailableCouponsTab extends StatefulWidget {
  const _AvailableCouponsTab();

  @override
  State<_AvailableCouponsTab> createState() => _AvailableCouponsTabState();
}

class _AvailableCouponsTabState extends State<_AvailableCouponsTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = VoucherService.fetchActiveCoupons(excludeAlreadyClaimed: true);
  }

  Future<void> _reload() async {
    setState(() {
      _future = VoucherService.fetchActiveCoupons(excludeAlreadyClaimed: true);
    });
  }

  String _subtitle(Map<String, dynamic> c) {
    final type = (c['discount_type'] ?? '').toString();
    final val = c['discount_value'];
    final code = (c['code'] ?? '').toString();
    final expires = (c['expires_at'] ?? '').toString();

    final typeTxt = type == 'percent'
        ? 'Save $val%'
        : type == 'amount'
        ? 'Save ฿$val'
        : 'Coupon';

    return [
      if (code.isNotEmpty) 'Code: $code',
      typeTxt,
      if (expires.isNotEmpty) 'Ends: $expires',
    ].join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      color: kPrimary,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: kPrimary));
          }
          if (snap.hasError) {
            return ListView(
              children: [
<<<<<<< HEAD
                const SizedBox(height: 24),
                _ErrorBox('Failed to load coupons: ${snap.error}'),
              ],
            );
          }

          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 48),
                _EmptyState(
                  title: 'No coupons available',
                  caption: 'Please check back later.',
=======
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
>>>>>>> a47fc57d44d340f0ace8e6089c81a288485841a8
                ),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final c = items[i];
              return _CouponCard(
                colorA: kPrimaryLiteA,
                colorB: kPrimaryLiteB,
                borderColor: kPrimary.withOpacity(.25),
                title: (c['title'] ?? 'Coupon').toString(),
                subtitle: _subtitle(c),
                actionText: 'Claim',
                onPressed: () async {
                  try {
                    final idAny = c['id'];
                    if (idAny == null) throw StateError('Invalid coupon id');
                    final id = int.tryParse(idAny.toString());
                    if (id == null) throw StateError('Invalid coupon id');

                    await VoucherService.claimCoupon(id);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Coupon claimed!')),
                    );
                    await _reload();
                  } on PostgrestException catch (e) {
                    if (!mounted) return;
                    final msg = (e.code == '23505')
                        ? 'Already claimed.'
                        : (e.code == '42501')
                        ? 'Permission denied.'
                        : 'Cannot claim coupon.';
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

/* ---------------------------- My coupons tab ---------------------------- */

class _MyCouponsTab extends StatefulWidget {
  const _MyCouponsTab();

  @override
  State<_MyCouponsTab> createState() => _MyCouponsTabState();
}

class _MyCouponsTabState extends State<_MyCouponsTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = VoucherService.fetchMyClaimedCoupons();
  }

  Future<void> _reload() async {
    setState(() => _future = VoucherService.fetchMyClaimedCoupons());
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      color: kPrimary,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: kPrimary));
          }
          if (snap.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 24),
                _ErrorBox('Failed to load your coupons: ${snap.error}'),
              ],
            );
          }

          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 48),
                _EmptyState(
                  title: 'No claimed coupons yet',
                  caption: 'Claim some from the Available tab.',
                ),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final row = items[i];
              final c = (row['coupons'] as Map?)?.cast<String, dynamic>() ?? {};
              final title = (c['title'] ?? 'Coupon').toString();
              final code = (c['code'] ?? '').toString();
              final expires = (c['expires_at'] ?? '').toString();
              final sub = [
                if (code.isNotEmpty) 'Code: $code',
                if (expires.isNotEmpty) 'Ends: $expires',
              ].join(' • ');

              return _CouponCard(
                colorA: Colors.white,
                colorB: Colors.white,
                borderColor: const Color(0x22000000),
                title: title,
                subtitle: sub.isEmpty ? 'Claimed coupon' : sub,
                actionText: 'Claimed',
                onPressed: null,
              );
            },
          );
        },
      ),
    );
  }
}

/* ------------------------------- UI pieces ------------------------------- */

class _CouponCard extends StatelessWidget {
  final Color colorA;
  final Color colorB;
  final Color borderColor;
  final String title;
  final String subtitle;
  final String actionText;
  final VoidCallback? onPressed;

  const _CouponCard({
    required this.colorA,
    required this.colorB,
    required this.borderColor,
    required this.title,
    required this.subtitle,
    required this.actionText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [colorA, colorB]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kPrimary.withOpacity(.25)),
                ),
                child: const Icon(Icons.local_offer_rounded, color: kPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: kText,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kMuted, fontSize: 12, height: 1.25),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: onPressed == null ? Colors.white : Colors.black,
                  foregroundColor: onPressed == null ? kText : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: onPressed == null
                      ? const BorderSide(color: Color(0x22000000))
                      : BorderSide.none,
                  elevation: 0,
                ),
                child: Text(
                  actionText,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String caption;
  const _EmptyState({required this.title, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: glassCard(18),
        child: Column(
          children: [
            Icon(Icons.local_offer_outlined, size: 64, color: kPrimary.withOpacity(.35)),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900, color: kText)),
            const SizedBox(height: 6),
            Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: glassCard(16).copyWith(
          color: const Color(0xFFFFF5F7),
          border: Border.all(color: const Color(0x26E11D48)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFE11D48)),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: Color(0xFFE11D48)))),
          ],
        ),
      ),
    );
  }
}

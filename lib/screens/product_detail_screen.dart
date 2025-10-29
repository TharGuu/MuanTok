import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'promotion_screen.dart';
import 'event_products_screen.dart';
import '../services/supabase_service.dart';
import '../features/profile/voucher_screen.dart';
import 'favourite_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final int productId;
  final Map<String, dynamic>? initialData;

  const ProductDetailScreen({
    super.key,
    required this.productId,
    this.initialData,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {

  bool _isFavourite = false;
  bool _togglingFav = false;
  bool _loading = true;
  int? _favRowId;
  String? _error;

  Map<String, dynamic>? _bestDiscountEvent() {
    if (_events.isEmpty) return null;

    Map<String, dynamic>? best;
    int bestPct = -1;

    for (final ev in _events) {
      // Accept common keys for id/percent/name
      final int? id = (ev['id'] ?? ev['event_id']) is int
          ? (ev['id'] ?? ev['event_id']) as int
          : int.tryParse('${ev['id'] ?? ev['event_id'] ?? ''}');

      final int pct = (ev['discount_percent'] is num)
          ? (ev['discount_percent'] as num).toInt()
          : int.tryParse('${ev['discount_percent'] ?? 0}') ?? 0;

      if (id != null && pct > bestPct) {
        bestPct = pct;
        best = ev;
      }
    }

    // fall back to first event if all percents are invalid
    return best ?? _events.first;
  }


  Map<String, dynamic>? _product; // Product info
  List<Map<String, dynamic>> _events = []; // [{ event_name, discount_percent }]
  List<Map<String, dynamic>> _comments = []; // preview comments (limit 3)
  List<Map<String, dynamic>> _related = []; // related products same category

  // NEW: active banner image for this product's event (nullable)
  String? _activeEventBannerUrl;

  RealtimeChannel? _commentChannel;

  static const int _commentPreviewLimit = 3;

  // brand colors
  static const Color kPurple = Color(0xFFD8BEE5); // light purple accent
  static const Color kPurpleDark = Color(0xFF9C6BCF); // darker fill purple
  static const Color kBorderGrey = Color(0xFFDDDDDD); // subtle border
  static const Color kTextDark = Colors.black;
  static final Color kTextLight = Colors.grey.shade600;
  static final Color kCardBg = Colors.white;
  static final Color kSubtleBg = Colors.grey.shade100;

  @override
  void initState() {
    super.initState();

    _product = widget.initialData;

    _subscribeToComments();
    _initLoadAfterBuild();
  }

  @override
  void dispose() {
    _commentChannel?.unsubscribe();
    super.dispose();
  }

  // ensure we fetch AFTER first frame so auth/realtime is stable
  void _initLoadAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _fetchAll();            // product, events, comments
      await _refreshCommentsOnly(); // force sync preview comments
      await _fetchRelated();        // pull related items
      await _fetchActiveEventBanner(); // pull active banner
      await _checkFav();            //
      await _loadFavouriteStatus();

    });
  }

  /* -------------------------------------------------------------------------- */
  /*                                DATA FETCHERS                               */
  /* -------------------------------------------------------------------------- */

  // Fetch product, events, and preview comments
  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final freshProduct =
      await SupabaseService.fetchProductDetail(widget.productId);

      final evs =
      await SupabaseService.fetchProductEvents(widget.productId);

      final cmts =
      await SupabaseService.fetchProductCommentsLimited(
        widget.productId,
        limit: _commentPreviewLimit,
      );

      if (!mounted) return;
      setState(() {
        _product = freshProduct;
        _events = evs;
        _comments = cmts;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // Refresh only preview comment list (latest 3)
  Future<void> _refreshCommentsOnly() async {
    try {
      final cmts =
      await SupabaseService.fetchProductCommentsLimited(
        widget.productId,
        limit: _commentPreviewLimit,
      );
      if (!mounted) return;
      setState(() {
        _comments = cmts;
      });
    } catch (_) {
      // ignore
    }
  }



  // RELATED PRODUCTS
  Future<void> _fetchRelated() async {
    // We can only fetch related after we know product + category.
    final prod = _product;
    if (prod == null) return;

    final category = (prod['category'] ?? '').toString();
    if (category.isEmpty) return;

    try {
      // get up to ~10 products in same category, newest first
      final sameCatList = await SupabaseService.listProducts(
        category: category,
        limit: 10,
        offset: 0,
        orderBy: 'id',
        ascending: false,
      );

      // filter out THIS product id so it's not shown as related to itself
      final filtered = sameCatList.where((p) {
        final pid = p['id'];
        return pid is int && pid != widget.productId;
      }).toList();

      if (!mounted) return;
      setState(() {
        _related = filtered;
      });
    } catch (e) {
      // optional UI -> ignore error
    }
  }



  // NEW: get banner for active event of this product
  Future<void> _fetchActiveEventBanner() async {
    try {
      // Assuming the event name is available in the _events list
      final eventName = _events.isNotEmpty ? _events.first['event_name'] : null;

      if (eventName == 'Christmas Sale') {
        setState(() {
          _activeEventBannerUrl = 'assets/banners/christmas_sale.png'; // Path for Christmas Sale banner
        });
      } else if (eventName == 'Promotion') {
        setState(() {
          _activeEventBannerUrl = 'assets/banners/promotion.png'; // Path for Promotion banner
        });
      } else {
        setState(() {
          _activeEventBannerUrl = null;  // No banner for other events
        });
      }
    } catch (e) {
      // Ignore silently, banner is optional
    }
  }

  //favourite
  Future<void> _checkFav() async {
    try {
      final fav = await SupabaseService.isFavourited(productId: widget.productId);
      if (mounted) setState(() => _isFavourite = fav);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadFavouriteStatus() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final row = await sb
          .from('favourites')
          .select('id')
          .eq('user_id', uid)
          .eq('product_id', widget.productId)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _isFavourite = row != null;
        _favRowId = row?['id'] as int?;
      });
    } catch (_) {
      // leave defaults on error
    }
  }

  Future<void> _toggleFavWithConfirm() async {
    if (_togglingFav) return;

    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in first')),
      );
      return;
    }

    final adding = !_isFavourite;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(adding ? 'Add to favourites' : 'Remove from favourites'),
        content: Text(adding
            ? 'Do you want to add this product to your favourites?'
            : 'Do you want to remove this product from your favourites?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _togglingFav = true);
    try {
      if (adding) {
        final inserted = await sb
            .from('favourites')
            .insert({'user_id': uid, 'product_id': widget.productId})
            .select('id')
            .single();

        if (!mounted) return;
        setState(() {
          _isFavourite = true;
          _favRowId = inserted['id'] as int?;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to favourites')),
        );
      } else {
        await sb
            .from('favourites')
            .delete()
            .eq('user_id', uid)
            .eq('product_id', widget.productId);

        if (!mounted) return;
        setState(() {
          _isFavourite = false;
          _favRowId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from favourites')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _togglingFav = false);
    }
  }






  /* -------------------------------------------------------------------------- */
  /*                           REALTIME COMMENT UPDATES                          */
  /* -------------------------------------------------------------------------- */

  void _subscribeToComments() {
    final sb = Supabase.instance.client;

    _commentChannel?.unsubscribe();

    _commentChannel = sb.channel('product_comments_${widget.productId}')
    // INSERT
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'product_comment',
        callback: (payload) async {
          final row = payload.newRecord;
          final pid = row['product_id'];
          if (pid == widget.productId) {
            await _refreshCommentsOnly();
          }
        },
      )
    // UPDATE
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'product_comment',
        callback: (payload) async {
          final row = payload.newRecord;
          final pid = row['product_id'];
          if (pid == widget.productId) {
            await _refreshCommentsOnly();
          }
        },
      )
    // DELETE
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'product_comment',
        callback: (payload) async {
          final row = payload.oldRecord;
          final pid = row['product_id'];
          if (pid == widget.productId) {
            await _refreshCommentsOnly();
          }
        },
      )
      ..subscribe();

    // force-fill preview right away
    _refreshCommentsOnly();
  }








  /* -------------------------------------------------------------------------- */
  /*                        EDIT / DELETE EXISTING COMMENTS                     */
  /* -------------------------------------------------------------------------- */

  void _editCommentDialog(Map<String, dynamic> commentRow) {
    final TextEditingController editCtrl =
    TextEditingController(text: commentRow['content'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Edit comment',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: kTextDark,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: editCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: kSubtleBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: kBorderGrey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kTextDark,
                        side: BorderSide(color: kBorderGrey),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPurpleDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final newTxt = editCtrl.text.trim();
                        if (newTxt.isEmpty) return;
                        try {
                          await SupabaseService.editProductComment(
                            commentId: commentRow['id'] as int,
                            content: newTxt,
                          );

                          if (mounted) Navigator.pop(ctx);

                          await _refreshCommentsOnly();
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Update failed: $e")),
                          );
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteComment(int commentId) async {
    try {
      await SupabaseService.deleteProductComment(commentId);
      await _refreshCommentsOnly();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Delete failed: $e")),
      );
    }
  }

  /* -------------------------------------------------------------------------- */
  /*                             OPEN VIEW ALL SHEET                             */
  /* -------------------------------------------------------------------------- */

  void _openAllCommentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return _CommentsSheet(
          productId: widget.productId,
          purpleColor: kPurple,
          purpleDark: kPurpleDark,
          borderGrey: kBorderGrey,
          subtleBg: kSubtleBg,
          textDark: kTextDark,
          textLight: kTextLight,
          onRequestEditComment: (row) async {
            _editCommentDialog(row);
          },
          onRequestDeleteComment: (commentId) async {
            await _deleteComment(commentId);
          },
        );
      },
    ).whenComplete(() async {
      // sync preview 3 after sheet closes
      await _refreshCommentsOnly();
    });
  }

  /* -------------------------------------------------------------------------- */
  /*                        RELATED PRODUCTS (UI helpers)                       */
  /* -------------------------------------------------------------------------- */

  String _fmtBaht(num value) {
    final s = value.toStringAsFixed(2);
    return s.endsWith('00') ? value.toStringAsFixed(0) : s;
  }

  num _parseNum(dynamic v) {
    if (v is num) return v;
    if (v is String) {
      final d = num.tryParse(v);
      if (d != null) return d;
    }
    return 0;
  }

  List<String> _imgList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (v is String && v.isNotEmpty) {
      return [v];
    }
    return const [];
  }

  Widget _relatedSection() {
    if (_related.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Things you might be interested in',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: kTextDark,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 240, // card height
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: _related.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final data = _related[i];
              return _RelatedProductCard(
                data: data,
                purple: kPurple,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(
                        productId: data['id'] as int,
                        initialData: data,
                      ),
                    ),
                  );
                },
                fmtBaht: _fmtBaht,
                parseNum: _parseNum,
              );
            },
          ),
        ),
      ],
    );
  }

  /* -------------------------------------------------------------------------- */
  /*                                  HELPERS                                   */
  /* -------------------------------------------------------------------------- */

  Widget _buildStars(num rating, {double size = 16}) {
    final r = rating.toDouble().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < r.floor()
              ? Icons.star_rounded
              : (i < r
              ? Icons.star_half_rounded
              : Icons.star_border_rounded),
          size: size,
          color: Colors.amber.shade600,
        );
      }),
    );
  }

  String _fmt(num value) {
    final s = value.toStringAsFixed(2);
    return s.endsWith('00') ? value.toStringAsFixed(0) : s;
  }

  num _readNumField(dynamic v) {
    if (v is num) return v;
    if (v is String) {
      final parsed = num.tryParse(v);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  /* -------------------------------------------------------------------------- */
  /*                                   BUILD                                    */
  /* -------------------------------------------------------------------------- */

  @override
  Widget build(BuildContext context) {
    final p = _product;

    final loadingOverlay =
    _loading ? const LinearProgressIndicator(minHeight: 2) : const SizedBox.shrink();

    // If product failed to load
    if (p == null && _error != null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: kCardBg,
          foregroundColor: kTextDark,
          title: const Text('Product'),
          elevation: 0.5,
          actions: [
            IconButton(
              onPressed: _togglingFav ? null : _toggleFavWithConfirm,
              icon: Icon(
                _isFavourite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: _isFavourite ? Colors.red : kPurple,
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: Icon(
                Icons.shopping_cart_outlined,
                color: kPurple,
              ),
            ),
          ],
        ),
        backgroundColor: kCardBg,
        body: Center(
          child: Text(
            'Error: $_error',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }





    // safe unwrap
    final name = (p?['name'] ?? '').toString();
    final desc = (p?['description'] ?? '').toString();
    final category = (p?['category'] ?? '').toString();
    final stock = p?['stock'];

    final dynamic _priceField = p?['price'];
    final num rawPrice = _priceField is num
        ? _priceField
        : (_priceField is String ? (num.tryParse(_priceField) ?? 0) : 0);

    final discountPct = int.tryParse('${p?['discount_percent'] ?? 0}') ?? 0;
    final hasDiscount = discountPct > 0;
    final discountedPrice =
    hasDiscount ? rawPrice * (100 - discountPct) / 100 : rawPrice;

    final num ratingVal = _readNumField(p?['rating']);
    final num ratingCount = _readNumField(p?['rating_count']);

    final sellerName = (p?['seller_name'] ??
        p?['seller_full_name'] ??
        p?['seller']?['full_name'] ??
        'Unknown seller')
        .toString();

    final images = _imgList(
      p?['image_urls'] ?? p?['imageurl'] ?? p?['image_url'],
    );

    return Scaffold(
      backgroundColor: kCardBg,
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 0.5,
        backgroundColor: kCardBg,
        foregroundColor: kTextDark,
        title: Text(
          name.isEmpty ? 'Product' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: kTextDark,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => FavouriteScreen()),
              );
            },
            icon: Icon(
              Icons.favorite_border_rounded,
              color: kPurple,
            ),
          ),
          IconButton(
            onPressed: () {
              // TODO: open cart
            },
            icon: Icon(
              Icons.shopping_cart_outlined,
              color: kPurple,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          loadingOverlay,
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _fetchAll();
                await _fetchRelated();
                await _fetchActiveEventBanner();
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  /* ---------------------- IMAGE GALLERY ---------------------- */
                  AspectRatio(
                    aspectRatio: 1,
                    child: PageView.builder(
                      itemCount: images.isEmpty ? 1 : images.length,
                      itemBuilder: (_, i) {
                        final url = images.isEmpty ? null : images[i];
                        return Container(
                          color: Colors.grey.shade200,
                          child: url == null
                              ? const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 48,
                              color: Colors.grey,
                            ),
                          )
                              : Image.network(
                            url,
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),



                  /* ------------------- CORE PRODUCT CARD ------------------- */
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                    decoration: BoxDecoration(
                      color: kCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorderGrey),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // NAME
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: kTextDark,
                              height: 1.2,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // CATEGORY (moved ABOVE price)
                        if (category.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.category_rounded,
                                  size: 20,
                                  color: kTextDark,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Category: $category',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                      color: kTextDark,
                                      height: 1.3,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 8),

                        // PRICE / DISCOUNT (now after category)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: hasDiscount
                              ? Row(
                            crossAxisAlignment:
                            CrossAxisAlignment.center,
                            children: [
                              Text(
                                '฿ ${_fmt(discountedPrice)}',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '฿ ${_fmt(rawPrice)}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  decoration:
                                  TextDecoration.lineThrough,
                                  decorationThickness: 2,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  borderRadius:
                                  BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '-$discountPct%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          )
                              : Text(
                            '฿ ${_fmt(rawPrice)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              color: kTextDark,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // RATING + STOCK
                        Padding(
                          padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _buildStars(ratingVal, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                ratingVal.toStringAsFixed(1),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: kTextDark,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '(${ratingCount.toString()})',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Stock: ${stock ?? '-'}',
                                style: TextStyle(
                                  color: kTextDark,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),
                        Divider(height: 1, color: kBorderGrey),

                        // SELLER
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.storefront_rounded,
                                size: 20,
                                color: kTextDark,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  sellerName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: kTextDark,
                                    height: 1.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  // TODO: open seller shop screen
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: kPurple,
                                ),
                                child: Text(
                                  'View shop',
                                  style: TextStyle(
                                    color: kPurple,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),


                  // Active Event Banner Section
// ------------------- ACTIVE EVENT BANNER SECTION -------------------
                  if (_activeEventBannerUrl != null)
                    GestureDetector(
                      onTap: () {
                        final chosen = _bestDiscountEvent();
                        if (chosen == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No event found for this product.')),
                          );
                          return;
                        }

                        final int? eventId = (chosen['id'] ?? chosen['event_id']) is int
                            ? (chosen['id'] ?? chosen['event_id']) as int
                            : int.tryParse('${chosen['id'] ?? chosen['event_id'] ?? ''}');
                        final String eventName = (chosen['event_name'] ?? 'Event').toString();

                        if (eventId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invalid event id.')),
                          );
                          return;
                        }

                        // 👉 Use PromotionScreen (your shop uses this for events)
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PromotionScreen(eventId: eventId, eventName: eventName),
                          ),
                        );

                        // If you prefer the products-only list screen instead, swap to:
                        // Navigator.push(
                        //   context,
                        //   MaterialPageRoute(builder: (_) => EventProductsScreen(eventId: eventId)),
                        // );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: kCardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorderGrey),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AspectRatio(
                          aspectRatio: 16 / 6,
                          child: Image.asset(
                            _activeEventBannerUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) {
                              return Container(
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Colors.grey.shade500,
                                  size: 36,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),



                  /* ------------------- DESCRIPTION CARD ------------------- */
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    decoration: BoxDecoration(
                      color: kCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorderGrey),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Description',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: kTextDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          desc.isEmpty ? 'No description' : desc,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: kTextDark,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  /* --------------------- COMMENTS PREVIEW CARD -------------------- */
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    decoration: BoxDecoration(
                      color: kCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorderGrey),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // header row: "Comments" + view all
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Comments',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: kTextDark,
                                ),
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _openAllCommentsSheet,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kTextDark,
                                side: BorderSide(
                                  color: kBorderGrey,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'View all',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        Text(
                          _comments.isEmpty
                              ? 'No comments yet'
                              : 'Latest ${_comments.length} comments',
                          style: TextStyle(
                            color: kTextLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        const SizedBox(height: 12),

                        if (_comments.isEmpty)
                          Text(
                            'Be the first to comment (open View all).',
                            style: TextStyle(
                              color: kTextLight,
                              fontSize: 13,
                            ),
                          )
                        else
                          Column(
                            children: _comments.map((c) {
                              final cmtId = c['id'] as int?;
                              final authorName =
                              (c['author_name'] ?? 'User').toString();
                              final content = (c['content'] ?? '').toString();
                              final createdAt =
                              (c['created_at'] ?? '').toString();
                              final mine = c['is_mine'] == true;

                              return _CommentTile(
                                authorName: authorName,
                                content: content,
                                createdAt: createdAt,
                                canEdit: mine,
                                purple: kPurple,
                                borderGrey: kBorderGrey,
                                subtleBg: kSubtleBg,
                                textDark: kTextDark,
                                textLight: kTextLight,
                                onEdit: mine && cmtId != null
                                    ? () => _editCommentDialog(c)
                                    : null,
                                onDelete: mine && cmtId != null
                                    ? () => _deleteComment(cmtId)
                                    : null,
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),

                  // RELATED SECTION
                  _relatedSection(),

                  const SizedBox(height: 80), // space above bottom bar
                ],
              ),
            ),
          ),

          /* ------------------ BOTTOM ACTION BAR ------------------ */
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: kCardBg,
                border: Border(
                  top: BorderSide(
                    color: kBorderGrey,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // favourite button
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: kBorderGrey),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: _togglingFav ? null : _toggleFavWithConfirm,
                      icon: Icon(
                        _isFavourite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: _isFavourite ? Colors.red : kPurple,
                      ),
                      tooltip: _isFavourite ? 'Remove from favourites' : 'Add to favourites',
                    ),
                  ),

                  const SizedBox(width: 12),

                  // add to cart
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kTextDark,
                        side: BorderSide(color: kBorderGrey),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        // TODO: add to cart logic
                      },
                      child: const Text(
                        'Add to cart',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // buy now
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPurpleDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        // TODO: checkout logic
                      },
                      child: const Text(
                        'Buy now',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------- EVENT DEAL BANNER WIDGET -------------------- */

class _EventDealBanner extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  final VoidCallback onBannerTap;
  final Color purple;
  final Color purpleDark;

  const _EventDealBanner({
    required this.events,
    required this.onBannerTap,
    required this.purple,
    required this.purpleDark,
  });

  @override
  Widget build(BuildContext context) {
    // Find the best discount event
    int bestPct = 0;
    String bannerUrl = '';
    String eventName = '';

    for (final ev in events) {
      final pctRaw = ev['discount_percent'];
      final pct = pctRaw is num ? pctRaw.toInt() : int.tryParse(pctRaw?.toString() ?? '0') ?? 0;
      if (pct > bestPct) {
        bestPct = pct;
        eventName = ev['event_name'] ?? 'Event';
        bannerUrl = ev['banner_image_url'] ?? '';
      }
    }

    return bannerUrl.isNotEmpty
        ? GestureDetector(
      onTap: onBannerTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: purpleDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.network(bannerUrl), // Display banner image
            const SizedBox(height: 8),
            Text(
              '$eventName - up to -$bestPct%',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onBannerTap,
              child: const Text(
                'View available coupons',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    )
        : const SizedBox.shrink(); // Don't show anything if no banner URL
  }
}





/* ---------------------- RELATED PRODUCT CARD ---------------------- */

class _RelatedProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color purple;
  final VoidCallback onTap;
  final String Function(num) fmtBaht;
  final num Function(dynamic) parseNum;

  const _RelatedProductCard({
    required this.data,
    required this.purple,
    required this.onTap,
    required this.fmtBaht,
    required this.parseNum,
  });

  List<String> _extractImageUrls(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (v is String) {
      return [v];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final urls = _extractImageUrls(
      data['image_urls'] ??
          data['imageurl'] ??
          data['image_url'],
    );
    final img = urls.isNotEmpty ? urls.first : null;

    final name = (data['name'] ?? '').toString();
    final category = (data['category'] ?? '').toString();

    final priceRaw = parseNum(data['price']);
    final isEvent = (data['is_event'] == true);
    final discountPercent = data['discount_percent'] is int
        ? data['discount_percent'] as int
        : int.tryParse(
      '${data['discount_percent'] ?? 0}',
    ) ??
        0;

    final bool hasDiscount =
        isEvent && discountPercent > 0 && priceRaw > 0;
    final num discounted = hasDiscount
        ? (priceRaw * (100 - discountPercent)) / 100
        : priceRaw;

    final sellerMap = data['seller'] is Map
        ? data['seller'] as Map<String, dynamic>
        : null;
    final sellerNameFromRow = (sellerMap?['full_name'] ??
        data['seller_full_name'] ??
        data['seller_name'] ??
        'Unknown Seller')
        .toString();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
          BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade300,
          ),
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius:
                      const BorderRadius.only(
                        topLeft:
                        Radius.circular(
                            12),
                        topRight:
                        Radius.circular(
                            12),
                      ),
                      child: img == null
                          ? Container(
                        color: Colors
                            .grey
                            .shade200,
                        child:
                        const Icon(
                          Icons.image_not_supported_outlined,
                          color:
                          Colors.grey,
                        ),
                      )
                          : Image.network(
                        img,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  if (category.isNotEmpty)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding:
                        const EdgeInsets
                            .symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration:
                        BoxDecoration(
                          color: Colors
                              .black
                              .withOpacity(
                              0.7),
                          borderRadius:
                          BorderRadius
                              .circular(
                              8),
                        ),
                        child: Text(
                          category,
                          style:
                          const TextStyle(
                            color: Colors
                                .white,
                            fontSize:
                            10,
                            fontWeight:
                            FontWeight
                                .w600,
                            height:
                            1.0,
                          ),
                        ),
                      ),
                    ),
                  if (hasDiscount)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding:
                        const EdgeInsets
                            .symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration:
                        BoxDecoration(
                          color: Colors
                              .red
                              .shade600,
                          borderRadius:
                          BorderRadius
                              .circular(
                              8),
                        ),
                        child: Text(
                          '-$discountPercent%',
                          style:
                          const TextStyle(
                            color: Colors
                                .white,
                            fontSize:
                            10,
                            fontWeight:
                            FontWeight
                                .w800,
                            height:
                            1.0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding:
              const EdgeInsets
                  .fromLTRB(
                10,
                8,
                10,
                8,
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment
                    .start,
                mainAxisSize:
                MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow:
                    TextOverflow
                        .ellipsis,
                    style:
                    const TextStyle(
                      fontWeight:
                      FontWeight
                          .w600,
                      fontSize:
                      13,
                    ),
                  ),
                  const SizedBox(
                      height: 4),
                  hasDiscount
                      ? Row(
                    mainAxisSize:
                    MainAxisSize
                        .min,
                    children: [
                      Text(
                        '฿ ${fmtBaht(discounted)}',
                        maxLines: 1,
                        overflow:
                        TextOverflow
                            .ellipsis,
                        style:
                        const TextStyle(
                          color:
                          Colors.red,
                          fontWeight:
                          FontWeight
                              .w800,
                          fontSize:
                          14,
                          height:
                          1.0,
                        ),
                      ),
                      const SizedBox(
                          width:
                          6),
                      Text(
                        '฿ ${fmtBaht(priceRaw)}',
                        maxLines: 1,
                        overflow:
                        TextOverflow
                            .ellipsis,
                        style:
                        TextStyle(
                          color: Colors
                              .grey
                              .shade600,
                          decoration:
                          TextDecoration
                              .lineThrough,
                          decorationThickness:
                          2,
                          fontWeight:
                          FontWeight
                              .w600,
                          fontSize:
                          11,
                          height:
                          1.0,
                        ),
                      ),
                    ],
                  )
                      : Text(
                    priceRaw == 0
                        ? ''
                        : '฿ ${fmtBaht(priceRaw)}',
                    maxLines: 1,
                    overflow:
                    TextOverflow
                        .ellipsis,
                    style:
                    const TextStyle(
                      fontWeight:
                      FontWeight
                          .w700,
                      fontSize:
                      14,
                      height:
                      1.0,
                    ),
                  ),
                  const SizedBox(
                      height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons
                            .storefront_rounded,
                        size: 13,
                        color: Colors
                            .grey
                            .shade700,
                      ),
                      const SizedBox(
                          width: 6),
                      Expanded(
                        child: Text(
                          sellerNameFromRow,
                          maxLines: 1,
                          overflow:
                          TextOverflow
                              .ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors
                                .grey
                                .shade700,
                            height:
                            1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ---------------------- COMMENT TILE WIDGET ---------------------- */

class _CommentTile extends StatelessWidget {
  final String authorName;
  final String content;
  final String createdAt;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  final Color purple;
  final Color borderGrey;
  final Color subtleBg;
  final Color textDark;
  final Color textLight;

  const _CommentTile({
    required this.authorName,
    required this.content,
    required this.createdAt,
    required this.canEdit,
    this.onEdit,
    this.onDelete,
    required this.purple,
    required this.borderGrey,
    required this.subtleBg,
    required this.textDark,
    required this.textLight,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
      const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor:
            Colors.grey.shade300,
            child: const Icon(
              Icons.person,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Container(
              padding:
              const EdgeInsets.all(
                  12),
              decoration: BoxDecoration(
                color: subtleBg,
                borderRadius:
                BorderRadius
                    .circular(
                    12),
                border: Border.all(
                    color:
                    borderGrey),
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment
                    .start,
                children: [
                  // Name + timestamp
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          authorName,
                          style:
                          TextStyle(
                            fontWeight:
                            FontWeight
                                .w600,
                            fontSize:
                            13,
                            color:
                            textDark,
                          ),
                        ),
                      ),
                      Text(
                        createdAt,
                        style:
                        TextStyle(
                          fontSize:
                          11,
                          color:
                          textLight,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                      height:
                      8),

                  // Comment text
                  Text(
                    content,
                    style:
                    TextStyle(
                      color:
                      textDark,
                      fontSize:
                      14,
                      height:
                      1.4,
                    ),
                  ),

                  // Edit / Delete for own comment
                  if (canEdit) ...[
                    const SizedBox(
                        height:
                        8),
                    Row(
                      mainAxisAlignment:
                      MainAxisAlignment
                          .end,
                      children: [
                        TextButton(
                          style:
                          TextButton.styleFrom(
                            padding:
                            const EdgeInsets.symmetric(
                              horizontal:
                              8,
                              vertical:
                              4,
                            ),
                            minimumSize:
                            Size
                                .zero,
                            foregroundColor:
                            purple,
                          ),
                          onPressed:
                          onEdit,
                          child:
                          const Text(
                            'Edit',
                            style:
                            TextStyle(
                              fontSize:
                              12,
                            ),
                          ),
                        ),
                        const SizedBox(
                            width:
                            8),
                        TextButton(
                          style:
                          TextButton.styleFrom(
                            foregroundColor:
                            Colors
                                .red,
                            padding:
                            const EdgeInsets.symmetric(
                              horizontal:
                              8,
                              vertical:
                              4,
                            ),
                            minimumSize:
                            Size
                                .zero,
                          ),
                          onPressed:
                          onDelete,
                          child:
                          const Text(
                            'Delete',
                            style:
                            TextStyle(
                              fontSize:
                              12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------------------- ALL COMMENTS SHEET ---------------------- */

class _CommentsSheet extends StatefulWidget {
  final int productId;

  // styling from parent so theme matches
  final Color purpleColor;
  final Color purpleDark;
  final Color borderGrey;
  final Color subtleBg;
  final Color textDark;
  final Color textLight;

  // Parent handles edit/delete (re-uses dialog logic)
  final Future<void> Function(
      Map<String, dynamic> commentRow,
      ) onRequestEditComment;
  final Future<void> Function(int commentId)
  onRequestDeleteComment;

  const _CommentsSheet({
    required this.productId,
    required this.onRequestEditComment,
    required this.onRequestDeleteComment,
    required this.purpleColor,
    required this.purpleDark,
    required this.borderGrey,
    required this.subtleBg,
    required this.textDark,
    required this.textLight,
  });

  @override
  State<_CommentsSheet> createState() =>
      _CommentsSheetState();
}

class _CommentsSheetState
    extends State<_CommentsSheet> {
  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _all = [];

  final TextEditingController _sheetCommentCtrl =
  TextEditingController();
  bool _sendingNew = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _sheetCommentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final rows =
      await SupabaseService.fetchAllProductCommentsFull(
        widget.productId,
      );
      if (!mounted) return;
      setState(() {
        _all = rows;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _handlePostNew() async {
    final txt = _sheetCommentCtrl.text.trim();
    if (txt.isEmpty) return;

    setState(() {
      _sendingNew = true;
    });

    try {
      await SupabaseService.addProductComment(
        productId: widget.productId,
        content: txt,
      );

      _sheetCommentCtrl.clear();

      await _loadAll(); // refresh list after posting
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Can't post comment: $e"),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingNew = false;
        });
      }
    }
  }

  Future<void> _handleEdit(
      Map<String, dynamic> row,
      ) async {
    await widget.onRequestEditComment(row);
    await _loadAll();
  }

  Future<void> _handleDelete(
      int commentId,
      ) async {
    await widget.onRequestDeleteComment(
      commentId,
    );
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final purple = widget.purpleColor;
    final purpleDark = widget.purpleDark;
    final borderGrey = widget.borderGrey;
    final subtleBg = widget.subtleBg;
    final textDark = widget.textDark;
    final textLight = widget.textLight;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom:
          MediaQuery.of(context)
              .padding
              .bottom +
              16,
        ),
        child: SizedBox(
          height: MediaQuery.of(context)
              .size
              .height *
              0.7,
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              // drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration:
                  BoxDecoration(
                    color:
                    Colors.grey.shade400,
                    borderRadius:
                    BorderRadius
                        .circular(
                        999),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                'All comments',
                style: TextStyle(
                  fontWeight:
                  FontWeight.w600,
                  color: textDark,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 16),

              // input row to post new comment
              Row(
                crossAxisAlignment:
                CrossAxisAlignment
                    .start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor:
                    Colors.grey
                        .shade300,
                    child:
                    const Icon(
                      Icons.person,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        TextField(
                          controller:
                          _sheetCommentCtrl,
                          maxLines: null,
                          decoration:
                          InputDecoration(
                            hintText:
                            'Write a comment...',
                            hintStyle:
                            TextStyle(
                              color:
                              textLight,
                            ),
                            filled:
                            true,
                            fillColor:
                            Colors
                                .white,
                            contentPadding:
                            const EdgeInsets
                                .symmetric(
                              horizontal:
                              12,
                              vertical:
                              12,
                            ),
                            enabledBorder:
                            OutlineInputBorder(
                              borderRadius:
                              BorderRadius.circular(
                                  8),
                              borderSide:
                              BorderSide(
                                color:
                                borderGrey,
                                width:
                                1.2,
                              ),
                            ),
                            focusedBorder:
                            OutlineInputBorder(
                              borderRadius:
                              BorderRadius.circular(
                                  8),
                              borderSide:
                              BorderSide(
                                color:
                                purpleDark,
                                width:
                                1.2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(
                            height:
                            8),
                        Align(
                          alignment:
                          Alignment
                              .centerRight,
                          child:
                          ElevatedButton(
                            onPressed:
                            _sendingNew
                                ? null
                                : _handlePostNew,
                            style: ElevatedButton
                                .styleFrom(
                              backgroundColor:
                              purpleDark,
                              foregroundColor:
                              Colors
                                  .white,
                              padding:
                              const EdgeInsets
                                  .symmetric(
                                horizontal:
                                16,
                                vertical:
                                10,
                              ),
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(
                                    10),
                              ),
                            ),
                            child:
                            _sendingNew
                                ? const SizedBox(
                              width:
                              16,
                              height:
                              16,
                              child:
                              CircularProgressIndicator(
                                strokeWidth:
                                2,
                                color:
                                Colors.white,
                              ),
                            )
                                : const Text(
                              'Post',
                              style:
                              TextStyle(
                                fontWeight:
                                FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              Divider(
                  height: 1,
                  color: borderGrey),
              const SizedBox(height: 12),

              if (_loading)
                const Center(
                  child: Padding(
                    padding:
                    EdgeInsets.all(
                        24),
                    child:
                    CircularProgressIndicator(),
                  ),
                )
              else if (_err != null)
                Padding(
                  padding:
                  const EdgeInsets
                      .all(24.0),
                  child: Text(
                    'Error loading comments:\n$_err',
                    style:
                    const TextStyle(
                      color:
                      Colors.red,
                    ),
                  ),
                )
              else if (_all.isEmpty)
                  Padding(
                    padding:
                    const EdgeInsets
                        .all(24.0),
                    child: Text(
                      'No comments yet.',
                      style:
                      TextStyle(
                        color:
                        textLight,
                        fontSize:
                        14,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child:
                    ListView.builder(
                      itemCount:
                      _all.length,
                      itemBuilder:
                          (context,
                          index) {
                        final c =
                        _all[index];
                        final mine =
                            c['is_mine'] ==
                                true;
                        final cmtId =
                        c['id']
                        as int?;

                        return _CommentTile(
                          authorName: (c['author_name'] ??
                              'User')
                              .toString(),
                          content: (c['content'] ??
                              '')
                              .toString(),
                          createdAt:
                          (c['created_at'] ??
                              '')
                              .toString(),
                          canEdit:
                          mine,
                          purple:
                          purple,
                          borderGrey:
                          borderGrey,
                          subtleBg:
                          subtleBg,
                          textDark:
                          textDark,
                          textLight:
                          textLight,
                          onEdit: (mine &&
                              cmtId !=
                                  null)
                              ? () => _handleEdit(
                            c,
                          )
                              : null,
                          onDelete:
                          (mine &&
                              cmtId !=
                                  null)
                              ? () => _handleDelete(
                            cmtId,
                          )
                              : null,
                        );
                      },
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

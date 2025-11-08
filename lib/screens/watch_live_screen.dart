// lib/screens/watch_live_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import 'product_detail_screen.dart';

class WatchLiveScreen extends StatefulWidget {
  const WatchLiveScreen({super.key});
  @override
  State<WatchLiveScreen> createState() => _WatchLiveScreenState();
}

class _WatchLiveScreenState extends State<WatchLiveScreen> {
  final _sp = Supabase.instance.client;
  final _controller = PageController();

  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _sp
          .from('streams')
          .select('id, title, host_id, livekit_room, created_at, is_live')
          .eq('is_live', true)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load live streams: $e')),
      );
    }
  }

  void _removeEndedStream(int streamId) {
    if (!mounted) return;
    setState(() {
      _items.removeWhere((m) => m['id'] == streamId);
    });
    // If list became empty, refetch to be safe
    if (_items.isEmpty) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_items.isEmpty) {
      return const Scaffold(body: Center(child: Text('No live streams right now')));
    }

    return Scaffold(
      body: PageView.builder(
        controller: _controller,
        scrollDirection: Axis.vertical,
        itemCount: _items.length,
        itemBuilder: (_, i) => _LivePage(
          item: _items[i],
          onEnded: _removeEndedStream,
        ),
      ),
    );
  }
}

/* ===================== LIVE PAGE ===================== */

class _LivePage extends StatefulWidget {
  final Map<String, dynamic> item;
  final void Function(int streamId)? onEnded;
  const _LivePage({required this.item, this.onEnded});
  @override
  State<_LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<_LivePage> {
  final _sp = Supabase.instance.client;

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  VideoTrack? _remoteVideo;
  RTCVideoRenderer? _renderer;
  bool _connecting = true;

  // Host info
  String? _hostName;
  String? _hostAvatar;

  // Chat state
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  final List<Map<String, dynamic>> _comments = [];
  final Map<String, String> _nameCache = {};
  final Map<String, Color> _nameColorCache = {};
  bool _commentsVisible = true;
  bool _showSwipeHint = false;

  // Realtime channels
  RealtimeChannel? _commentsChannel;
  RealtimeChannel? _streamChannel;

  int get _streamId => widget.item['id'] as int;

  // Product ads
  List<Map<String, dynamic>> _adProducts = [];
  int _adIndex = 0;
  bool _adVisible = true;
  final PageController _adPage = PageController(viewportFraction: 1.0);
  Timer? _adRotateTimer;

  // Layout constants
  static const double _kSideMargin = 10;
  static const double _kAdMaxHeight = 140;
  static const double _kAdMinHeight = 110;
  static const double _kAdWidthFrac = 0.62;

  // Compact transparent chat
  static const double _kChatListHeight = 120;
  static const double _kChatInputHeight = 44;
  static const double _kChatGap = 6;

  @override
  void initState() {
    super.initState();
    _connect();
    _fetchHostProfile();
    _fetchStreamerProducts();
    _subscribeStreamStatus();
  }

  @override
  void dispose() {
    _listener?.dispose();

    if (_renderer != null && _remoteVideo != null) {
      try {
        _renderer!.srcObject = null;
        _remoteVideo!.mediaStreamTrack.enabled = false;
      } catch (_) {}
    }
    _renderer?.dispose();

    _commentsChannel?.unsubscribe();
    _streamChannel?.unsubscribe();
    _room?.dispose();

    _msgCtrl.dispose();
    _chatScroll.dispose();

    _adRotateTimer?.cancel();
    _adPage.dispose();

    super.dispose();
  }

  /* ---------------- LiveKit ---------------- */
  Future<void> _connect() async {
    try {
      final uid = _sp.auth.currentUser?.id;
      if (uid == null) throw 'Not authenticated';

      final res = await _sp.functions.invoke(
        'livekit-token',
        body: {'room': widget.item['livekit_room'], 'identity': uid, 'role': 'viewer'},
      );
      final data = res.data as Map<String, dynamic>;
      final url = data['url'] as String;
      final token = data['token'] as String;

      final room = Room();
      await room.connect(
        url,
        token,
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );

      final listener = room.createListener()
        ..on<TrackSubscribedEvent>((e) {
          if (e.track is VideoTrack) _setRemoteVideo(e.track as VideoTrack);
        })
        ..on<TrackUnsubscribedEvent>((e) {
          if (e.track == _remoteVideo) _setRemoteVideo(null);
        })
      // If the server disconnects the room, treat it as ended.
        ..on<RoomDisconnectedEvent>((_) => _handleStreamEnded());

      _pickExistingRemoteVideo(room);
      await _loadComments();
      _subscribeComments();

      if (!mounted) return;
      setState(() {
        _room = room;
        _listener = listener;
        _connecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _connecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Join failed: $e')),
      );
    }
  }

  void _pickExistingRemoteVideo(Room room) {
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        final t = pub.track;
        if (t != null) {
          _setRemoteVideo(t);
          return;
        }
      }
    }
  }

  Future<void> _setRemoteVideo(VideoTrack? track) async {
    if (_renderer != null && _remoteVideo != null) {
      try {
        _renderer!.srcObject = null;
        _remoteVideo!.mediaStreamTrack.enabled = false;
      } catch (_) {}
      await _renderer!.dispose();
      _renderer = null;
    }
    _remoteVideo = track;

    if (track != null) {
      final r = RTCVideoRenderer();
      await r.initialize();
      r.srcObject = track.mediaStream;
      if (!mounted) {
        await r.dispose();
        return;
      }
      setState(() => _renderer = r);
    } else {
      if (mounted) setState(() {});
    }
  }

  /* ---------------- Stream end: realtime watch ---------------- */
  void _subscribeStreamStatus() {
    _streamChannel?.unsubscribe();
    _streamChannel = _sp
        .channel('realtime:streams_${_streamId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'streams',
        callback: (payload) {
          final row = payload.newRecord;
          if (row == null) return;
          if (row['id'] == _streamId && row['is_live'] == false) {
            _handleStreamEnded();
          }
        },
      )
      ..subscribe();
  }

  void _handleStreamEnded() {
    // Remove this page from parent immediately
    widget.onEnded?.call(_streamId);
    // Also give visual feedback if still mounted
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live has ended')),
      );
    }
  }

  /* ---------------- Host profile ---------------- */
  Future<void> _fetchHostProfile() async {
    try {
      final hostId = (widget.item['host_id'] ?? '').toString();
      if (hostId.isEmpty) return;
      final row = await _sp.from('users').select('full_name, avatar_url').eq('id', hostId).maybeSingle();
      if (!mounted) return;
      setState(() {
        _hostName = (row?['full_name'] as String?)?.trim();
        _hostAvatar = (row?['avatar_url'] as String?)?.trim();
      });
    } catch (_) {}
  }

  /* ---------------- Streamer products ---------------- */
  Future<void> _fetchStreamerProducts() async {
    try {
      final hostId = (widget.item['host_id'] ?? '').toString();
      if (hostId.isEmpty) return;

      final rows = await _sp
          .from('products')
          .select('id, name, price, stock, category, image_urls, seller_id')
          .eq('seller_id', hostId)
          .gt('stock', 0)
          .order('id', ascending: false)
          .limit(20);

      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isEmpty) {
        if (mounted) setState(() => _adProducts = []);
        return;
      }

      try {
        final ids = list.map((e) => e['id']).whereType<int>().toList();
        final best = await SupabaseService.fetchBestDiscountMapForProducts(ids);
        for (final p in list) {
          final pid = p['id'] as int?;
          p['discount_percent'] = pid != null ? (best[pid] ?? 0) : 0;
          p['is_event'] = (p['discount_percent'] ?? 0) > 0;
        }
      } catch (_) {
        for (final p in list) {
          p['discount_percent'] = 0;
          p['is_event'] = false;
        }
      }

      if (!mounted) return;
      setState(() {
        _adProducts = list;
        _adVisible = true;
      });

      _adRotateTimer?.cancel();
      if (_adProducts.length > 1) {
        _adRotateTimer = Timer.periodic(const Duration(seconds: 6), (_) {
          if (!mounted || !_adVisible || _adProducts.isEmpty) return;
          _adIndex = (_adIndex + 1) % _adProducts.length;
          if (_adPage.hasClients) {
            _adPage.animateToPage(_adIndex, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
          } else {
            setState(() {});
          }
        });
      }
    } catch (e) {
      debugPrint('fetchStreamerProducts error: $e');
    }
  }

  /* ---------------- Chat ---------------- */
  Future<void> _loadComments() async {
    try {
      final rows = await _sp
          .from('stream_comments')
          .select('id, user_id, text, created_at')
          .eq('stream_id', _streamId)
          .order('created_at', ascending: true)
          .limit(100);

      _comments
        ..clear()
        ..addAll(List<Map<String, dynamic>>.from(rows as List));

      // Preload names
      final ids = _comments.map((c) => c['user_id'] as String).toSet().toList();
      if (ids.isNotEmpty) {
        final users = await _sp.from('users').select('id, full_name').inFilter('id', ids);
        for (final u in users as List) {
          final id = u['id'] as String;
          final name = (u['full_name'] as String?)?.trim();
          if (name != null && name.isNotEmpty) _nameCache[id] = name;
        }
      }

      if (mounted) setState(() {});
      _scrollChatToEnd();
    } catch (e) {
      debugPrint('Load comments failed: $e');
    }
  }

  void _subscribeComments() {
    _commentsChannel?.unsubscribe();
    _commentsChannel = _sp
        .channel('realtime:stream_comments_${_streamId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'stream_comments',
        callback: (payload) async {
          final row = payload.newRecord;
          if (row == null || row['stream_id'] != _streamId) return;

          final uid = row['user_id'] as String;
          if (!_nameCache.containsKey(uid)) {
            try {
              final u = await _sp.from('users').select('full_name').eq('id', uid).maybeSingle();
              final n = (u?['full_name'] as String?)?.trim();
              if (n != null && n.isNotEmpty) _nameCache[uid] = n;
            } catch (_) {}
          }

          setState(() => _comments.add(row));
          _scrollChatToEnd();
        },
      )
      ..subscribe();
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      final uid = _sp.auth.currentUser!.id;
      await _sp.from('stream_comments').insert({
        'stream_id': _streamId,
        'user_id': uid,
        'text': text,
      });
      _msgCtrl.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e')),
      );
    }
  }

  /* ---------------- Helpers ---------------- */
  String _shortUid(String uid) {
    if (uid.length <= 6) return uid;
    return '${uid.substring(0, 3)}…${uid.substring(uid.length - 3)}';
  }

  List<String> _imgList(dynamic v) {
    if (v is List) return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    if (v is String && v.isNotEmpty) return [v];
    return const [];
  }

  num _numOrZero(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  String _fmtBaht(num value) {
    final s = value.toStringAsFixed(2);
    return s.endsWith('00') ? value.toStringAsFixed(0) : s;
  }

  Color _colorForUser(String uid) {
    // Consistent but varied color per user
    if (_nameColorCache.containsKey(uid)) return _nameColorCache[uid]!;
    final seed = uid.hashCode;
    final hue = (seed % 360).toDouble();
    final hsl = HSLColor.fromAHSL(1, hue, 0.65, 0.55); // vivid-ish
    final c = hsl.toColor();
    _nameColorCache[uid] = c;
    return c;
  }

  /* ---------------- Product Ad overlay (TOP) ---------------- */
  Widget _adOverlayTop(BuildContext context) {
    if (!_adVisible || _adProducts.isEmpty) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    final availableW = mq.size.width - (_kSideMargin * 2);
    final cardW = (availableW * _kAdWidthFrac).clamp(240.0, availableW);

    // just below name row
    final double adTopOffset = mq.padding.top + 10 + 34 + 8;

    return Positioned(
      left: _kSideMargin,
      top: adTopOffset,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: cardW.toDouble(),
          constraints: const BoxConstraints(minHeight: _kAdMinHeight, maxHeight: _kAdMaxHeight),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _adPage,
                  itemCount: _adProducts.length,
                  onPageChanged: (i) => setState(() => _adIndex = i),
                  itemBuilder: (_, i) {
                    final p = _adProducts[i];
                    final name = (p['name'] ?? '').toString();
                    final priceRaw = _numOrZero(p['price']);
                    final discountPercent = p['discount_percent'] is int
                        ? p['discount_percent'] as int
                        : int.tryParse('${p['discount_percent'] ?? 0}') ?? 0;
                    final hasDiscount = discountPercent > 0 && priceRaw > 0;
                    final discounted = hasDiscount ? (priceRaw * (100 - discountPercent)) / 100 : priceRaw;
                    final images = _imgList(p['image_urls'] ?? p['imageurl'] ?? p['image_url']);
                    final img = images.isNotEmpty ? images.first : null;

                    return InkWell(
                      onTap: () {
                        final id = p['id'] as int?;
                        if (id != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProductDetailScreen(productId: id, initialData: p),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 86,
                                height: 86,
                                color: Colors.white10,
                                child: img == null
                                    ? const Icon(Icons.image_not_supported_outlined, color: Colors.white54)
                                    : Image.network(img, fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  hasDiscount
                                      ? Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '฿ ${_fmtBaht(discounted)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          '฿ ${_fmtBaht(priceRaw)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            decoration: TextDecoration.lineThrough,
                                            decorationThickness: 2,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade600,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '-$discountPercent%',
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
                                    '฿ ${_fmtBaht(priceRaw)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Tap to view details',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Close on top (tap target isolated from card tap)
              Positioned(
                right: 4,
                top: 4,
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _adVisible = false),
                      child: const Center(child: Icon(Icons.close, size: 18, color: Colors.white)),
                    ),
                  ),
                ),
              ),

              if (_adProducts.length > 1)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _adProducts.length,
                          (i) => Container(
                        width: i == _adIndex ? 18 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == _adIndex ? Colors.white : Colors.white38,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReopenHint() {
    setState(() => _showSwipeHint = true);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showSwipeHint = false);
    });
  }

  /* ---------------- Build ---------------- */
  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_connecting)
          Container(color: Colors.black, child: const Center(child: CircularProgressIndicator()))
        else if (_renderer != null)
          RTCVideoView(_renderer!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
        else
          Container(
            color: Colors.black,
            child: const Center(child: Text('Waiting for video…', style: TextStyle(color: Colors.white70))),
          ),

        // Streamer name + LIVE
        Positioned(
          top: safe.top + 10,
          left: 16,
          right: 16,
          child: Row(
            children: [
              if (_hostAvatar != null && _hostAvatar!.isNotEmpty)
                CircleAvatar(radius: 14, backgroundImage: NetworkImage(_hostAvatar!))
              else
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.person, size: 16, color: Colors.white),
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _hostName?.isNotEmpty == true ? _hostName! : 'Live',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          shadows: [Shadow(blurRadius: 2)],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(999)),
                      child: const Text('LIVE',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Product ad UNDER the name
        _adOverlayTop(context),

        // CHAT (transparent). Swipe RIGHT to hide. Use smooth AnimatedSlide/Opacity.
        Positioned(
          left: 8,
          right: 8,
          bottom: 8 + safe.bottom,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            offset: _commentsVisible ? Offset.zero : const Offset(1.05, 0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _commentsVisible ? 1 : 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (d) {
                  // swipe RIGHT to hide
                  if (d.primaryVelocity != null && d.primaryVelocity! > 200) {
                    setState(() => _commentsVisible = false);
                    _showReopenHint();
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: _kChatListHeight,
                      child: ListView.builder(
                        controller: _chatScroll,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        itemCount: _comments.length,
                        itemBuilder: (_, i) {
                          final c = _comments[i];
                          final content = (c['text'] ?? '') as String;
                          final uid = (c['user_id'] ?? '') as String;
                          final name = _nameCache[uid] ?? _shortUid(uid);
                          final nameColor = _colorForUser(uid);

                          const msgStyle = TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.1,
                            shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                          );

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: name,
                                    style: msgStyle.copyWith(
                                      color: nameColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const TextSpan(text: '  ', style: msgStyle),
                                  TextSpan(text: content, style: msgStyle),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: _kChatGap),
                    SizedBox(
                      height: _kChatInputHeight,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _msgCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Say something…',
                                hintStyle: const TextStyle(color: Colors.white70),
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.28),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            backgroundColor: Colors.white,
                            child: IconButton(
                              icon: const Icon(Icons.send, color: Colors.black87),
                              onPressed: _sendMessage,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // When chat is hidden: swipe LEFT anywhere to reopen + brief hint
        if (!_commentsVisible)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) {
                if (d.primaryVelocity != null && d.primaryVelocity! < -200) {
                  setState(() {
                    _commentsVisible = true;
                    _showSwipeHint = false;
                  });
                }
              },
              child: Stack(
                children: [
                  if (_showSwipeHint)
                    Positioned(
                      bottom: 16 + safe.bottom,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Swipe left to reopen comments',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          .select('id, title, host_id, livekit_room, created_at')
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
        itemBuilder: (_, i) => _LivePage(item: _items[i]),
      ),
    );
  }
}

class _LivePage extends StatefulWidget {
  final Map<String, dynamic> item;
  const _LivePage({required this.item});

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

  // --- Chat state ---
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  RealtimeChannel? _commentsChannel;
  final List<Map<String, dynamic>> _comments = []; // {id, user_id, text, created_at}
  final Map<String, String> _nameCache = {};       // user_id -> full_name

  int get _streamId => widget.item['id'] as int;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final uid = _sp.auth.currentUser?.id;
      if (uid == null) throw 'Not authenticated';

      // 1) Get viewer token from Supabase Edge Function
      final res = await _sp.functions.invoke(
        'livekit-token',
        body: {
          'room': widget.item['livekit_room'],
          'identity': uid,
          'role': 'viewer',
        },
      );
      final data = res.data as Map<String, dynamic>;
      final url = data['url'] as String;
      final token = data['token'] as String;

      // 2) Connect to LiveKit room
      final room = Room();
      await room.connect(
        url,
        token,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      // 3) Track events
      final listener = room.createListener()
        ..on<TrackSubscribedEvent>((e) {
          if (e.track is VideoTrack) {
            _setRemoteVideo(e.track as VideoTrack);
          }
        })
        ..on<TrackUnsubscribedEvent>((e) {
          if (e.track == _remoteVideo) {
            _setRemoteVideo(null);
          }
        })
        ..on<ParticipantDisconnectedEvent>((_) {
          if (room.remoteParticipants.isEmpty) {
            _setRemoteVideo(null);
          }
        });

      // 4) If a publisher is already live, hook into their video
      _pickExistingRemoteVideo(room);

      // 5) Load chat + subscribe to new messages
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
    // Clean previous renderer
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

      setState(() {
        _renderer = r;
      });
    } else {
      if (mounted) setState(() {});
    }
  }

  // ---------------- Chat ----------------

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

      // Preload names for distinct user_ids
      final ids = _comments.map((c) => c['user_id'] as String).toSet().toList();
      if (ids.isNotEmpty) {
        final users = await _sp
            .from('users')
            .select('id, full_name')
            .inFilter('id', ids); // <- compatible with supabase_flutter 2.10.x

        for (final u in users as List) {
          final id = u['id'] as String;
          final name = (u['full_name'] as String?)?.trim();
          if (name != null && name.isNotEmpty) {
            _nameCache[id] = name;
          }
        }
      }

      if (mounted) setState(() {});
      _scrollChatToEnd();
    } catch (e) {
      debugPrint('Load comments failed: $e');
    }
  }

  void _subscribeComments() {
    // Clean previous subscription if any
    _commentsChannel?.unsubscribe();

    // Broad subscription (filter-less) to avoid SDK filter quirks; filter in callback.
    _commentsChannel = _sp
        .channel('realtime:stream_comments_${_streamId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'stream_comments',
        callback: (payload) async {
          final row = payload.newRecord;
          if (row == null) return;
          if (row['stream_id'] != _streamId) return;

          // Resolve name lazily if not cached
          final uid = row['user_id'] as String;
          if (!_nameCache.containsKey(uid)) {
            try {
              final u = await _sp
                  .from('users')
                  .select('full_name')
                  .eq('id', uid)
                  .maybeSingle();
              final n = (u?['full_name'] as String?)?.trim();
              if (n != null && n.isNotEmpty) {
                _nameCache[uid] = n;
              }
            } catch (_) {}
          }

          setState(() {
            _comments.add(row);
          });
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
    _room?.dispose();

    _msgCtrl.dispose();
    _chatScroll.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;

    return Stack(
      fit: StackFit.expand,
      children: [
        // --- Video / loader ---
        if (_connecting)
          Container(
            color: Colors.black,
            child: const Center(child: CircularProgressIndicator()),
          )
        else if (_renderer != null)
          RTCVideoView(
            _renderer!,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else
          Container(
            color: Colors.black,
            child: const Center(
              child: Text('Waiting for video…', style: TextStyle(color: Colors.white70)),
            ),
          ),

        // --- Top bar ---
        Positioned(
          top: safe.top + 10,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: const [
                    _TabPill(active: true, label: 'Public'),
                    _TabPill(active: false, label: 'Friend'),
                  ],
                ),
              ),
              Row(children: const [
                Icon(Icons.search, color: Colors.white, size: 28, shadows: [Shadow(blurRadius: 2)]),
                SizedBox(width: 12),
                CircleAvatar(radius: 16, backgroundColor: Colors.white24),
              ]),
            ],
          ),
        ),

        // --- Chat panel ---
        Positioned(
          left: 8,
          right: 8,
          bottom: 8 + safe.bottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // message list
              Container(
                height: 240,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  itemCount: _comments.length,
                  itemBuilder: (_, i) {
                    final c = _comments[i];
                    final content = (c['text'] ?? '') as String;
                    final uid = (c['user_id'] ?? '') as String;
                    final name = _nameCache[uid] ?? _shortUid(uid);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: content,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              // input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Say something…',
                        hintStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.35),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
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
            ],
          ),
        ),
      ],
    );
  }

  String _shortUid(String uid) {
    if (uid.length <= 6) return uid;
    return '${uid.substring(0, 3)}…${uid.substring(uid.length - 3)}';
  }
}

class _TabPill extends StatelessWidget {
  final bool active;
  final String label;
  const _TabPill({required this.active, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.black : Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

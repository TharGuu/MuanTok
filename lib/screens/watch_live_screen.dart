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
          .select('id, title, host_id, livekit_room')
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

      // 2) Connect to LiveKit room (2.x API)
      final room = Room();
      await room.connect(
        url,
        token,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      // 3) Listen for track events
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

      // 4) If publisher already live, pick existing video track
      _pickExistingRemoteVideo(room);

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
        final t = pub.track; // 2.x API: use .track
        if (t != null) {
          _setRemoteVideo(t);
          return;
        }
      }
    }
  }

  Future<void> _setRemoteVideo(VideoTrack? track) async {
    // Detach and dispose previous renderer
    if (_renderer != null && _remoteVideo != null) {
      try {
        final mediaStreamTrack = _remoteVideo!.mediaStreamTrack;
        _renderer!.srcObject = null;
        mediaStreamTrack.enabled = false;
      } catch (_) {}
      await _renderer!.dispose();
      _renderer = null;
    }

    _remoteVideo = track;

    if (track != null) {
      final r = RTCVideoRenderer();
      await r.initialize();

      // Attach LiveKit track to RTC renderer
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


  @override
  void dispose() {
    _listener?.dispose();

    // Clean up renderer safely
    if (_renderer != null && _remoteVideo != null) {
      try {
        // Detach the media stream from the renderer instead of removeRenderer()
        _renderer!.srcObject = null;
        _remoteVideo!.mediaStreamTrack.enabled = false;
      } catch (_) {}
    }

    _renderer?.dispose();
    _room?.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ---- LIVE VIDEO or loader ----
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

        // ---- Top bar ----
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
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: const Text('Public', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: const Text('Friend', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
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

        // ---- Right side stats ----
        Positioned(
          right: 16,
          bottom: 24,
          child: Column(
            children: const [
              _SideStat(icon: Icons.favorite_rounded, label: '2.3M'),
              SizedBox(height: 16),
              _SideStat(icon: Icons.comment_rounded, label: '56.7K'),
              SizedBox(height: 16),
              _SideStat(icon: Icons.share_rounded, label: '12.9K'),
              SizedBox(height: 16),
              _SideStat(icon: Icons.bookmark_rounded, label: '88.2K'),
            ],
          ),
        ),

        // ---- Bottom overlays (product pill + creator card) ----
        Positioned(
          left: 16,
          right: 80,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  CircleAvatar(radius: 12, backgroundColor: Color(0xFFFFE0E6)),
                  SizedBox(width: 8),
                  Text('Bags • the product is quite good',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(radius: 18, backgroundColor: Colors.white24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.item['title'] ?? 'Live',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          const Text(
                            'Embracing the lilac skies and chasing dreams… #PastelLife',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.add, size: 16, color: Colors.black87),
                      label: const Text('Follow',
                          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFd1c4e9),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SideStat extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SideStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: Colors.white, size: 34, shadows: const [Shadow(blurRadius: 2)]),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    ],
  );
}

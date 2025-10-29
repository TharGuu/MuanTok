import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _sp = Supabase.instance.client;

  /// ---- form
  final _titleCtrl = TextEditingController(text: 'My Live');

  /// ---- livekit / media
  Room? _room;
  RTCVideoRenderer? _previewRenderer;

  bool _connecting = false;
  bool _isLive = false;
  String? _roomName;

  bool _micOn = true;
  bool _camOn = true;
  CameraPosition _cameraPos = CameraPosition.front;

  /// ---- comments (streamer-side)
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  final List<Map<String, dynamic>> _comments = []; // {id, user_id, text, created_at}
  RealtimeChannel? _cmtsChannel;

  /// current stream row
  int? _streamId;

  /// username cache for comments
  final Map<String, String> _nameCache = {};

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    _chatScroll.dispose();
    _stopLive(silent: true);
    super.dispose();
  }

  // ===================== LIVE START / STOP =====================

  Future<void> _startLive() async {
    if (_isLive || _connecting) return;

    // Permissions
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera & Microphone permission required')),
      );
      return;
    }

    setState(() => _connecting = true);

    try {
      final uid = _sp.auth.currentUser?.id;
      if (uid == null) throw 'Not authenticated';

      // Create new room name
      final rnd = Random().nextInt(999999);
      _roomName = 'muan_${uid.substring(0, 6)}_$rnd';

      // Get LiveKit token from Edge Function
      final fx = await _sp.functions.invoke(
        'livekit-token',
        body: {'room': _roomName, 'identity': uid, 'role': 'host'},
      );
      final data = (fx.data as Map).cast<String, dynamic>();
      final url = data['url'] as String;
      final token = data['token'] as String;

      // Connect to LiveKit
      final room = Room();
      await room.connect(
        url,
        token,
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );

      // Ensure local participant is available
      final local = room.localParticipant;
      if (local == null) throw 'Local participant not available after connect';

      // Enable cam+mic with capture options (so we can flip later)
      await local.setCameraEnabled(
        true,
        cameraCaptureOptions: CameraCaptureOptions(cameraPosition: _cameraPos),
      );
      await local.setMicrophoneEnabled(true);

      // Prepare local preview (use the published camera track)
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      final track = _findLocalCameraTrack(local);
      if (track != null) {
        renderer.srcObject = track.mediaStream;
      }

      // ALWAYS INSERT a new streams row for this live session
      final title =
      _titleCtrl.text.trim().isEmpty ? 'Live' : _titleCtrl.text.trim();

      final inserted = await _sp
          .from('streams')
          .insert({
        'title': title,
        'host_id': uid,
        'livekit_room': _roomName,
        'is_live': true,
      })
          .select('id')
          .single();

      _streamId = (inserted['id'] as num).toInt();

      // Reset chat and subscribe for only this session
      _comments.clear();
      _nameCache.clear();
      await _loadComments(); // fresh row = zero
      _subscribeComments();

      if (!mounted) return;
      setState(() {
        _room = room;
        _previewRenderer = renderer;
        _isLive = true;
        _connecting = false;
        _micOn = true;
        _camOn = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are live!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _connecting = false);
      final msg = e.toString();
      final hint = msg.contains('42501')
          ? '\n(RLS blocked the insert/update. Check your streams policies.)'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to go live: $e$hint')),
      );
    }
  }

  Future<void> _stopLive({bool silent = false}) async {
    if (!_isLive && _room == null) return;

    try {
      // Mark offline in DB (don’t delete the row — keeps VOD/record history if desired)
      final uid = _sp.auth.currentUser?.id;
      if (uid != null) {
        await _sp.from('streams').update({'is_live': false}).eq('host_id', uid);
      }

      // Disable cam/mic
      final local = _room?.localParticipant;
      if (local != null) {
        try {
          await local.setCameraEnabled(false);
          await local.setMicrophoneEnabled(false);
        } catch (_) {}
      }

      // Dispose preview
      if (_previewRenderer != null) {
        try {
          _previewRenderer!.srcObject = null;
        } catch (_) {}
        await _previewRenderer!.dispose();
      }

      // Close realtime
      _cmtsChannel?.unsubscribe();
      _cmtsChannel = null;
      _comments.clear();
      _nameCache.clear();

      // Disconnect room
      final room = _room;
      try {
        await room?.disconnect();
      } catch (_) {}
      await room?.dispose();
    } catch (_) {
      // ignore
    } finally {
      if (!mounted) return;
      setState(() {
        _previewRenderer = null;
        _room = null;
        _isLive = false;
        _roomName = null;
        _streamId = null;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Live ended')),
        );
      }
    }
  }

  // ===================== CAMERA / MIC CONTROLS =====================

  Future<void> _toggleMic() async {
    final local = _room?.localParticipant;
    if (local == null) return;
    try {
      final next = !_micOn;
      await local.setMicrophoneEnabled(next);
      if (!mounted) return;
      setState(() => _micOn = next);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mic toggle failed: $e')),
      );
    }
  }

  Future<void> _toggleCamera() async {
    final local = _room?.localParticipant;
    if (local == null) return;
    try {
      final next = !_camOn;
      await local.setCameraEnabled(
        next,
        cameraCaptureOptions:
        CameraCaptureOptions(cameraPosition: _cameraPos), // keep position
      );

      // Keep preview in sync
      if (next) {
        final track = _findLocalCameraTrack(local);
        if (_previewRenderer != null && track != null) {
          _previewRenderer!.srcObject = track.mediaStream;
        }
      } else {
        _previewRenderer?.srcObject = null;
      }

      if (!mounted) return;
      setState(() => _camOn = next);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera toggle failed: $e')),
      );
    }
  }

  /// Works for SDKs where `switchCamera` expects a **String** ('front'/'back'),
  /// and falls back to re-enable with opposite `CameraPosition`.
  Future<void> _flipCamera() async {
    final local = _room?.localParticipant;
    if (local == null) return;

    try {
      // Try preferred API first: switchCamera on LocalVideoTrack
      final track = _findLocalCameraTrack(local);
      if (track != null) {
        // Your SDK shows 'String' parameter — map CameraPosition -> string
        final newFacing = _cameraPos == CameraPosition.front ? 'back' : 'front';
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        await track.switchCamera(newFacing);

        _cameraPos =
        _cameraPos == CameraPosition.front ? CameraPosition.back : CameraPosition.front;

        if (mounted) setState(() {});
        return;
      }

      // Fallback: disable + re-enable with opposite position
      _cameraPos = _cameraPos == CameraPosition.front
          ? CameraPosition.back
          : CameraPosition.front;

      await local.setCameraEnabled(false);
      await local.setCameraEnabled(
        true,
        cameraCaptureOptions: CameraCaptureOptions(cameraPosition: _cameraPos),
      );

      final t2 = _findLocalCameraTrack(local);
      if (_previewRenderer != null && t2 != null) {
        _previewRenderer!.srcObject = t2.mediaStream;
      }
      if (mounted) setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Flip camera failed: $e')),
      );
    }
  }

  LocalVideoTrack? _findLocalCameraTrack(LocalParticipant local) {
    for (final pub in local.videoTrackPublications) {
      final t = pub.track;
      if (t is LocalVideoTrack) return t;
    }
    return null;
  }

  // ===================== COMMENTS (names + cache) =====================

  Future<void> _loadComments() async {
    final sid = _streamId;
    if (sid == null) return;
    try {
      final rows = await _sp
          .from('stream_comments')
          .select('id, user_id, text, created_at')
          .eq('stream_id', sid)
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
            .inFilter('id', ids);

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
    final sid = _streamId;
    if (sid == null) return;

    // Filter in callback for broad SDK compatibility
    _cmtsChannel = _sp.channel('realtime:stream_comments_$sid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'stream_comments',
        callback: (payload) async {
          final row = payload.newRecord;
          if (row == null) return;
          if (row['stream_id'] == sid) {
            _comments.add(row);

            // Warm the name cache if needed
            final uid = row['user_id'] as String;
            if (!_nameCache.containsKey(uid)) {
              try {
                final user = await _sp
                    .from('users')
                    .select('full_name')
                    .eq('id', uid)
                    .maybeSingle();
                final name = (user?['full_name'] as String?)?.trim();
                if (name != null && name.isNotEmpty) {
                  _nameCache[uid] = name;
                }
              } catch (_) {}
            }

            if (mounted) setState(() {});
            _scrollChatToEnd();
          }
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
    final sid = _streamId;
    final text = _msgCtrl.text.trim();
    if (sid == null || text.isEmpty) return;
    try {
      final uid = _sp.auth.currentUser!.id;
      await _sp.from('stream_comments').insert({
        'stream_id': sid,
        'user_id': uid,
        'text': text,
      });
      _msgCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e')),
      );
    }
  }

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Live'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ===== TOP: VIDEO AREA =====
          Expanded(child: _buildVideoArea()),

          // ===== BOTTOM: CONTROLS + CHAT =====
          _BottomPanel(
            safeBottom: safe.bottom,
            isLive: _isLive,
            roomName: _roomName,
            micOn: _micOn,
            camOn: _camOn,
            onStart: (_isLive || _connecting) ? null : _startLive,
            onEnd: (_isLive || _room != null) ? () => _stopLive() : null,
            onToggleCam: (_room == null) ? null : _toggleCamera,
            onToggleMic: (_room == null) ? null : _toggleMic,
            onFlipCam: (_room == null) ? null : _flipCamera,
            comments: _comments,
            chatScroll: _chatScroll,
            msgCtrl: _msgCtrl,
            nameFor: _displayNameFor,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildVideoArea() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _previewRenderer != null
              ? RTCVideoView(
            _previewRenderer!,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
              : Center(
            child: Text(
              _connecting ? 'Connecting…' : 'Preview will appear here',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }

  String _displayNameFor(String uid) {
    final n = _nameCache[uid];
    if (n != null && n.trim().isNotEmpty) return n;
    // fallback: short uid
    if (uid.length <= 6) return uid;
    return '${uid.substring(0, 3)}…${uid.substring(uid.length - 3)}';
  }
}

// ===================== BOTTOM PANEL WIDGET =====================

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.safeBottom,
    required this.isLive,
    required this.roomName,
    required this.micOn,
    required this.camOn,
    required this.onStart,
    required this.onEnd,
    required this.onToggleCam,
    required this.onToggleMic,
    required this.onFlipCam,
    required this.comments,
    required this.chatScroll,
    required this.msgCtrl,
    required this.nameFor,
    required this.onSend,
  });

  final double safeBottom;
  final bool isLive;
  final String? roomName;

  final bool micOn;
  final bool camOn;

  final VoidCallback? onStart;
  final VoidCallback? onEnd;
  final VoidCallback? onToggleCam;
  final VoidCallback? onToggleMic;
  final VoidCallback? onFlipCam;

  final List<Map<String, dynamic>> comments;
  final ScrollController chatScroll;
  final TextEditingController msgCtrl;
  final String Function(String uid) nameFor;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    const double panelHeight = 320;

    return Container(
      height: panelHeight + safeBottom,
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + safeBottom),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: const [BoxShadow(blurRadius: 14, color: Colors.black12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Controls row
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Start Live'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEnd,
                  icon: const Icon(Icons.stop),
                  label: const Text('End Live'),
                ),
              ),
              const SizedBox(width: 8),
              _RoundIcon(
                icon: camOn ? Icons.videocam : Icons.videocam_off,
                onTap: onToggleCam,
                tooltip: 'Toggle camera',
              ),
              const SizedBox(width: 8),
              _RoundIcon(
                icon: micOn ? Icons.mic : Icons.mic_off,
                onTap: onToggleMic,
                tooltip: 'Toggle mic',
              ),
              const SizedBox(width: 8),
              _RoundIcon(
                icon: Icons.cameraswitch,
                onTap: onFlipCam,
                tooltip: 'Flip camera',
              ),
            ],
          ),
          if (roomName != null) ...[
            const SizedBox(height: 6),
            Text(
              'Room: $roomName',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Colors.black54),
            ),
          ],

          const SizedBox(height: 8),

          // Chat list
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListView.builder(
                controller: chatScroll,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                itemCount: comments.length,
                itemBuilder: (_, i) {
                  final c = comments[i];
                  final text = (c['text'] ?? '') as String;
                  final uid = (c['user_id'] ?? '') as String;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: nameFor(uid),
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: '  '),
                          TextSpan(
                            text: text,
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Chat input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: msgCtrl,
                  decoration: InputDecoration(
                    hintText: 'Say something…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                child: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => onSend(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Ink(
      decoration: const ShapeDecoration(
        color: Color(0xFFEDEDED),
        shape: CircleBorder(),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.black87),
        onPressed: onTap,
        tooltip: tooltip,
      ),
    );
  }
}

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

  final _titleCtrl = TextEditingController(text: 'My Live');

  Room? _room;
  RTCVideoRenderer? _previewRenderer;

  bool _connecting = false;
  bool _isLive = false;
  String? _roomName;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _stopLive(silent: true);
    super.dispose();
  }

  Future<void> _startLive() async {
    if (_isLive || _connecting) return;

    // 1) Ask for permissions
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
      if (uid == null) {
        throw 'Not authenticated';
      }

      // 2) Generate a room name
      final rnd = Random().nextInt(999999);
      _roomName = 'muan_${uid.substring(0, 6)}_$rnd';

      // 3) Get LiveKit token from your Edge Function
      final res = await _sp.functions.invoke(
        'livekit-token',
        body: {
          'room': _roomName,
          'identity': uid,
          'role': 'host',
        },
      );

      // Might throw if function errors
      final data = (res.data as Map).cast<String, dynamic>();
      final url = data['url'] as String;
      final token = data['token'] as String;

      // 4) Connect to LiveKit
      final room = Room();
      await room.connect(
        url,
        token,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      // 5) Enable camera & microphone (v2.5+)
      final local = room.localParticipant;
      if (local == null) {
        throw 'Local participant not available after connect';
      }

      await local.setCameraEnabled(true);
      await local.setMicrophoneEnabled(true);

      // 6) Prepare local preview (use the published camera track)
      final renderer = RTCVideoRenderer();
      await renderer.initialize();

      LocalVideoTrack? cameraTrack;
      for (final pub in local.videoTrackPublications) {
        final t = pub.track;
        if (t is LocalVideoTrack) {
          cameraTrack = t;
          break;
        }
      }
      if (cameraTrack != null) {
        renderer.srcObject = cameraTrack.mediaStream;
      }

      // 7) Upsert 'streams' row (columns: host_id, title, livekit_room, is_live)
      final title = _titleCtrl.text.trim().isEmpty ? 'Live' : _titleCtrl.text.trim();

      final existing = await _sp
          .from('streams')
          .select('id')
          .eq('host_id', uid)
          .maybeSingle();

      if (existing != null) {
        await _sp.from('streams').update({
          'title': title,
          'livekit_room': _roomName,
          'is_live': true,
        }).eq('id', existing['id']);
      } else {
        await _sp.from('streams').insert({
          'title': title,
          'host_id': uid,
          'livekit_room': _roomName,
          'is_live': true,
        });
      }

      if (!mounted) return;
      setState(() {
        _room = room;
        _previewRenderer = renderer;
        _isLive = true;
        _connecting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are live!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _connecting = false);

      // Helpful hint if this is an RLS error (42501)
      final msg = e.toString();
      final hint = msg.contains('42501')
          ? '\n(RLS blocked the insert/update. Ensure your streams policies allow INSERT/UPDATE for authenticated users where host_id = auth.uid().)'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to go live: $e$hint')),
      );
    }
  }

  Future<void> _stopLive({bool silent = false}) async {
    if (!_isLive && _room == null) return;

    try {
      // 1) Mark offline in DB
      final uid = _sp.auth.currentUser?.id;
      if (uid != null) {
        await _sp.from('streams').update({'is_live': false}).eq('host_id', uid);
      }

      // 2) Disable camera/mic
      final local = _room?.localParticipant;
      if (local != null) {
        try {
          await local.setCameraEnabled(false);
          await local.setMicrophoneEnabled(false);
        } catch (e) {
          debugPrint('Failed to disable media: $e');
        }
      }

      // 3) Dispose preview renderer
      if (_previewRenderer != null) {
        try {
          _previewRenderer!.srcObject = null;
        } catch (_) {}
        await _previewRenderer!.dispose();
      }

      // 4) Disconnect from LiveKit
      final room = _room;
      try {
        await room?.disconnect();
      } catch (_) {}
      await room?.dispose();
    } catch (_) {
      // swallow cleanup errors
    } finally {
      if (!mounted) return;
      setState(() {
        _previewRenderer = null;
        _room = null;
        _isLive = false;
        _roomName = null;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Live ended')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Live'),
        centerTitle: true,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16 + safe.top, 16, 24),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'What are you streaming?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Local Preview
          AspectRatio(
            aspectRatio: 9 / 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _previewRenderer != null
                    ? RTCVideoView(
                  _previewRenderer!,
                  objectFit:
                  RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
                    : Center(
                  child: Text(
                    _connecting
                        ? 'Connecting…'
                        : 'Preview will appear here',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Controls
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_isLive || _connecting) ? null : _startLive,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Start Live'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_isLive || _room != null) ? () => _stopLive() : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('End Live'),
                ),
              ),
            ],
          ),

          if (_roomName != null) ...[
            const SizedBox(height: 8),
            Text(
              'Room: $_roomName',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

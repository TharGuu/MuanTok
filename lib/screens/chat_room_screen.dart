// lib/screens/chat_room_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message.dart';
import '../services/messaging_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatRoomScreen extends StatefulWidget {
  final int roomId;
  final String otherUserName;

  const ChatRoomScreen({
    super.key,
    required this.roomId,
    required this.otherUserName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final MessagingService _messagingService = MessagingService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final Stream<List<Message>> _messagesStream;
  late final String _currentUserId;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = Supabase.instance.client.auth.currentUser!.id;
    _messagesStream = _messagingService.getMessagesStream(widget.roomId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendTextMessage() {
    final content = _messageController.text.trim();
    if (content.isNotEmpty) {
      _messagingService.sendMessage(
          roomId: widget.roomId,
          content: content,
          type: 'text',
      );
      _messageController.clear();
      _scrollToBottom();
    }
  }
  // --- NEW: Shows the attachment options menu ---
  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Image'),
                onTap: () {
                  Navigator.pop(context);
                  _sendImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('File'),
                onTap: () {
                  Navigator.pop(context);
                  _sendFile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.location_on),
                title: const Text('Location'),
                onTap: () {
                  Navigator.pop(context);
                  _sendLocation();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- NEW: Image sending logic ---
  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    _uploadFile(File(pickedFile.path), 'image');
  }

  // --- NEW: Generic file sending logic ---
  Future<void> _sendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    _uploadFile(File(result.files.single.path!), 'file');
  }

  // --- NEW: Reusable upload logic ---
  Future<void> _uploadFile(File file, String type) async {
    setState(() => _isUploading = true);
    try {
      final fileUrl = await _messagingService.uploadFile(
        roomId: widget.roomId,
        file: file,
      );

      _messagingService.sendMessage(
        roomId: widget.roomId,
        content: type == 'image' ? 'Sent an image' : 'Sent a file',
        type: type,
        metadata: {'url': fileUrl, 'file_name': file.path.split('/').last},
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // --- NEW: Location sending logic ---
  Future<void> _sendLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are denied.')));
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are permanently denied.')));
      return;
    }

    setState(() => _isUploading = true);
    try {
      final position = await Geolocator.getCurrentPosition();
      final coords = '${position.latitude},${position.longitude}';
      _messagingService.sendMessage(
        roomId: widget.roomId,
        content: 'Shared a location',
        type: 'location',
        metadata: {'coordinates': coords},
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _scrollToBottom() {
    // A small delay ensures the UI has time to build the new message before scrolling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherUserName),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          if (_isUploading) const LinearProgressIndicator(), // Show loading bar during upload
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Padding(padding: const EdgeInsets.all(8.0), child: Text('An error occurred: ${snapshot.error}', textAlign: TextAlign.center)));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('Say hi!'));
                }

                final messages = snapshot.data!;
                _scrollToBottom();

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMine = message.senderId == _currentUserId;
                    // --- MODIFIED: Use the new flexible message bubble builder ---
                    return _buildMessageBubble(message, isMine);
                  },
                );
              },
            ),
          ),
          _buildMessageInputField(),
        ],
      ),
    );
  }

  // Helper widget for the message input area
  Widget _buildMessageInputField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.3), spreadRadius: 1, blurRadius: 5)]),
      child: SafeArea(
        child: Row(
          children: [
            // --- NEW: Attachment Icon ---
            IconButton(
              icon: const Icon(Icons.attach_file, color: Color(0xFF673ab7)),
              onPressed: _showAttachmentMenu,
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(hintText: 'Type a message...', border: InputBorder.none),
                onSubmitted: (_) => _sendTextMessage(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFF673ab7)),
              onPressed: _sendTextMessage,
            ),
          ],
        ),
      ),
    );
  }

  // --- MODIFIED: This widget now handles rendering all message types ---
  Widget _buildMessageBubble(Message message, bool isMine) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = isMine ? const Color(0xFF673ab7) : Colors.grey.shade200;
    final textColor = isMine ? Colors.white : Colors.black87;

    Widget messageContent;

    switch (message.type) {
      case 'image':
        final imageUrl = message.metadata?['url'] ?? '';

        // --- START OF MODIFICATION ---

        messageContent = GestureDetector(
          onTap: () => _openUrl(imageUrl),
          child: ClipRRect(
            // Adds rounded corners to the image, matching the bubble.
            borderRadius: BorderRadius.circular(12.0),
            child: Container(
              // Constrain the size of the image container.
              constraints: BoxConstraints(
                // Max width is 65% of the screen width.
                maxWidth: MediaQuery.of(context).size.width * 0.65,
                // Max height is 300 pixels.
                maxHeight: 300,
              ),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover, // Ensures the image fills the container without distortion.
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  // Shows a spinner inside the image container while loading.
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  // Shows an error icon if the image fails to load.
                  return const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        break;
      case 'file':
        final fileUrl = message.metadata?['url'] ?? '';
        final fileName = message.metadata?['file_name'] ?? 'File';
        messageContent = InkWell(
          onTap: () => _openUrl(fileUrl),
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.description, color: textColor),
              const SizedBox(width: 8),
              Flexible(child: Text(fileName, style: TextStyle(color: textColor, decoration: TextDecoration.underline))),
            ]),
          ),
        );
        break;
      case 'location':
        final coords = message.metadata?['coordinates'] ?? '0,0';
        messageContent = InkWell(
          onTap: () => _openUrl('https://www.google.com/maps/search/?api=1&query=$coords'),
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.location_on, color: textColor),
              const SizedBox(width: 8),
              Text('Shared Location', style: TextStyle(color: textColor, decoration: TextDecoration.underline)),
            ]),
          ),
        );
        break;
      case 'text':
      default:
        messageContent = Text(message.content, style: TextStyle(color: textColor));
        break;
    }

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.circular(20)),
        child: messageContent,
      ),
    );
  }

  // --- NEW: Helper to launch URLs ---
  Future<void> _openUrl(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }
}

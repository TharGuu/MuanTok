import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Add this dependency for date formatting
import 'package:muantok/models/chat_room.dart';
import 'package:muantok/services/messaging_service.dart';
import 'package:muantok/screens/chat_room_screen.dart';

class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key});

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final MessagingService _messagingService = MessagingService();
  late Future<List<ChatRoom>> _chatRoomsFuture;

  @override
  void initState() {
    super.initState();
    _loadChatRooms();
  }

  void _loadChatRooms() {
    _chatRoomsFuture = _messagingService.getChatRooms();
  }

  // Helper to format the timestamp
  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return DateFormat('MMM d').format(timestamp); // e.g., Oct 28
    } else {
      return DateFormat('h:mm a').format(timestamp); // e.g., 9:45 AM
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: FutureBuilder<List<ChatRoom>>(
        future: _chatRoomsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No conversations yet.\nStart a chat from a user\'s profile.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final chatRooms = snapshot.data!;

          return RefreshIndicator(
            onRefresh: () async => setState(() => _loadChatRooms()),
            child: ListView.builder(
              itemCount: chatRooms.length,
              itemBuilder: (context, index) {
                final room = chatRooms[index];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 28,
                    backgroundImage: (room.otherUser.avatarUrl != null && room.otherUser.avatarUrl!.isNotEmpty)
                        ? NetworkImage(room.otherUser.avatarUrl!)
                        : null,
                    child: (room.otherUser.avatarUrl == null || room.otherUser.avatarUrl!.isEmpty)
                        ? const Icon(Icons.person, size: 28)
                        : null,
                  ),
                  title: Text(
                    room.otherUser.fullName ?? 'User',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    room.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _formatTimestamp(room.lastMessageTimestamp),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  onTap: () async {
                    // Navigate to the chat room and refresh the list when we return
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(
                          roomId: room.roomId,
                          otherUserName: room.otherUser.fullName ?? 'User',
                        ),
                      ),
                    );
                    // Refresh the list after coming back from a chat
                    setState(() {
                      _loadChatRooms();
                    });
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

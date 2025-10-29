import 'package:muantok/models/user_profile.dart';

class ChatRoom {
  final int roomId;
  final UserProfile otherUser;
  final String lastMessage;
  final DateTime? lastMessageTimestamp;

  ChatRoom({
    required this.roomId,
    required this.otherUser,
    required this.lastMessage,
    this.lastMessageTimestamp,
  });

  // A factory constructor to create a ChatRoom from a JSON map
  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      roomId: json['room_id'],
      otherUser: UserProfile.fromChatList(json), // A new helper constructor
      lastMessage: json['last_message_content'] ?? 'No messages yet.',
      lastMessageTimestamp: json['last_message_timestamp'] != null
          ? DateTime.parse(json['last_message_timestamp'])
          : null,
    );
  }
}
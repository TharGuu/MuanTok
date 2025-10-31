// lib/models/message.dart

class Message {
  final int id;
  final int roomId;
  final String senderId;
  final String content; // Will still be used for text messages or as a caption
  final DateTime createdAt;
  final String senderFullName;
  final String senderAvatarUrl;

  // --- NEW FIELDS ---
  final String type; // 'text', 'image', 'file', 'location'
  final Map<String, dynamic>? metadata; // For URL, coordinates, etc.

  Message({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.senderFullName,
    required this.senderAvatarUrl,
    // --- NEW ---
    this.type = 'text',
    this.metadata,
  });

  factory Message.fromJson(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      roomId: map['room_id'],
      senderId: map['sender_id'],
      content: map['content'],
      createdAt: DateTime.parse(map['created_at']),
      senderFullName: map['sender']?['full_name'] ?? 'User',
      senderAvatarUrl: map['sender']?['avatar_url'] ?? '',
      // --- NEW ---
      type: map['type'] ?? 'text',
      metadata: map['metadata'] != null ? map['metadata'] as Map<String, dynamic> : null,
    );
  }
}

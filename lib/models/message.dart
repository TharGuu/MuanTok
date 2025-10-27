// lib/models/message.dart

class Message {
  final String id;
  final String content;
  final String senderId;
  final DateTime createdAt;
  final String senderFullName;
  final String? senderAvatarUrl;

  Message({
    required this.id,
    required this.content,
    required this.senderId,
    required this.createdAt,
    required this.senderFullName,
    this.senderAvatarUrl,
  });

  factory Message.fromJson(Map<String, dynamic> map) {
    // The 'sender' data comes from the join we did in the query.
    final senderData = map['sender'] as Map<String, dynamic>?;

    return Message(
      id: map['id'].toString(),
      content: map['content'] as String,
      senderId: map['sender_id'] as String,
      createdAt: DateTime.parse(map['created_at']),
      senderFullName: senderData?['full_name'] ?? 'Unknown User',
      senderAvatarUrl: senderData?['avatar_url'] as String?,
    );
  }
}

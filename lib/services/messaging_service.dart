// lib/services/messaging_service.dart

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message.dart'; // We will create this model next
import 'package:rxdart/rxdart.dart';

class MessagingService {
  final _supabase = Supabase.instance.client;

  /// Finds an existing chat room between two users, or creates a new one if it doesn't exist.
  Future<int> getOrCreateRoom(String otherUserId) async {
    final currentUserId = _supabase.auth.currentUser!.id;

    // Use an RPC (Remote Procedure Call) on the database for this complex logic.
    // This is more efficient and secure than doing multiple queries from the client.
    // We will create this 'create_or_get_room' function in the next step.
    final response = await _supabase.rpc(
      'create_or_get_room',
      params: {'user_1': currentUserId, 'user_2': otherUserId},
    );

    // The RPC will return the ID of the room.
    return response as int;
  }

  /// Sends a message to a specific chat room.
  Future<void> sendMessage({required int roomId, required String content}) async {
    final senderId = _supabase.auth.currentUser!.id;

    final message = {
      'room_id': roomId,
      'sender_id': senderId,
      'content': content,
    };

    // The RLS policies we created will ensure the user is allowed to do this.
    await _supabase.from('messages').insert(message);
  }

  /// Listens for new messages in a specific room using Supabase Realtime.
  Stream<List<Message>> getMessagesStream(int roomId) {
    // This function now correctly handles both initial data and new messages.

    // 1. Fetch initial data
    final initialStream = _supabase
        .from('messages')
        .select('*, sender:users(full_name, avatar_url)')
        .eq('room_id', roomId)
        .order('created_at', ascending: true)
        .asStream(); // Use asStream() to treat the initial fetch as a stream

    // 2. Listen for new inserts
    final realtimeStream = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: true); // Order new messages too

    // 3. Combine and process the streams
    return initialStream.asyncMap((initialData) {
      // This runs once with the initial data
      final messages =
      (initialData as List<dynamic>).map((msg) => Message.fromJson(msg)).toList();

      // Now, listen to the realtime stream for any updates
      return realtimeStream.map((newData) {
        // When a new message payload comes in...
        for (var payload in newData) {
          // ...find if it's an update to an existing message or a new one
          final index = messages.indexWhere((m) => m.id == payload['id'].toString());
          if (index != -1) {
            // If it's an update, replace it
            messages[index] = Message.fromJson(payload);
          } else {
            // If it's a new message, add it to the list
            messages.add(Message.fromJson(payload));
          }
        }
        // Sort the list one last time to be sure
        messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return messages;
      }).startWith(messages); // Immediately return the initial list
    }).switchMap((stream) => stream); // Flatten the stream of streams
  }
}

// lib/services/messaging_service.dart

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message.dart'; // We will create this model next
import 'package:rxdart/rxdart.dart';

class MessagingService {
  final _supabase = Supabase.instance.client;

  /// Finds an existing chat room between two users, or creates a new one if it doesn't exist.
  Future<int> getOrCreateRoom(String otherUserId) async {
    try {
      // Correctly call the RPC function with a single named parameter.
      // The function itself handles getting the current user's ID on the backend.
      final response = await _supabase.rpc(
        'create_or_get_room',
        params: {
          'other_user_id': otherUserId, // Pass only the other user's ID
        },
      );

      // The RPC function returns the room_id, so we cast it to an integer.
      return response as int;

    } catch (e) {
      // Re-throw the exception to be handled by the UI.
      throw Exception('Failed to get or create room: $e');
    }
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
    // This defines a realtime channel that listens for inserts on the messages table
    final channel = _supabase
        .from('messages')
        .stream(primaryKey: ['id']).eq('room_id', roomId);

    // Use a StreamTransformer to process the stream
    final transformer = StreamTransformer<
        List<Map<String, dynamic>>, List<Message>>.fromHandlers(
      handleData: (payload, sink) {
        // When new data comes in, fetch the whole list again with sender info.
        // This is a simple and reliable way to ensure data consistency.
        _supabase
            .from('messages')
            .select('*, sender:users(full_name, avatar_url)')
            .eq('room_id', roomId)
            .order('created_at', ascending: true)
            .then((data) {
          final messages =
          (data as List<dynamic>).map((msg) => Message.fromJson(msg)).toList();
          // Add the newly fetched and parsed list to the stream sink
          sink.add(messages);
        }).catchError((error) {
          // If there's an error fetching, add it to the stream sink
          sink.addError(error);
        });
      },
    );

    // First, fetch the initial data to show something immediately
    final initialDataFuture = _supabase
        .from('messages')
        .select('*, sender:users(full_name, avatar_url)')
        .eq('room_id', roomId)
        .order('created_at', ascending: true);

    // Return a new stream that starts with the initial data and then
    // listens to the realtime channel, transforming its output.
    return Stream.fromFuture(initialDataFuture).map((data) {
      return (data as List<dynamic>).map((msg) => Message.fromJson(msg)).toList();
    }).asyncExpand((initialMessages) {
      // Start with the initial messages, then pipe the realtime channel through our transformer
      return channel.transform(transformer).startWith(initialMessages);
    });
  }
}
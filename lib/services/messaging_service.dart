// lib/services/messaging_service.dart

import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_room.dart';
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
  Future<void> sendMessage({
    required int roomId,
    required String content,
    String type = 'text',
    Map<String, String>? metadata,
  }) async {
    final senderId = _supabase.auth.currentUser!.id;
    await _supabase.from('messages').insert({
      'room_id': roomId,
      'sender_id': senderId,
      'content': content,
      'type': type,       // NEW
      'metadata': metadata, // NEW
    });
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
  Future<List<ChatRoom>> getChatRooms() async {
    try {
      // Call the RPC function we just created
      final response = await _supabase.rpc('get_chat_rooms_for_user');

      // The response is a List<dynamic>, where each item is a Map
      if (response is List) {
        // Use the factory constructor to parse the JSON into ChatRoom objects
        return response.map((roomJson) => ChatRoom.fromJson(roomJson)).toList();
      }
      return [];
    } catch (e) {
      // Rethrow the exception to be handled by the UI
      throw Exception('Failed to fetch chat rooms: $e');
    }
  }

  Future<String> uploadFile({
    required int roomId,
    required File file,
  }) async {
    final fileExtension = file.path.split('.').last;
    final fileName = '${DateTime.now().toIso8601String()}.$fileExtension';
    final filePath = 'rooms/$roomId/$fileName';

    // Upload file to Supabase Storage
    await _supabase.storage.from('chat_attachments').upload(filePath, file);

    // Get the public URL of the uploaded file
    final fileUrl = _supabase.storage.from('chat_attachments').getPublicUrl(filePath);

    return fileUrl;
  }
}
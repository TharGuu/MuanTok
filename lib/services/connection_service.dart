// lib/services/connection_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class ConnectionService {
  final _supabase = Supabase.instance.client;

  /// Checks if the current user is following a specific userId.
  Future<bool> isFollowing(String userId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return false;

    final response = await _supabase
        .from('connections')
        .select('id')
        .eq('follower_id', currentUserId)
        .eq('following_id', userId)
        .limit(1);

    // If the query returns any rows, it means the connection exists.
    return response.isNotEmpty;
  }

  /// Follows a user.
  Future<void> followUser(String userId) async {
    final currentUserId = _supabase.auth.currentUser!.id;

    await _supabase.from('connections').insert({
      'follower_id': currentUserId,
      'following_id': userId,
    });
  }

  /// Unfollows a user.
  Future<void> unfollowUser(String userId) async {
    final currentUserId = _supabase.auth.currentUser!.id;

    await _supabase
        .from('connections')
        .delete()
        .eq('follower_id', currentUserId)
        .eq('following_id', userId);
  }
}

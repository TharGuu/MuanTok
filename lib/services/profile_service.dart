import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart'; // Assume this file holds the UserProfile class
import 'package:muantok/screens/connections_screen.dart';

class ProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String functionName = 'get_user_profile';
  static const String tableName = 'users';

  ProfileService(); // Make constructor const for use in ProfileScreen

  // Fallback profile data for unauthenticated users or testing
  UserProfile _unauthenticatedProfile() {
    return UserProfile(
      id: 'unauthenticated',
      fullName: 'Guest User',
      bio: 'Please sign in to view your profile and stats.',
      avatarUrl: null, // No avatar
      followersCount: 0,
      followingCount: 0,
      productsCount: 0,
    );
  }

  Future<UserProfile> fetchUserProfile(String userId) async {
    // Crucial Check: If the Supabase client doesn't recognize a logged-in user,
    // return the fallback profile instead of attempting an RPC call that will fail.
    if (_supabase.auth.currentUser?.id == null) {
      print('Warning: User is not logged in. Returning unauthenticated profile.');
      return _unauthenticatedProfile();
    }

    try {
      // Call the stored procedure
      final response = await _supabase.rpc(
        functionName,
        params: {
          'user_id': userId,
        },
      );

      // Handle the response (it should be a list with one item)
      if (response is List && response.isNotEmpty) {
        return UserProfile.fromJson(response[0] as Map<String, dynamic>);
      } else {
        // If the user is authenticated but the public.users table has no record (rare, but possible)
        throw Exception('User record found in auth but not in public.users.');
      }
    } on PostgrestException catch (error) {
      print('PostgREST Error fetching profile: ${error.message}');
      rethrow;
    } catch (e) {
      print('General Error fetching profile: $e');
      rethrow;
    }
  }

  /// Updates the user's profile data in the public.users table.
  Future<void> updateUserProfile({
    required String userId,
    String? fullName,
    String? bio,
    String? phone,      // ADDED
    String? address,    // ADDED
    String? avatarUrl,
  }) async {
    final Map<String, dynamic> updates = {};
    if (fullName != null) updates['full_name'] = fullName;
    if (bio != null) updates['bio'] = bio;
    if (phone != null) updates['phone'] = phone;       // ADDED
    if (address != null) updates['address'] = address; // ADDED
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

    if (updates.isEmpty) {
      return; // Nothing to update
    }

    try {
      await _supabase
          .from(tableName)
          .update(updates)
          .eq('id', userId);

      // Also update the auth.users metadata if relevant fields changed
      final Map<String, dynamic> authUpdates = {};
      if (fullName != null) authUpdates['full_name'] = fullName;
      if (avatarUrl != null) authUpdates['avatar_url'] = avatarUrl;

      if (authUpdates.isNotEmpty) {
        await _supabase.auth.updateUser(UserAttributes(data: authUpdates));
      }

    } on PostgrestException catch (error) {
      print('Update Profile Error: ${error.message}');
      throw Exception('Failed to update profile data: ${error.message}');
    } catch (e) {
      print('Unexpected Update Error: $e');
      rethrow;
    }
  }

  Future<List<UserProfile>> fetchConnections({
    required String userId,
    required ConnectionsMode mode,
  }) async {
    final response = await _supabase.rpc(
      'get_user_connections',
      params: {
        'p_user_id': userId,
        'p_mode': mode == ConnectionsMode.following ? 'following' : 'followers',
      },
    );

    if (response is List) {
      // We can reuse the UserProfile.fromChatList constructor if it fits,
      // or create a more specific one. For now, let's make a simple one.
      return response.map((data) {
        return UserProfile(
          id: data['id'],
          fullName: data['full_name'],
          avatarUrl: data['avatar_url'],
          // Provide default values for non-nullable fields
          followersCount: 0,
          followingCount: 0,
          productsCount: 0,
        );
      }).toList();
    }
    return [];
  }
}

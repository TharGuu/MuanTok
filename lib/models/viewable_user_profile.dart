// lib/models/viewable_user_profile.dart

import 'user_profile.dart';

// This class combines the user's profile data with the current user's relationship to them.
class ViewableUserProfile {
  final UserProfile profile;
  final bool isFollowing;

  ViewableUserProfile({required this.profile, required this.isFollowing});
}

// In lib/models/user_profile.dart

class UserProfile {
  final String id;
  final String? fullName;
  final String? bio;
  final String? avatarUrl;
  final String? phone;    // ADDED
  final String? address;  // ADDED
  final int followersCount;
  final int followingCount;
  final int productsCount;

  UserProfile({
    required this.id,
    this.fullName,
    this.bio,
    this.avatarUrl,
    this.phone,         // ADDED
    this.address,       // ADDED
    required this.followersCount,
    required this.followingCount,
    required this.productsCount,
  });

  factory UserProfile.fromJson(Map<String, dynamic> map) {
    int parseCount(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? 0;
    }

    return UserProfile(
      id: map['id'] as String,
      fullName: map['full_name'] as String?,
      bio: map['bio'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      phone: map['phone'] as String?,       // ADDED
      address: map['address'] as String?,   // ADDED
      followersCount: parseCount(map['followers_count']),
      followingCount: parseCount(map['following_count']),
      productsCount: parseCount(map['products_count']),
    );
  }

  factory UserProfile.fromChatList(Map<String, dynamic> json) {
    return UserProfile(
      id: json['other_user_id'],
      fullName: json['other_user_full_name'],
      avatarUrl: json['other_user_avatar_url'],
      // The other fields are not needed for the chat list, so they can be null/default.
      bio: null,
      followingCount: 0,
      followersCount: 0,
      productsCount: 0,
    );
  }
}

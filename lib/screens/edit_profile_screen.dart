import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import '../services/profile_service.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile initialProfile;

  const EditProfileScreen({super.key, required this.initialProfile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _bioController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  final ProfileService _profileService = ProfileService();
  bool _isLoading = false;

  // --- NEW: State variable to hold the selected image file ---
  XFile? _selectedImage;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.initialProfile.fullName ?? '');
    _bioController = TextEditingController(text: widget.initialProfile.bio ?? '');
    _phoneController = TextEditingController(text: widget.initialProfile.phone ?? '');
    _addressController = TextEditingController(text: widget.initialProfile.address ?? '');
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // --- NEW: Method to let the user pick an image from the gallery ---
  Future<void> _pickAvatar() async {
    final ImagePicker picker = ImagePicker();
    // Open image gallery to let user pick an image
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80, // Compress image slightly to save space
    );

    // If the user picked an image, update the state to show a preview
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  // --- UPDATED: The main profile update logic ---
  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    String? avatarUrl = widget.initialProfile.avatarUrl;

    try {
      // --- NEW: UPLOAD LOGIC ---
      // If a new image was selected, upload it first.
      if (_selectedImage != null) {
        final imageFile = File(_selectedImage!.path);
        final userId = Supabase.instance.client.auth.currentUser!.id;
        // Create a unique file path: /<user_id>/avatar_<timestamp>
        final imagePath = '/$userId/avatar_${DateTime.now().millisecondsSinceEpoch}';

        // Upload the image to the 'avatars' bucket in Supabase Storage
        await Supabase.instance.client.storage.from('avatars').upload(
          imagePath,
          imageFile,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: lookupMimeType(imageFile.path),
          ),
        );

        // Get the public URL of the newly uploaded image
        avatarUrl = Supabase.instance.client.storage
            .from('avatars')
            .getPublicUrl(imagePath);
      }
      // --- END OF UPLOAD LOGIC ---

      // Now, call the updateUserProfile service with the new data.
      // This will be the existing URL if no new image was picked,
      // or the new URL if an upload was successful.
      await _profileService.updateUserProfile(
        userId: widget.initialProfile.id,
        fullName: _fullNameController.text.trim(),
        bio: _bioController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        avatarUrl: avatarUrl, // Pass the new or existing URL
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
        Navigator.of(context).pop(true); // Pop back and indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryPurple = Color(0xFF673ab7);

    // --- NEW: Logic to determine what image to display in the CircleAvatar ---
    ImageProvider? avatarImage;
    if (_selectedImage != null) {
      // If a new image has been picked, show it from the local file
      avatarImage = FileImage(File(_selectedImage!.path));
    } else if (widget.initialProfile.avatarUrl != null && widget.initialProfile.avatarUrl!.isNotEmpty) {
      // Otherwise, show the existing image from the network URL
      avatarImage = NetworkImage(widget.initialProfile.avatarUrl!);
    }
    // If both are null, the CircleAvatar will show a default icon.

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- UPDATED: Avatar Area is now interactive ---
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: avatarImage, // Use the dynamic avatarImage
                      child: avatarImage == null ? Icon(Icons.person, size: 60, color: Colors.grey.shade600) : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector( // Wrap the icon in GestureDetector
                        onTap: _pickAvatar,    // Call the image picker on tap
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: primaryPurple,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // ... The rest of your form fields remain unchanged ...
              _buildTextField(
                controller: _fullNameController,
                label: 'Full Name',
                hint: 'Enter your full name',
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Full name cannot be empty';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              _buildTextField(
                controller: _phoneController,
                label: 'Phone Number',
                hint: 'Enter your phone number',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),

              _buildTextField(
                controller: _addressController,
                label: 'Address',
                hint: 'Enter your shipping address',
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              _buildTextField(
                controller: _bioController,
                label: 'Bio',
                hint: 'Tell us about yourself (max 150 characters)',
                maxLines: 4,
                maxLength: 150,
              ),
              const SizedBox(height: 30),

              ElevatedButton(
                onPressed: _isLoading ? null : _updateProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryPurple,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white),
                )
                    : const Text(
                  'Save Changes',
                  style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // The _buildTextField helper remains unchanged
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          ),
        ),
      ],
    );
  }
}

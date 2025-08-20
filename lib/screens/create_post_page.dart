import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../providers/circle_provider.dart';
import 'footer_nav_bar.dart';
import 'cloudinary_config.dart';
import 'emoji_picker_page.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({Key? key, this.allowVideo = false}) : super(key: key);

  final bool allowVideo;

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  static const int _kMaxTextLength = 800;
  static const int _kMaxImages = 6;
  static const int _kMaxImageSizeBytes = 5 * 1024 * 1024;

  final TextEditingController _textController = TextEditingController();
  final List<File> _mediaFiles = [];
  final List<String> _uploadedUrls = [];
  final ImagePicker _picker = ImagePicker();

  bool _isUploading = false;

  Future<void> _pickImages() async {
    try {
      final List<XFile>? picked = await _picker.pickMultiImage();
      if (picked == null || picked.isEmpty) return;

      if ((_mediaFiles.length + picked.length) > _kMaxImages) {
        final remaining = _kMaxImages - _mediaFiles.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You can add up to $_kMaxImages images (${remaining.clamp(0, _kMaxImages)} more).'),
          ),
        );
        return;
      }

      final List<File> validFiles = [];
      for (final XFile x in picked) {
        final f = File(x.path);
        if (await f.length() > _kMaxImageSizeBytes) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Each image must be ≤ 5 MB. "${x.name}" is too large.')),
          );
          continue;
        }
        validFiles.add(f);
      }

      if (validFiles.isNotEmpty) {
        setState(() => _mediaFiles.addAll(validFiles));
      }
    } catch (e) {
      debugPrint('Image pick error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to pick images')),
      );
    }
  }

  Future<void> _pickEmoji() async {
    final emoji = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => EmojiPickerPage(), fullscreenDialog: true),
    );
    if (emoji == null) return;

    setState(() {
      _textController
        ..text += emoji
        ..selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
    });
  }

  Future<void> _uploadImages() async {
    _uploadedUrls.clear();
    setState(() => _isUploading = true);

    for (final file in _mediaFiles) {
      try {
        final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudinaryCloudName/upload');
        final req = http.MultipartRequest('POST', uri)
          ..fields['upload_preset'] = cloudinaryUploadPreset
          ..files.add(await http.MultipartFile.fromPath('file', file.path));

        final res = await req.send();
        if (res.statusCode == 200) {
          final data = json.decode(await res.stream.bytesToString()) as Map<String, dynamic>;
          final url = data['secure_url'] as String?;
          if (url != null) _uploadedUrls.add(url);
        } else {
          debugPrint('Cloudinary HTTP ${res.statusCode}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed (HTTP ${res.statusCode})')),
          );
        }
      } catch (e) {
        debugPrint('Upload error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image upload error')),
        );
      }
    }

    setState(() => _isUploading = false);
  }

  Future<void> _submitPost() async {
    final circle = context.read<CircleProvider>().circleData;
    if (circle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your circle first.')),
      );
      return;
    }

    final text = _textController.text.trim();
    if (text.isEmpty && _mediaFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some text or an image.')),
      );
      return;
    }

    if (text.length > _kMaxTextLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Text cannot exceed $_kMaxTextLength characters.')),
      );
      return;
    }

    if (_mediaFiles.isNotEmpty && _uploadedUrls.isEmpty) await _uploadImages();

    try {
      final user = FirebaseAuth.instance.currentUser;
      final displayName = (user?.displayName?.trim().isNotEmpty ?? false)
          ? user!.displayName!
          : user?.email?.split('@').first ?? 'Anonymous';

      await FirebaseFirestore.instance.collection('posts').add({
        'content': text,
        'mediaUrls': _uploadedUrls,
        'mediaType': _uploadedUrls.isEmpty ? null : 'image',
        'timestamp': FieldValue.serverTimestamp(),
        'likes': [],
        'commentsCount': 0,
        'tag': 'user',
        'state': circle['state'] ?? '',
        'district': circle['district'] ?? '',
        'pinCode': circle['pinCode'] ?? '',
        'userId': user?.uid ?? '',
        'username': displayName,
        'email': user?.email ?? '',
        'photoURL': user?.photoURL ?? '',
        'lastActivityAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Post submitted successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Firestore error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Failed to submit post')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Create Post'),
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary,
        foregroundColor: theme.appBarTheme.foregroundColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: theme.shadowColor.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _textController,
                    maxLength: _kMaxTextLength,
                    maxLines: null,
                    decoration: InputDecoration.collapsed(
                      hintText: 'What\'s on your mind?',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                    ),
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.image, color: theme.colorScheme.primary),
                        onPressed: _pickImages,
                      ),
                      IconButton(
                        icon: Icon(Icons.emoji_emotions_outlined, color: theme.colorScheme.secondary),
                        onPressed: _pickEmoji,
                      ),
                    ],
                  ),
                  if (_mediaFiles.isNotEmpty)
                    SizedBox(
                      height: 200,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _mediaFiles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _mediaFiles[i],
                            height: 200,
                            width: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _submitPost,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  backgroundColor: theme.colorScheme.primary,
                ),
                child: _isUploading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        'Post',
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onPrimary),
                      ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: FooterNavBar(
        selectedIndex: 2,
        onTap: (i) {
          const routes = ['/home', '/news', '/rate', '/party', '/profile'];
          if (i < routes.length) Navigator.pushReplacementNamed(context, routes[i]);
        },
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}

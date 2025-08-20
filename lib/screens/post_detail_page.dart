import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'post_card_widget.dart';
import 'comments_section.dart';
import '../theme/app_theme.dart';

class PostDetailPage extends StatefulWidget {
  final String postId;
  final bool isEditMode; // <-- added

  const PostDetailPage({
    Key? key,
    required this.postId,
    this.isEditMode = false, // default false
  }) : super(key: key);

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late final String userId;
  final TextEditingController _textController = TextEditingController();
  Map<String, dynamic>? postData;
  bool loading = true;
  bool isEditMode = false;
  bool isCommenting = false;

  @override
  void initState() {
    super.initState();
    userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    isEditMode = widget.isEditMode; // <-- initialize from widget
    _fetchPost();
  }

  Future<void> _fetchPost() async {
    final doc =
        await FirebaseFirestore.instance.collection('posts').doc(widget.postId).get();
    if (!mounted) return;

    setState(() {
      postData = doc.data();
      if (isEditMode && postData != null) {
        _textController.text = postData!['content'] ?? '';
      }
      loading = false;
    });
  }

  Future<void> _updatePost() async {
    if (_textController.text.trim().isEmpty) return;

    await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .update({'content': _textController.text.trim()});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Post updated successfully')),
    );
    setState(() {
      isEditMode = false;
    });
    _fetchPost(); // refresh content
  }

  Future<void> _deletePost() async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Delete Post?'),
              content: const Text('Are you sure you want to delete this post?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
              ],
            ));

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('posts').doc(widget.postId).delete();
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  Future<void> _addComment(String comment) async {
    if (comment.trim().isEmpty || postData == null) return;

    setState(() => isCommenting = true);

    try {
      final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);
      await postRef.update({
        'commentsCount': FieldValue.increment(1),
      });

      await postRef.collection('comments').add({
        'userId': userId,
        'content': comment.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      _textController.clear();
      _fetchPost();
    } catch (e) {
      debugPrint('Add comment error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add comment')),
      );
    }

    setState(() => isCommenting = false);
  }

  void _toggleLike() async {
    if (postData == null) return;
    final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);
    final likes = List<String>.from(postData!['likes'] ?? []);

    if (likes.contains(userId)) {
      likes.remove(userId);
    } else {
      likes.add(userId);
    }

    await postRef.update({'likes': likes});
    _fetchPost();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.lightTheme;

    if (loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Post Detail'),
          backgroundColor: theme.colorScheme.primary,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (postData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Post Detail'),
          backgroundColor: theme.colorScheme.primary,
        ),
        body: const Center(child: Text('Post not found')),
      );
    }

    final isOwner = postData!['userId'] == userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post Detail'),
        backgroundColor: theme.colorScheme.primary,
        actions: [
          if (isOwner)
            PopupMenuButton(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: const [
                      Icon(Icons.edit, color: Colors.black),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: const [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'edit') {
                  setState(() => isEditMode = true);
                  _textController.text = postData!['content'] ?? '';
                } else if (value == 'delete') {
                  _deletePost();
                }
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            PostCardWidget(
              postId: widget.postId,
              postData: postData!,
              userId: userId,
              showComments: true,
              onLike: _toggleLike,
              onAddComment: () => _addComment(_textController.text),
              commentController: _textController,
              toggleComments: () {},
              openGallery: (urls, index) {},
              onDelete: isOwner ? _deletePost : null,
            ),
            const SizedBox(height: 12),
            if (isEditMode)
              Column(
                children: [
                  TextField(
                    controller: _textController,
                    maxLines: null,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Edit Post',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _updatePost,
                    child: const Text('Update'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

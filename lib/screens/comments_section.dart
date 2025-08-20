import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:readmore/readmore.dart';
import 'post_detail_page.dart';

class CommentsSection extends StatefulWidget {
  final String postId;
  final String currentUserId;

  const CommentsSection({
    Key? key,
    required this.postId,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  static const int _kCommentsPerPage = 10;
  static const int _kMaxLength = 400;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _commentController = TextEditingController();

  DocumentSnapshot? _lastVisible;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  final List<DocumentSnapshot> _comments = [];

  final Map<String, bool> _showReplyField = {};
  final Map<String, TextEditingController> _replyCtrls = {};
  final Map<String, String?> _replyingToReplyId = {};
  final Map<String, List<DocumentSnapshot>> _loadedReplies = {};
  final Map<String, bool> _repliesExpanded = {};
  final Map<String, int> _replyCounts = {};

  // To prevent multiple rapid taps on send reply buttons
  final Set<String> _sendingReplies = {};

  // To prevent multiple rapid taps on send comment button
  bool _sendingComment = false;

  bool _showCommentsInputOnly = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final snap = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .orderBy('timestamp', descending: true)
        .limit(_kCommentsPerPage)
        .get();

    if (!mounted) return;
    setState(() {
      _comments.clear();
      _comments.addAll(snap.docs);
      _hasMore = snap.docs.length >= _kCommentsPerPage;
      _lastVisible = snap.docs.isNotEmpty ? snap.docs.last : null;
    });
  }

  Future<void> _loadMore() async {
    if (_lastVisible == null || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    final snap = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .orderBy('timestamp', descending: true)
        .startAfterDocument(_lastVisible!)
        .limit(_kCommentsPerPage)
        .get();

    if (!mounted) return;
    setState(() {
      _comments.addAll(snap.docs);
      _hasMore = snap.docs.length >= _kCommentsPerPage;
      _lastVisible = snap.docs.isNotEmpty ? snap.docs.last : _lastVisible;
      _isLoadingMore = false;
    });
  }

  Future<void> _addComment() async {
    if (_sendingComment) return; // prevent multiple sends
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    if (text.length > _kMaxLength) {
      _showSnack('Comment can be at most $_kMaxLength characters.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _sendingComment = true;
    });

    try {
      final commentData = {
        'userId': user.uid,
        'username': user.displayName ?? 'Anonymous',
        'comment': text,
        'timestamp': FieldValue.serverTimestamp(),
      };

      final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);
      final newDoc = await postRef.collection('comments').add(commentData);
      await postRef.update({
        'commentsCount': FieldValue.increment(1),
        'lastActivityAt': FieldValue.serverTimestamp(),
      });

      _commentController.clear();

      final newDocSnapshot = await newDoc.get();

      if (mounted) {
        setState(() {
          _comments.insert(0, newDocSnapshot);
          // Reset paging so new comment shows on top
          _lastVisible = _comments.last;
          _hasMore = _comments.length >= _kCommentsPerPage;
          _showCommentsInputOnly = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingComment = false;
        });
      }
    }
  }

  Future<void> _addReply(String commentId, {String? parentReplyId}) async {
    if (_sendingReplies.contains(commentId)) return; // prevent multiple sends for same comment
    final ctrl = _replyCtrls[commentId]!;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    if (text.length > _kMaxLength) {
      _showSnack('Reply can be at most $_kMaxLength characters.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _sendingReplies.add(commentId);
    });

    try {
      final repliesRef = FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc(commentId)
          .collection('replies');

      final replyData = {
        'userId': user.uid,
        'username': user.displayName ?? 'Anonymous',
        'reply': text,
        'timestamp': FieldValue.serverTimestamp(),
        'parentReplyId': parentReplyId,
      };

      final added = await repliesRef.add(replyData);

      final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);
      await postRef.update({'lastActivityAt': FieldValue.serverTimestamp()});

      final snap = await added.get();
      setState(() {
        _replyCounts[commentId] = (_replyCounts[commentId] ?? 0) + 1;
        final list = _loadedReplies.putIfAbsent(commentId, () => []);
        list.add(snap);
        ctrl.clear();

        _showReplyField[commentId] = false;
        _replyingToReplyId[commentId] = null;

        _repliesExpanded[commentId] = true;
      });
    } finally {
      setState(() {
        _sendingReplies.remove(commentId);
      });
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);
    await postRef.collection('comments').doc(commentId).delete();
    await postRef.update({'commentsCount': FieldValue.increment(-1)});
    if (!mounted) return;
    setState(() => _comments.removeWhere((d) => d.id == commentId));
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<int> _fetchReplyCount(String commentId) async {
    if (_replyCounts.containsKey(commentId)) return _replyCounts[commentId]!;
    final snap = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .get();
    final count = snap.docs.length;
    if (mounted) setState(() => _replyCounts[commentId] = count);
    return count;
  }

  Future<void> _loadReplies(String commentId) async {
    if (_loadedReplies.containsKey(commentId)) {
      setState(() {
        _repliesExpanded[commentId] = true;
      });
      return;
    }

    final snap = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .orderBy('timestamp', descending: false)
        .get();

    if (!mounted) return;
    setState(() {
      _loadedReplies[commentId] = snap.docs;
      _repliesExpanded[commentId] = true;
      _replyCounts[commentId] = snap.docs.length;
    });
  }

  Widget _buildRepliesFromLoaded(String commentId, Color primary) {
    final docs = _loadedReplies[commentId] ?? [];
    if (docs.isEmpty) return const SizedBox.shrink();

    final Map<String, DocumentSnapshot> byId = {};
    final Map<String?, List<DocumentSnapshot>> children = {};

    for (final d in docs) {
      byId[d.id] = d;
      final data = d.data() as Map<String, dynamic>;
      final parent = data['parentReplyId'] as String?;
      children.putIfAbsent(parent, () => []).add(d);
    }

    Widget buildReplyWidget(DocumentSnapshot doc, int indentLevel) {
      final r = doc.data() as Map<String, dynamic>;
      final replyId = doc.id;
      final isOwner = r['userId'] == widget.currentUserId;
      final avatarLetter = (r['username'] ?? '?').toString().isNotEmpty
          ? (r['username'] as String)[0]
          : '?';

      final replyChildren = children[replyId] ?? [];

      return Padding(
        padding: EdgeInsets.only(left: 16.0 * indentLevel, bottom: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(avatarLetter)),
              title: Text(isOwner ? 'You' : (r['username'] ?? '')),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReadMoreText(
                    r['reply'] ?? '',
                    trimLines: 3,
                    trimMode: TrimMode.Line,
                    trimCollapsedText: 'Read more',
                    trimExpandedText: 'Show less',
                    moreStyle: TextStyle(color: primary, fontWeight: FontWeight.bold),
                    lessStyle: TextStyle(color: primary, fontWeight: FontWeight.bold),
                  ),
                  if (r['parentReplyId'] != null)
                    Builder(builder: (ctx) {
                      final parentId = r['parentReplyId'] as String;
                      final parentDoc = byId[parentId];
                      final parentName =
                          parentDoc != null ? (parentDoc.data() as Map<String, dynamic>)['username'] ?? 'Someone' : 'Someone';
                      return Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text('In reply to $parentName', style: Theme.of(ctx).textTheme.bodySmall),
                      );
                    }),
                ],
              ),
              trailing: TextButton(
                onPressed: () {
                  setState(() {
                    final currently = _replyingToReplyId[commentId];
                    if (currently == replyId) {
                      _replyingToReplyId[commentId] = null;
                      _showReplyField[commentId] = false;
                    } else {
                      _replyingToReplyId[commentId] = replyId;
                      _showReplyField[commentId] = true;
                      _replyCtrls.putIfAbsent(commentId, () => TextEditingController());
                      _repliesExpanded[commentId] = true;
                    }
                  });
                },
                child: Text(_replyingToReplyId[commentId] == replyId ? 'Cancel' : 'Reply'),
              ),
            ),

            if (_replyingToReplyId[commentId] == replyId && (_showReplyField[commentId] ?? false))
              Padding(
                padding: const EdgeInsets.only(left: 56.0, right: 16.0, bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replyCtrls.putIfAbsent(commentId, () => TextEditingController()),
                        maxLength: _kMaxLength,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Write a reply...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: _sendingReplies.contains(commentId)
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: primary),
                            )
                          : Icon(Icons.send, color: primary),
                      onPressed: _sendingReplies.contains(commentId) ? null : () => _addReply(commentId, parentReplyId: replyId),
                    ),
                  ],
                ),
              ),

            if (replyChildren.isNotEmpty)
              Column(children: replyChildren.map((c) => buildReplyWidget(c, indentLevel + 1)).toList()),
          ],
        ),
      );
    }

    final topLevel = children[null] ?? [];
    return Column(children: topLevel.map((d) => buildReplyWidget(d, 0)).toList());
  }

  Widget _buildCommentsList(Color primary) {
    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _comments.length,
      itemBuilder: (_, i) {
        final doc = _comments[i];
        final data = doc.data() as Map<String, dynamic>;
        final cid = doc.id;
        final isOwner = data['userId'] == widget.currentUserId;
        _replyCtrls.putIfAbsent(cid, () => TextEditingController());
        _replyingToReplyId.putIfAbsent(cid, () => null);
        _repliesExpanded.putIfAbsent(cid, () => false);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text(data['username']?[0] ?? '?')),
                title: Text(data['userId'] == widget.currentUserId ? 'You' : (data['username'] ?? '')),
                subtitle: ReadMoreText(
                  data['comment'] ?? '',
                  trimLines: 3,
                  trimMode: TrimMode.Line,
                  trimCollapsedText: 'Read more',
                  trimExpandedText: 'Show less',
                  moreStyle: TextStyle(color: primary, fontWeight: FontWeight.bold),
                  lessStyle: TextStyle(color: primary, fontWeight: FontWeight.bold),
                ),
                trailing: isOwner
                    ? PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'delete') await _deleteComment(cid);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      )
                    : null,
              ),

              Padding(
                padding: const EdgeInsets.only(left: 56.0),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          final current = _showReplyField[cid] ?? false;
                          _showReplyField[cid] = !current;

                          if (_showReplyField[cid] == true) {
                            _replyingToReplyId[cid] = null;
                          }
                        });
                      },
                      child: Text((_showReplyField[cid] ?? false) ? 'Cancel' : 'Reply'),
                    ),

                    FutureBuilder<int>(
                      future: _fetchReplyCount(cid),
                      builder: (context, snapCount) {
                        final count = snapCount.data ?? _replyCounts[cid] ?? 0;
                        if (count == 0) return const SizedBox.shrink();
                        final expanded = _repliesExpanded[cid] ?? false;
                        return TextButton(
                          onPressed: () async {
                            if (!expanded) {
                              await _loadReplies(cid);
                            } else {
                              setState(() => _repliesExpanded[cid] = false);
                            }
                          },
                          child: Text(expanded ? 'Hide replies' : 'View $count replies'),
                        );
                      },
                    ),
                  ],
                ),
              ),

              if (_showReplyField[cid] == true && _replyingToReplyId[cid] == null)
                Padding(
                  padding: const EdgeInsets.only(left: 56.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replyCtrls[cid],
                          maxLength: _kMaxLength,
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'Write a reply...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: _sendingReplies.contains(cid)
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: primary),
                              )
                            : Icon(Icons.send, color: primary),
                        onPressed: _sendingReplies.contains(cid) ? null : () => _addReply(cid),
                      ),
                    ],
                  ),
                ),

              if (_repliesExpanded[cid] == true) _buildRepliesFromLoaded(cid, primary),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Button to toggle showing all comments (like "View all comments")
        if (!_showCommentsInputOnly)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailPage(postId: widget.postId),
                  ),
                );
              },
              child: const Text('View all comments'),
            ),
          ),

        if (_showCommentsInputOnly)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    maxLength: _kMaxLength,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: primary,
                  child: IconButton(
                      icon: _sendingComment
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendingComment ? null : _addComment),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showCommentsInputOnly = false;
                    });
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        maxLength: _kMaxLength,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Add a comment...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: primary,
                      child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _addComment),
                    ),
                  ],
                ),
              ),
              _buildCommentsList(primary),
              if (_isLoadingMore)
                const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
              if (_hasMore && !_isLoadingMore)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: ElevatedButton(
                      onPressed: _loadMore,
                      child: const Text('Load more comments'),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _commentController.dispose();
    for (final c in _replyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }
}

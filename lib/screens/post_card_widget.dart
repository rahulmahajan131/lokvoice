import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'comments_section.dart';
import 'package:readmore/readmore.dart';
import 'post_detail_page.dart'; // import for navigation to edit page

class PostCardWidget extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> postData;
  final String userId;

  // actions
  final VoidCallback onLike;
  final VoidCallback onAddComment;
  final TextEditingController commentController;
  final bool showComments;
  final VoidCallback toggleComments;
  final void Function(List<String> urls, int index) openGallery;

  // overflow‑menu callbacks
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  /// If `false`, any `.mp4` media will be hidden
  final bool allowVideo;

  const PostCardWidget({
    Key? key,
    required this.postId,
    required this.postData,
    required this.userId,
    required this.onLike,
    required this.onAddComment,
    required this.commentController,
    required this.showComments,
    required this.toggleComments,
    required this.openGallery,
    this.onDelete,
    this.onReport,
    this.onBlock,
    this.allowVideo = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final content       = postData['content'] ?? '';
    final rawUrls       = (postData['mediaUrls'] as List<dynamic>? ?? []).cast<String>();
    final mediaUrls     = allowVideo ? rawUrls : rawUrls.where((u) => !u.endsWith('.mp4')).toList();
    final likes         = (postData['likes'] ?? []) as List<dynamic>;
    final commentsCount = (postData['commentsCount'] ?? 0);
    final ts            = postData['timestamp'] as Timestamp?;
    final isOwner       = postData['userId'] == userId;
    final isLiked       = likes.contains(userId);

    String _format(Timestamp t) {
      final d = t.toDate();
      final diff = DateTime.now().difference(d);
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours   < 24) return '${diff.inHours}h ago';
      return '${d.day}/${d.month}/${d.year}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0,2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          ListTile(
            leading: const CircleAvatar(child: Text('U')),
            title: Text(
              isOwner ? 'You' : (postData['username'] ?? 'Anonymous'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(ts != null ? _format(ts) : 'Just now'),
            trailing: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  final hasActions = (isOwner) || (!isOwner && (onReport != null || onBlock != null));

                  if (!hasActions) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('No actions available')),
                    );
                    return;
                  }

                  showModalBottomSheet(
                    context: ctx,
                    builder: (_) => SafeArea(
                      child: Wrap(
                        children: [
                          if (isOwner)
                            ListTile(
                              leading: const Icon(Icons.edit, color: Colors.blue),
                              title: const Text('Edit Post'),
                              onTap: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  ctx,
                                  MaterialPageRoute(
                                    builder: (_) => PostDetailPage(
                                      postId: postId,
                                      isEditMode: true,
                                    ),
                                  ),
                                );
                              },
                            ),
                          if (isOwner && onDelete != null)
                            ListTile(
                              leading: const Icon(Icons.delete, color: Colors.red),
                              title: const Text('Delete Post'),
                              onTap: () { Navigator.pop(ctx); onDelete!(); },
                            ),
                          if (!isOwner && onReport != null)
                            ListTile(
                              leading: const Icon(Icons.report),
                              title: const Text('Report Post'),
                              onTap: () { Navigator.pop(ctx); onReport!(); },
                            ),
                          if (!isOwner && onBlock != null)
                            ListTile(
                              leading: const Icon(Icons.block),
                              title: const Text('Block User'),
                              onTap: () { Navigator.pop(ctx); onBlock!(); },
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // media gallery
          if (mediaUrls.isNotEmpty)
            SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: mediaUrls.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => openGallery(mediaUrls, i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: mediaUrls[i].endsWith('.mp4')
                          ? Container(
                              width: 200,
                              color: Colors.black12,
                              child: const Icon(Icons.play_circle, size: 48, color: Colors.blue),
                            )
                          : Image.network(mediaUrls[i], width: 200, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ),

          // post text
         if (content.isNotEmpty)
           Padding(
             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
             child: ReadMoreText(
               content,
               trimLines: 4,
               trimMode: TrimMode.Line,
               trimCollapsedText: 'Read more',
               trimExpandedText: 'Show less',
               style: const TextStyle(fontSize: 16),
               moreStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
               lessStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
             ),
           ),

          // like/comment row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                             color: isLiked ? Colors.blue : null),
                  onPressed: onLike,
                ),
                Text('${likes.length}'),
                const SizedBox(width: 20),
                IconButton(icon: const Icon(Icons.comment_outlined), onPressed: toggleComments),
                Text('$commentsCount'),
              ],
            ),
          ),

          // comments
          if (showComments)
            CommentsSection(postId: postId, currentUserId: userId),
        ],
      ),
    );
  }
}

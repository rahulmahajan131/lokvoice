import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../providers/circle_provider.dart';
import 'create_post_page.dart';
import 'footer_nav_bar.dart';
import 'post_card_widget.dart';
import 'post_detail_page.dart';
import 'news_content.dart';
import 'image_gallery_page.dart';
import 'quiz_page.dart';
import 'poll_page.dart';

class CreatePostBox extends StatelessWidget {
  const CreatePostBox({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.split(' ').first ?? 'You';
    final photoURL = user?.photoURL;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CreatePostPage(allowVideo: false)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundImage: photoURL != null ? NetworkImage(photoURL) : null,
              child: photoURL == null ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "What's on your mind, $name?",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
            ),
            Icon(Icons.edit, color: Theme.of(context).colorScheme.secondary),
          ],
        ),
      ),
    );
  }
}

class QuizPollRow extends StatelessWidget {
  const QuizPollRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) {
                      final circleData = context.read<CircleProvider>().circleData;
                      final state = circleData?['state'] ?? 'Madhya Pradesh';
                      return QuizPage(state: state);
                    },
                  ),
                );
              },
              icon: const Icon(Icons.quiz, color: Colors.white),
              label: const Text("Daily Quiz", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PollPage()));
              },
              icon: const Icon(Icons.poll, color: Colors.white),
              label: const Text("Poll", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  late String userId;
  List<String> _tabs = ['Local Feeds', 'News'];
  bool _initialized = false;

  final Map<String, bool> _showCommentsForPost = {};
  final Map<String, TextEditingController> _commentControllers = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;

    final circleProvider = context.watch<CircleProvider>();
    if (!circleProvider.isLoaded) return;

    userId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final circleData = circleProvider.circleData;
    final followedParties = circleProvider.followedParties;

    final state = circleData?['state'] ?? 'Madhya Pradesh';
    final district = circleData?['district'] ?? 'Delhi';

    FirebaseFirestore.instance
        .collection('parties')
        .where('state', isEqualTo: state)
        .where('district', isEqualTo: district)
        .get()
        .then((snap) {
      final activeParties = snap.docs.map((d) => d['name'] as String).toList();
      final visibleFollowed = followedParties.where(activeParties.contains).toList();
      final newTabs = ['Local Feeds', 'News', ...visibleFollowed];

      _tabController?.dispose();
      _tabController = TabController(length: newTabs.length, vsync: this);

      setState(() {
        _tabs = newTabs;
        _initialized = true;
      });
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _commentControllers.values.forEach((c) => c.dispose());
    super.dispose();
  }

  Query _postsQuery(Map<String, dynamic> circle, String tab) {
    var q = FirebaseFirestore.instance.collection('posts')
        .where('state', isEqualTo: circle['state'])
        .where('district', isEqualTo: circle['district']);

    if ((circle['pinCode'] ?? '').toString().isNotEmpty) {
      q = q.where('pinCode', isEqualTo: circle['pinCode']);
    }
    if (tab != 'Local Feeds' && tab != 'News') {
      q = q.where('tag', isEqualTo: tab);
    }
    return q.orderBy('timestamp', descending: true);
  }

  Future<void> _toggleLike(String postId, List<dynamic>? likes) async {
    final ref = FirebaseFirestore.instance.collection('posts').doc(postId);
    final liked = likes?.contains(userId) ?? false;
    await ref.update({
      'likes': liked
          ? FieldValue.arrayRemove([userId])
          : FieldValue.arrayUnion([userId]),
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _addComment(String postId) async {
    final ctl = _commentControllers[postId];
    if (ctl == null || ctl.text.trim().isEmpty) return;

    final refPost = FirebaseFirestore.instance.collection('posts').doc(postId);
    final refComm = refPost.collection('comments');

    await refComm.add({
      'userId': userId,
      'username': 'You',
      'comment': ctl.text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    });
    await refPost.update({'commentsCount': FieldValue.increment(1)});

    ctl.clear();
    setState(() => _showCommentsForPost[postId] = true);
  }

  void _openGallery(List<String> urls, int start) {}

  @override
  Widget build(BuildContext context) {
    final circleProv = context.watch<CircleProvider>();
    if (!circleProv.isLoaded || !_initialized || _tabController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final circle = circleProv.circleData!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LokVoice'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.map((t) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(t),
          )).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((tab) {
          if (tab == 'News') {
            final dist = circle['district'] ?? 'Delhi';
            final st = circle['state'] ?? 'Madhya Pradesh';
            return NewsContent(district: dist, state: st);
          }

          return StreamBuilder<QuerySnapshot>(
            stream: _postsQuery(circle, tab).snapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) return const Center(child: Text('Error loading posts'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final docs = snap.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length + 2, // CreatePostBox + QuizPollRow
                itemBuilder: (_, i) {
                  if (i == 0) return const QuizPollRow();
                  if (i == 1) return const CreatePostBox();

                  final d = docs[i - 2];
                  final map = d.data() as Map<String, dynamic>;
                  final isOwner = map['userId'] == userId;

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => PostDetailPage(postId: d.id)),
                      );
                    },
                    child: PostCardWidget(
                      postId: d.id,
                      postData: map,
                      userId: userId,
                      allowVideo: false,
                      onLike: () => _toggleLike(d.id, map['likes']),
                      onAddComment: () => _addComment(d.id),
                      commentController: _commentControllers.putIfAbsent(d.id, () => TextEditingController()),
                      showComments: _showCommentsForPost[d.id] ?? false,
                      toggleComments: () => setState(() {
                        _showCommentsForPost[d.id] = !(_showCommentsForPost[d.id] ?? false);
                      }),
                      openGallery: (urls, startIndex) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ImageGalleryPage(images: urls, initialIndex: startIndex),
                          ),
                        );
                      },
                      onDelete: isOwner
                          ? () async {
                              await FirebaseFirestore.instance.collection('posts').doc(d.id).delete();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Post deleted')),
                              );
                            }
                          : null,
                      onReport: !isOwner
                          ? () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Report Post'),
                                  content: const Text('Are you sure you want to report this post?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Report')),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await FirebaseFirestore.instance.collection('reports').add({
                                  'postId': d.id,
                                  'reportedBy': userId,
                                  'timestamp': FieldValue.serverTimestamp(),
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Post reported')),
                                );
                              }
                            }
                          : null,
                      onBlock: !isOwner
                          ? () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Block User'),
                                  content: const Text('Do you want to block this user? You won\'t see their posts anymore.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Block')),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('User blocked (demo)')),
                                );
                              }
                            }
                          : null,
                    ),
                  );
                },
              );
            },
          );
        }).toList(),
      ),
      bottomNavigationBar: FooterNavBar(
        selectedIndex: 0,
        onTap: (i) {
          const routes = ['/home', '/news', '/rate', '/party', '/profile'];
          if (i < routes.length) Navigator.pushReplacementNamed(context, routes[i]);
        },
      ),
    );
  }
}

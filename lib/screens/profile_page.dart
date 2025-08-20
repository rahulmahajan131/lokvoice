import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'post_detail_page.dart';
import 'post_card_widget.dart';
import 'footer_nav_bar.dart';
import '../providers/circle_provider.dart';
import 'circle_selection_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _selectedIndex = 4;
  Map<String, dynamic>? circleData;
  List<dynamic> followedParties = [];

  Future<List<Map<String, dynamic>>> _fetchUserPosts(String uid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('posts')
        .where('userId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(5)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['postId'] = doc.id;
      return data;
    }).toList();
  }

  Future<void> _fetchUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = userDoc.data();
    if (data != null) {
      setState(() {
        circleData = data['circle'];
        followedParties = data['followedParties'] ?? [];
      });
    }
  }

  void _onFooterTap(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);

    const routes = ['/home', '/news', '/rate', '/party', '/profile'];
    if (index < routes.length) Navigator.pushReplacementNamed(context, routes[index]);
  }

  @override
  void initState() {
    super.initState();
    _fetchUserInfo();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final cardColor = theme.cardColor;

    if (user == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('My Profile'),
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
        ),
        body: Center(
          child: Text('No user logged in', style: theme.textTheme.bodyLarge),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchUserPosts(user.uid),
        builder: (context, snapshot) {
          final posts = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile info
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundImage:
                            user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                        child: user.photoURL == null
                            ? const Icon(Icons.person, size: 48, color: Colors.white)
                            : null,
                        backgroundColor: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user.displayName ?? 'Anonymous',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        user.email ?? '',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Circle info
                if (circleData != null)
                  Card(
                    color: cardColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: const Icon(Icons.location_on),
                      title: const Text('Your Circle'),
                      subtitle: Text(
                        '${circleData!['district']}, ${circleData!['state']}' +
                            (circleData!['pinCode'] != null
                                ? ' - ${circleData!['pinCode']}'
                                : ''),
                        style: theme.textTheme.bodyMedium,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CircleSelectionPage()),
                          );
                        },
                      ),
                    ),
                  ),

                // Followed parties
                if (followedParties.isNotEmpty)
                  Card(
                    color: cardColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: const Icon(Icons.flag),
                      title: const Text('Parties You Follow'),
                      subtitle: Text(
                        followedParties.join(', '),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),

                const SizedBox(height: 20),
                Text(
                  'Latest Posts',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                if (snapshot.connectionState == ConnectionState.waiting)
                  Center(child: CircularProgressIndicator(color: primaryColor))
                else if (posts.isEmpty)
                  Text('You haven’t posted anything yet.', style: theme.textTheme.bodyMedium)
                else
                  Column(
                    children: posts.map((post) {
                      final postId = post['postId'] as String;

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PostDetailPage(postId: postId),
                            ),
                          ).then((_) => setState(() {})); // refresh posts after return
                        },
                        child: PostCardWidget(
                          postId: postId,
                          postData: post,
                          userId: user.uid,
                          onLike: () {}, // optional
                          onAddComment: () {}, // optional
                          commentController: TextEditingController(),
                          showComments: false,
                          toggleComments: () {},
                          openGallery: (urls, index) {},
                          onDelete: null, // delete handled in PostDetailPage
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: FooterNavBar(
        selectedIndex: _selectedIndex,
        onTap: _onFooterTap,
      ),
    );
  }
}

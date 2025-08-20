import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/circle_provider.dart';
import 'footer_nav_bar.dart';
import 'party_feed_page.dart';

class PartyFollowPage extends StatefulWidget {
  const PartyFollowPage({Key? key}) : super(key: key);

  @override
  State<PartyFollowPage> createState() => _PartyFollowPageState();
}

class _PartyFollowPageState extends State<PartyFollowPage> {
  List<Map<String, dynamic>> _allParties = [];
  List<bool> _expandedList = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  Future<void> _loadParties() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final circleData = context.read<CircleProvider>().circleData;
      if (circleData == null) {
        setState(() {
          _error = 'Circle data not set.';
          _loading = false;
        });
        return;
      }

      final state = circleData['state'] as String;
      final district = circleData['district'] as String;

      final querySnapshot = await FirebaseFirestore.instance
          .collection('parties')
          .where('state', isEqualTo: state)
          .where('district', isEqualTo: district)
          .get();

      final parties = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'Unknown',
        };
      }).toList();

      setState(() {
        _allParties = parties;
        _expandedList = List<bool>.filled(parties.length, false);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load parties: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CircleProvider>();
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (_loading) {
      return _buildScaffold(const Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return _buildScaffold(Center(child: Text(_error!)));
    }

    if (_allParties.isEmpty) {
      return _buildScaffold(const Center(child: Text('No active parties found in your area.')));
    }

    return _buildScaffold(
      ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _allParties.length,
        itemBuilder: (context, index) {
          final partyId = _allParties[index]['id'];

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('parties').doc(partyId).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              if (data == null) return const SizedBox.shrink();

              final partyName = data['name'] ?? 'Unknown';
              final isFollowed = provider.isFollowing(partyName);
              final followers = data['followers'] as List<dynamic>? ?? [];
              final followersCount = followers.length;
              final expanded = _expandedList[index];

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PartyFeedPage(partyId: partyId, partyName: partyName),
                    ),
                  );
                },
                child: Card(
                  color: theme.cardColor,
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundImage: data['logoUrl'] != null && data['logoUrl'] != ''
                                  ? NetworkImage(data['logoUrl'])
                                  : null,
                              child: (data['logoUrl'] == null || data['logoUrl'] == '')
                                  ? const Icon(Icons.flag, size: 28)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    partyName,
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$followersCount follower${followersCount == 1 ? '' : 's'}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                              onPressed: () {
                                setState(() {
                                  _expandedList[index] = !_expandedList[index];
                                });
                              },
                            ),
                          ],
                        ),
                        if (expanded && data['description'] != null && data['description'].toString().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            data['description'],
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isFollowed ? Colors.red : primaryColor,
                              side: BorderSide(color: isFollowed ? Colors.red : primaryColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                            onPressed: () async {
                              final docRef = FirebaseFirestore.instance.collection('parties').doc(partyId);

                              await FirebaseFirestore.instance.runTransaction((transaction) async {
                                final snapshot = await transaction.get(docRef);
                                final data = snapshot.data() as Map<String, dynamic>;
                                final currentFollowers = List<String>.from(data['followers'] ?? []);

                                if (isFollowed) {
                                  currentFollowers.remove(userId);
                                  provider.unfollowParty(partyName);
                                } else {
                                  currentFollowers.add(userId);
                                  provider.followParty(partyName);
                                }

                                transaction.update(docRef, {'followers': currentFollowers});
                              });
                            },
                            icon: Icon(isFollowed ? Icons.remove_circle : Icons.add_circle),
                            label: Text(isFollowed ? 'Unfollow' : 'Follow'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Scaffold _buildScaffold(Widget bodyContent) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'My Parties',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        automaticallyImplyLeading: false,
        backgroundColor: theme.colorScheme.primary,
        centerTitle: true,
        elevation: 2,
      ),
      body: bodyContent,
      bottomNavigationBar: FooterNavBar(
                    selectedIndex: 3,
                    onTap: (i) {
                      const routes = ['/home', '/news', '/rate', '/party', '/profile'];
                      if (i < routes.length) Navigator.pushReplacementNamed(context, routes[i]);
            },
      ),
    );
  }
}
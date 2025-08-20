import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PartyFeedPage extends StatelessWidget {
  final String partyId;
  final String partyName;

  const PartyFeedPage({required this.partyId, required this.partyName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$partyName Feeds'), automaticallyImplyLeading: false),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .where('party', isEqualTo: partyName)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final posts = snapshot.data!.docs;
          if (posts.isEmpty) return const Center(child: Text('No posts from this party yet.'));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final data = posts[index].data() as Map<String, dynamic>;
              final text = data['text'] ?? '';
              final username = data['username'] ?? 'Unknown';
              final mediaUrl = data['mediaPath'];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(text),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('by $username'),
                      if (mediaUrl != null && mediaUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Image.network(
                            mediaUrl,
                            errorBuilder: (context, error, stackTrace) => const SizedBox(),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
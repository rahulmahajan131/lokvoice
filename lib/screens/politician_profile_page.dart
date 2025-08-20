import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class PoliticianProfilePage extends StatelessWidget {
  final String politicianId;

  const PoliticianProfilePage({super.key, required this.politicianId});

  void _launchURL(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(content, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Politician Profile')),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('politicians')
            .doc(politicianId)
            .get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage: data['photoUrl'] != null && data['photoUrl'].isNotEmpty
                        ? NetworkImage(data['photoUrl'])
                        : null,
                    child: data['photoUrl'] == null || data['photoUrl'].isEmpty
                        ? const Icon(Icons.person, size: 40)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: [
                      Text(
                        data['name'] ?? 'Unknown',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        data['position'] ?? '',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      Text('Party: ${data['party'] ?? ''}',
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (data['twitter'] != null && data['twitter'].isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.alternate_email, color: Colors.blue),
                        onPressed: () => _launchURL(data['twitter']),
                      ),
                    if (data['facebook'] != null && data['facebook'].isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.facebook, color: Colors.blue),
                        onPressed: () => _launchURL(data['facebook']),
                      ),
                    if (data['wikipedia'] != null && data['wikipedia'].isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.public, color: Colors.blueGrey),
                        onPressed: () => _launchURL(data['wikipedia']),
                      ),
                  ],
                ),
                const Divider(height: 32),
                if (data['workHistory'] != null && data['workHistory'].isNotEmpty)
                  _buildSection('Work History', data['workHistory']),
                if (data['education'] != null && data['education'].isNotEmpty)
                  _buildSection('Education', data['education']),
              ],
            ),
          );
        },
      ),
    );
  }
}

// lib/screens/poll_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../providers/circle_provider.dart';
import '../utils/state_languages.dart';

class PollPage extends StatefulWidget {
  const PollPage({Key? key}) : super(key: key);

  @override
  State<PollPage> createState() => _PollPageState();
}

class _PollPageState extends State<PollPage> {
  bool isLoading = true;
  String? errorMessage;
  Map<String, dynamic>? pollData;
  String? userVote;
  final String openAIApiKey = "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"; // 🔹 Replace with your OpenAI key

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => fetchPoll());
  }

  Future<void> fetchPoll() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final circleData = context.read<CircleProvider>().circleData;
      final state = circleData?['state'] ?? 'Madhya Pradesh';
      final langCode = stateLanguages[state] ?? 'hi';
      final now = DateTime.now();

      final pollRef = FirebaseFirestore.instance.collection('state_polls').doc(state);
      final doc = await pollRef.get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          final Timestamp? createdAt = data['createdAt'] as Timestamp?;
          if (createdAt != null && now.difference(createdAt.toDate()).inDays < 5) {
            pollData = Map<String, dynamic>.from(data);
            final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
            final votes = (pollData?['votes'] ?? {}) as Map;
            userVote = votes[userId] as String?;
            setState(() => isLoading = false);
            return;
          }
        }
      }

      // If no poll or expired, generate new poll from AI
      final newPoll = await generatePollAI(state, langCode);
      await pollRef.set({
        'question': newPoll['question'],
        'options': newPoll['options'],
        'votes': {},
        'createdAt': FieldValue.serverTimestamp(),
      });
      pollData = newPoll;
      userVote = null;
      setState(() => isLoading = false);
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.toString();
      });
      debugPrint("Poll fetch error: $e");
    }
  }

  Future<Map<String, dynamic>> generatePollAI(String state, String langCode) async {
    final url = Uri.parse("https://api.openai.com/v1/chat/completions");
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $openAIApiKey",
    };
    final body = jsonEncode({
      "model": "gpt-4o-mini",
      "messages": [
        {
          "role": "system",
          "content": "You are a poll generator for Indian news and politics. Return only valid JSON."
        },
        {
          "role": "user",
          "content": "Create a poll about current hot topic in ${state} politics in simple $langCode language. "
              "Provide 'question' and 'options' (2 options). Return JSON like {\"question\":\"...\",\"options\":[\"...\",\"...\"]}"
        }
      ],
      "temperature": 0.7
    });

    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 200) {
      String content = jsonDecode(response.body)['choices'][0]['message']['content'];
      content = content.replaceAll(RegExp(r'```'), '').trim();
      return Map<String, dynamic>.from(jsonDecode(content));
    } else {
      throw Exception("Failed to fetch poll from AI: ${response.body}");
    }
  }

  Future<void> vote(int index) async {
    if (pollData == null) return;
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userVote != null) return; // already voted

    final selectedOption = pollData!['options'][index] as String;

    // Update vote in Firebase
    final pollRef = FirebaseFirestore.instance
        .collection('state_polls')
        .doc(context.read<CircleProvider>().circleData?['state'] ?? 'Madhya Pradesh');

    await pollRef.update({
      'votes.$userId': selectedOption,
    });

    setState(() {
      userVote = selectedOption;
      (pollData!['votes'] as Map)[userId] = selectedOption;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Text("Error: $errorMessage", style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    if (pollData == null) {
      return const Scaffold(
        body: Center(child: Text("No poll available")),
      );
    }

    final options = List<String>.from(pollData!['options'] ?? []);
    final votesMap = Map<String, dynamic>.from(pollData!['votes'] ?? {});
    final voteCounts = <String, int>{};
    for (var opt in options) {
      voteCounts[opt] = votesMap.values.where((v) => v == opt).length;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Hot State Poll"),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pollData!['question'] ?? "", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...List.generate(options.length, (i) {
              final option = options[i];
              final isSelected = userVote == option;
              return Card(
                color: isSelected ? Colors.green.shade300 : Colors.white,
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  title: Text(option, style: const TextStyle(fontSize: 18)),
                  trailing: Text(voteCounts[option].toString()),
                  onTap: () => vote(i),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

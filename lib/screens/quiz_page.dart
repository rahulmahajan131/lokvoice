// lib/screens/quiz_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../utils/state_languages.dart';

class QuizPage extends StatefulWidget {
  final String state; // pass user's state here

  const QuizPage({Key? key, required this.state}) : super(key: key);

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  bool isLoading = true;
  String? errorMessage;
  List<Map<String, dynamic>> questions = [];
  int currentQuestionIndex = 0;
  int? selectedIndex;
  bool showAnswer = false;

  final openAIApiKey = "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";

  @override
  void initState() {
    super.initState();
    loadQuiz();
  }

  Future<void> loadQuiz() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final quizRef =
          FirebaseFirestore.instance.collection('quizzes').doc(widget.state);
      final doc = await quizRef.get();

      final now = DateTime.now();

      if (doc.exists) {
        final data = doc.data()!;
        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
        if (timestamp != null &&
            now.difference(timestamp).inHours < 24 &&
            data['questions'] != null) {
          // Use cached quiz
          questions = List<Map<String, dynamic>>.from(data['questions']);
          setState(() {
            isLoading = false;
          });
          return;
        }
      }

      // Fetch new quiz from OpenAI
      await generateQuizFromAI();

      // Save to Firestore
      await quizRef.set({
        'questions': questions,
        'timestamp': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> generateQuizFromAI() async {
    final languageCode = stateLanguages[widget.state] ?? 'hi';
    final url = Uri.parse("https://api.openai.com/v1/chat/completions");

    final body = jsonEncode({
      "model": "gpt-4o-mini",
      "messages": [
        {
          "role": "system",
          "content":
              "You are a quiz generator for an Indian audience. Return ONLY valid JSON array without extra text."
        },
        {
          "role": "user",
          "content":
              "Generate 5 multiple-choice quiz questions about Indian civic sense, politics, and general knowledge. "
              "Use simple language for people from ${widget.state} and write all questions in $languageCode. "
              "Each question should have 'question', 4 'options', 'correctAnswer', and a short 'explanation'. "
              "Return ONLY a JSON array like [{\"question\":..., \"options\":[...], \"correctAnswer\":..., \"explanation\":...}]"
        }
      ],
      "temperature": 0.7
    });

    final response =
        await http.post(url, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $openAIApiKey",
    }, body: body);

    if (response.statusCode == 200) {
      String content = jsonDecode(response.body)['choices'][0]['message']
          ['content']
          .toString();
      content = content.replaceAll(RegExp(r'```json'), '')
          .replaceAll(RegExp(r'```'), '')
          .trim();
      final parsed = jsonDecode(content) as List;
      questions = parsed.map((q) => Map<String, dynamic>.from(q)).toList();
      setState(() {
        isLoading = false;
      });
    } else {
      throw Exception("Failed to fetch quiz: ${response.body}");
    }
  }

  void answerQuestion(int index) {
    if (showAnswer) return;

    setState(() {
      selectedIndex = index;
      showAnswer = true;
    });

    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        showAnswer = false;
        selectedIndex = null;
        if (currentQuestionIndex < questions.length - 1) {
          currentQuestionIndex++;
        } else {
          showDialog(
              context: context,
              builder: (_) => AlertDialog(
                    title: const Text("Quiz Completed"),
                    content: Text(
                        "You completed the quiz! (${questions.length} questions)"),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Close"))
                    ],
                  ));
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    if (errorMessage != null) {
      return Scaffold(
          body: Center(
              child:
                  Text("Error: $errorMessage", style: const TextStyle(color: Colors.red))));
    }

    final currentQuestion = questions[currentQuestionIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.state} Quiz"),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: (currentQuestionIndex + 1) / questions.length,
              backgroundColor: Colors.grey[300],
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 16),
            Text(
              "Question ${currentQuestionIndex + 1} of ${questions.length}",
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              currentQuestion['question'],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...List.generate(
              (currentQuestion['options'] as List).length,
              (index) {
                final optionText = currentQuestion['options'][index];
                Color? color;
                if (showAnswer) {
                  if (optionText == currentQuestion['correctAnswer']) {
                    color = Colors.green.shade300;
                  } else if (selectedIndex == index) {
                    color = Colors.red.shade300;
                  }
                }
                return GestureDetector(
                  onTap: () => answerQuestion(index),
                  child: Card(
                    color: color,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(optionText, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                );
              },
            ),
            if (showAnswer)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  "व्याख्या: ${currentQuestion['explanation']}",
                  style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

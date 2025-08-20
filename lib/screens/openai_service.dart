import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenAIService {
  final String apiKey = "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"; // 🔑 replace with your key


Future<Map<String, dynamic>> generatePoll(String state) async {
  final prompt = """
  Create a political poll in the local language of $state.
  Output JSON only in this format:
  {
    "topic": "<hot political topic in $state>",
    "poll1": "Was this right or wrong?",
    "poll2": "What should be improved for progress?"
  }
  """;

  final response = await _chat([
    {"role": "system", "content": "You are a political poll generator."},
    {"role": "user", "content": prompt}
  ]);

  return jsonDecode(response);
}

  Future<Map<String, dynamic>?> generateQuiz(String state) async {
    final url = Uri.parse("https://api.openai.com/v1/chat/completions");

    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $apiKey",
    };

    final body = jsonEncode({
      "model": "gpt-4o-mini", // fast + cheap
      "messages": [
        {
          "role": "system",
          "content":
              "You are a quiz generator. ONLY return valid JSON. No markdown, no extra text."
        },
        {
          "role": "user",
          "content": """
Generate 5 multiple-choice quiz questions about politics, geography, or culture of $state.
Return ONLY JSON in this exact format:

{
  "questions": [
    {
      "question": "string",
      "options": ["A", "B", "C", "D"],
      "answer": "A"
    }
  ]
}
"""
        }
      ],
      "temperature": 0.7,
    });

    final response = await http.post(url, headers: headers, body: body);

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        final rawText = data['choices'][0]['message']['content'];

        // 🛠 Clean up response (remove markdown, newlines)
        String cleaned = rawText
            .replaceAll("```json", "")
            .replaceAll("```", "")
            .trim();

        return jsonDecode(cleaned);
      } catch (e) {
        print("❌ JSON parsing error: $e");
        return null;
      }
    } else {
      print("❌ OpenAI API error: ${response.body}");
      return null;
    }
  }
}

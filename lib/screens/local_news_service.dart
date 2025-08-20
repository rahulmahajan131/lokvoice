import 'dart:convert';
import 'package:http/http.dart' as http;

class LocalNewsService {
  final String apiKey = 'pub_1307c30015c246589fd4b8e7e3b673c1'; // Replace with your real key

  Future<List<dynamic>> fetchNews(String districtName) async {
    final url = Uri.parse(
      'https://newsdata.io/api/1/news?apikey=$apiKey&q=$districtName&country=in',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to fetch news');
    }
  }
}
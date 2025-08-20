import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class NewsContent extends StatefulWidget {
  final String district;
  final String state;

  const NewsContent({Key? key, required this.district, required this.state}) : super(key: key);

  @override
  State<NewsContent> createState() => _NewsContentState();
}

class _NewsContentState extends State<NewsContent> {
  List<Article> _articles = [];
  bool _loading = true;
  String? _error;

  final _functionBaseUrl = "asia-south1-lokvoice.cloudfunctions.net";

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  Future<void> _loadNews() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.https(
        _functionBaseUrl,
        "/getDistrictNews",
        {
          'state': widget.state,
          'district': widget.district,
        },
      );

      final response = await http.get(uri);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final articles = data.map((e) => Article.fromJson(e)).toList();
        if (mounted) {
          setState(() => _articles = articles);
        }
      } else if (response.statusCode == 400) {
        if (mounted) {
          setState(() => _error = 'Invalid request. Missing or incorrect district/state.');
        }
      } else if (response.statusCode == 502) {
        if (mounted) {
          setState(() => _error = 'News service is temporarily unavailable. Try again later.');
        }
      } else if (response.statusCode == 500) {
        if (mounted) {
          setState(() => _error = 'Internal server error. Please retry.');
        }
      } else {
        if (mounted) {
          setState(() => _error = 'Failed to load news. (Code: ${response.statusCode})');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not connect to the server. Please check your internet.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the news article')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                onPressed: _loadNews,
              ),
            ],
          ),
        ),
      );
    }

    if (_articles.isEmpty) {
      return const Center(child: Text('No news articles available at the moment.'));
    }

    return RefreshIndicator(
      onRefresh: _loadNews,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _articles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final article = _articles[index];
          return Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _launchUrl(article.url),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (article.urlToImage != null)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: Image.network(
                        article.urlToImage!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 180,
                          width: double.infinity,
                          color: Colors.grey[300],
                          alignment: Alignment.center,
                          child: const Icon(Icons.image_not_supported),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          article.sourceName ?? '',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class Article {
  final String title;
  final String url;
  final String? urlToImage;
  final String? sourceName;

  Article({
    required this.title,
    required this.url,
    this.urlToImage,
    this.sourceName,
  });

  factory Article.fromJson(Map<String, dynamic> json) {
    return Article(
      title: json['title'] ?? 'No title',
      url: json['link'] ?? json['url'] ?? '',
      urlToImage: json['image_url'] ?? json['urlToImage'],
      sourceName: json['source_id'] ?? json['sourceName'],
    );
  }
}

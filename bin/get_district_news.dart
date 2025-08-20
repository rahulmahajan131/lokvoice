// functions/bin/get_district_news.dart
import 'dart:convert';
import 'package:functions_framework/functions_framework.dart';
import 'package:firebase_admin/firebase_admin.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// 🔑 Your NewsData.io API key (keep it secret on server)
const String _newsApiKey = 'pub_3f7f7aae73f042279ddf1faa6901f1d4';

/// Cache TTL
const Duration _cacheExpiry = Duration(days: 1);

/// Very small state→language map (add the rest of India’s states as needed)
const Map<String, String> _stateLanguages = {
  'Madhya Pradesh': 'hi',
  'Maharashtra': 'mr',
  'Karnataka': 'kn',
  'Tamil Nadu': 'ta',
  'Kerala': 'ml',
  // default -> 'en'
};

FirebaseApp? _app;
FirebaseFirestore get _firestore {
  _app ??= FirebaseAdmin.instance.initializeApp(
    AppOptions(
      credential: FirebaseAdmin.instance.certFromPath('service-account.json'),
    ),
  );
  return FirebaseFirestore.instanceFor(app: _app!);
}

/// HTTP entry point:
@CloudFunction()
Future<Response> getDistrictNews(Request req) async {
  final params = req.url.queryParameters;
  final state = params['state']?.trim();
  final district = params['district']?.trim();

  if (state == null || district == null) {
    return Response('Missing "state" or "district" query params', 400);
  }

  final cacheDocId =
      '${state.toLowerCase()}_${district.toLowerCase()}'.replaceAll(' ', '_');
  final docRef = _firestore.collection('news_cache').doc(cacheDocId);

  // ── 1. Check Firestore cache ───────────────────────────────────────────────
  final snapshot = await docRef.get();
  final now = DateTime.now();

  if (snapshot.exists) {
    final data = snapshot.data()! as Map<String, dynamic>;
    final ts = (data['updatedAt'] as Timestamp).toDate();
    if (now.difference(ts) < _cacheExpiry) {
      // ✔ Serve cached articles
      return Response(jsonEncode(data['articles']),
          200, headers: {'Content-Type': 'application/json'});
    }
  }

  // ── 2. Cache expired → fetch from NewsData.io ──────────────────────────────
  final language = _stateLanguages[state] ?? 'en';

  final uri = Uri.https('newsdata.io', '/api/1/news', {
    'apikey': _newsApiKey,
    'language': language,
    'country': 'in',
    'q': district,
  });

  final apiRes = await http.get(uri);

  if (apiRes.statusCode != 200) {
    return Response('NewsData API error ${apiRes.statusCode}', 502);
  }

  final apiJson = jsonDecode(apiRes.body);
  if (apiJson['status'] != 'success' || apiJson['results'] == null) {
    return Response('Unexpected NewsData response', 502);
  }

  final articles = apiJson['results'];

  // ── 3. Save to Firestore cache ─────────────────────────────────────────────
  await docRef.set({
    'articles': articles,
    'updatedAt': Timestamp.fromDate(now),
  });

  return Response(jsonEncode(articles), 200,
      headers: {'Content-Type': 'application/json'});
}
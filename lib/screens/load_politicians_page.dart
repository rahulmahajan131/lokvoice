// lib/screens/load_politicians_page.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:cloud_firestore/cloud_firestore.dart';

/// One-time importer & cleaner for MyNeta -> Firestore (Cloudinary for images).
///
/// Usage (dev only):
///  - Set CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET below.
///  - Make main.dart open this page (dev run).
///  - Optionally Delete existing district docs first using the red button.
///  - Run import, check Firestore & Cloudinary, then remove this page.
class LoadPoliticiansPage extends StatefulWidget {
  final String statePage;      // e.g. "MadhyaPradesh2023"
  final String constituencyId; // e.g. "39"
  final String districtName;   // e.g. "Burhanpur"
  final String stateName;      // e.g. "Madhya Pradesh"

  const LoadPoliticiansPage({
    Key? key,
    required this.statePage,
    required this.constituencyId,
    required this.districtName,
    required this.stateName,
  }) : super(key: key);

  @override
  State<LoadPoliticiansPage> createState() => _LoadPoliticiansPageState();
}

class _LoadPoliticiansPageState extends State<LoadPoliticiansPage> {
  // === CONFIG: set these before running ===
  static const String CLOUDINARY_CLOUD_NAME = 'dmz3wul2h';
  static const String CLOUDINARY_UPLOAD_PRESET = 'lokvoice_politicians';
  // === end config ===

  final String myNetaBase = 'https://myneta.info/';
  final List<String> _messages = [];
  bool _loading = false;

  void _addMessage(String m, {bool printToConsole = true}) {
    final ts = DateTime.now().toIso8601String();
    final msg = '[$ts] $m';
    if (printToConsole) print(msg);
    setState(() {
      _messages.insert(0, msg);
      if (_messages.length > 800) _messages.removeLast();
    });
  }

  String _sanitizeFilename(String input) =>
      input.replaceAll(RegExp(r'[^\w\-\. ]'), '_').replaceAll(' ', '_');

  // ----- Delete existing records for a district -----
  Future<void> _deleteDistrictRecords(String districtName) async {
    setState(() => _loading = true);
    _addMessage('Starting delete for district="$districtName"');
    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore
          .collection('politicians')
          .where('district', isEqualTo: districtName)
          .get();

      if (snapshot.docs.isEmpty) {
        _addMessage('No documents found for district="$districtName"');
        setState(() => _loading = false);
        return;
      }

      int deleted = 0;
      for (final doc in snapshot.docs) {
        try {
          await firestore.collection('politicians').doc(doc.id).delete();
          deleted += 1;
          _addMessage('Deleted doc ${doc.id}');
        } catch (e) {
          _addMessage('Failed to delete ${doc.id}: $e', printToConsole: true);
        }
      }
      _addMessage('Delete complete — total deleted: $deleted');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $deleted docs for $districtName')),
      );
    } catch (e) {
      _addMessage('Fatal delete error: $e', printToConsole: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  // ----- Helpers for parsing -----
  String _extractLabelFromText(String pageText, String label) {
    try {
      final re = RegExp(r'(?im)' + RegExp.escape(label) + r'\s*[:\-\u2013]\s*([^\n\r]+)');
      final m = re.firstMatch(pageText);
      if (m != null) return m.group(1)?.trim() ?? '';
    } catch (e) {
      _addMessage('extractLabelFromText error for "$label": $e', printToConsole: true);
    }
    return '';
  }

  String _extractSectionBlock(dom.Document doc, String heading) {
    try {
      final bodyText = doc.body?.text ?? '';
      final pattern = RegExp('(?i)${RegExp.escape(heading)}\\s*\\n([\\s\\S]*?)(\\n\\s*\\n|\\n[A-Z][a-z])', dotAll: true);
      final m = pattern.firstMatch(bodyText);
      if (m != null) return m.group(1)?.trim() ?? '';
    } catch (e) {
      _addMessage('extractSectionBlock error for "$heading": $e', printToConsole: true);
    }
    return '';
  }

  Future<String?> _uploadToCloudinary(Uint8List bytes, String fileName) async {
    try {
      final uri = Uri.parse('https://api.cloudinary.com/v1_1/$CLOUDINARY_CLOUD_NAME/image/upload');
      final request = http.MultipartRequest('POST', uri);
      request.fields['upload_preset'] = CLOUDINARY_UPLOAD_PRESET;
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
      _addMessage('Uploading to Cloudinary: $fileName');
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final Map<String, dynamic> j = json.decode(resp.body);
        final secureUrl = j['secure_url'] as String?;
        _addMessage('Cloudinary uploaded: $secureUrl');
        return secureUrl;
      } else {
        _addMessage('Cloudinary upload failed: ${resp.statusCode} ${resp.body}', printToConsole: true);
        return null;
      }
    } catch (e) {
      _addMessage('Cloudinary upload error: $e', printToConsole: true);
      return null;
    }
  }

  // ----- Robust candidate detail parser -----
  Future<Map<String, dynamic>> _parseCandidateDetail(String detailUrl) async {
    final result = <String, dynamic>{};
    try {
      _addMessage('GET detail: $detailUrl');
      final resp = await http.get(Uri.parse(detailUrl));
      _addMessage('Detail HTTP status: ${resp.statusCode}');
      if (resp.statusCode != 200) {
        _addMessage('Detail page HTTP ${resp.statusCode}', printToConsole: true);
        return result;
      }

      final doc = html_parser.parse(resp.body);
      // normalize br => newline spans to keep text extraction easier
      doc.querySelectorAll('br').forEach((b) => b.replaceWith(dom.Element.tag('span')..text = '\n'));

      final pageTextRaw = doc.body?.text ?? '';
      final pageText = pageTextRaw.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'\s+\n'), '\n');

      // NAME: prefer headers, else strong/b, else first meaningful line
      String name = '';
      final header = doc.querySelector('h1, h2, h3, h4');
      if (header != null) name = header.text.trim();
      if (name.isEmpty) {
        final strong = doc.querySelector('b, strong');
        if (strong != null) name = strong.text.trim();
      }
      if (name.isEmpty) {
        final lines = pageText.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (lines.isNotEmpty) name = lines.first;
      }
      // clean parentheses like (Winner)
      name = name.replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').trim();

      // LABELS: party, age, assets, liabilities
      final party = _extractLabelFromText(pageText, 'Party');
      final age = _extractLabelFromText(pageText, 'Age');
      String totalAssets = _extractLabelFromText(pageText, 'Assets');
      if (totalAssets.isEmpty) totalAssets = _extractLabelFromText(pageText, 'Total Assets');
      final liabilities = _extractLabelFromText(pageText, 'Liabilities');

      // EDUCATION: try section block then label fallback
      String education = _extractSectionBlock(doc, 'Educational');
      if (education.isEmpty) education = _extractLabelFromText(pageText, 'Education');

      // POSITION heuristics
      String position = '';
      final posMatch = RegExp(r'(?i)(Position|Current Position|Designation)[:\-\s]*([^\n]+)').firstMatch(pageText);
      if (posMatch != null) position = posMatch.group(2)?.trim() ?? '';
      else {
        final heur = RegExp(r'(?i)(Former\s+[A-Za-z ]+|President[, A-Za-z ]+|Member of the [A-Za-z ]+)');
        final hm = heur.firstMatch(pageText);
        if (hm != null) position = hm.group(0)!.trim();
      }

      // PDF links
      final pdfs = <String>[];
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = (a.attributes['href'] ?? '').trim();
        if (href.isEmpty) continue;
        final lower = href.toLowerCase();
        if (lower.endsWith('.pdf') || href.contains('docs.myneta.info') || lower.contains('affidavit')) {
          final url = href.startsWith('http') ? href : '$myNetaBase${widget.statePage}/$href';
          if (!pdfs.contains(url)) pdfs.add(url);
        }
      }

      // IMAGE: pick first jpg/png; resolve relative
      String? imageUrl;
      for (final img in doc.querySelectorAll('img[src]')) {
        final src = img.attributes['src'] ?? '';
        if (src.isEmpty) continue;
        final lower = src.toLowerCase();
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png')) {
          String resolved = src;
          if (!resolved.startsWith('http')) {
            if (resolved.startsWith('/')) resolved = '$myNetaBase$resolved';
            else resolved = '$myNetaBase${widget.statePage}/$resolved';
          }
          imageUrl = resolved;
          break;
        }
      }

      result['name'] = name;
      result['party'] = party;
      result['education'] = education;
      result['age'] = age;
      result['totalAssets'] = totalAssets;
      result['liabilities'] = liabilities;
      result['position'] = position;
      result['affidavit_pdfs'] = pdfs;
      result['imageUrl'] = imageUrl;
      result['raw_text'] = pageText;

      _addMessage('Parsed detail: name="${name}", party="${party}", age="${age}", assets="${totalAssets}"');
    } catch (e) {
      _addMessage('parseCandidateDetail error: $e', printToConsole: true);
    }
    return result;
  }

  // ----- Main import runner: find candidate links, parse details, upload images, save to Firestore -----
  Future<void> _runImport() async {
    setState(() => _loading = true);
    _addMessage('Starting import for ${widget.districtName}, ${widget.stateName}');

    if (CLOUDINARY_CLOUD_NAME == 'your_cloud_name' || CLOUDINARY_UPLOAD_PRESET == 'your_unsigned_preset') {
      _addMessage('Set Cloudinary constants at top of file before running.', printToConsole: true);
      setState(() => _loading = false);
      return;
    }

    try {
      final listUrl = Uri.parse('$myNetaBase${widget.statePage}/index.php?action=show_candidates&constituency_id=${widget.constituencyId}');
      _addMessage('Fetching list: $listUrl');
      final r = await http.get(listUrl);
      _addMessage('List page HTTP status: ${r.statusCode}');
      if (r.statusCode != 200) throw Exception('List page HTTP ${r.statusCode}');

      final pageDoc = html_parser.parse(r.body);

      // Collect candidate.php links anywhere on the page (robust)
      final candidateLinks = <String>{};
      for (final a in pageDoc.querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        if (href.contains('candidate.php')) {
          var resolved = href;
          if (!resolved.startsWith('http')) {
            resolved = resolved.startsWith('/') ? '$myNetaBase$resolved' : '$myNetaBase${widget.statePage}/$resolved';
          }
          candidateLinks.add(resolved);
        }
      }

      _addMessage('Found ${candidateLinks.length} candidate links');

      if (candidateLinks.isEmpty) {
        _addMessage('No candidate.php links found — dumping sample anchors (first 30) for debugging');
        int c = 0;
        for (final a in pageDoc.querySelectorAll('a[href]')) {
          final href = a.attributes['href'] ?? '';
          _addMessage(' anchor: ${href.length > 200 ? href.substring(0, 200) + "..." : href}');
          if (++c >= 30) break;
        }
        setState(() => _loading = false);
        return;
      }

      final firestore = FirebaseFirestore.instance;
      int processed = 0;

      for (final detailUrl in candidateLinks) {
        _addMessage('--- processing: $detailUrl');
        try {
          final parsed = await _parseCandidateDetail(detailUrl);

          final name = (parsed['name'] as String?)?.trim() ?? '';
          final party = (parsed['party'] as String?)?.trim() ?? '';
          final education = (parsed['education'] as String?)?.trim() ?? '';
          final age = (parsed['age'] as String?)?.trim() ?? '';
          final totalAssets = (parsed['totalAssets'] as String?)?.trim() ?? '';
          final liabilities = (parsed['liabilities'] as String?)?.trim() ?? '';
          final position = (parsed['position'] as String?)?.trim() ?? '';
          final affidavitPdfs = List<String>.from(parsed['affidavit_pdfs'] ?? []);
          final imageUrl = (parsed['imageUrl'] as String?) ?? '';

          final record = <String, dynamic>{
            'name': name,
            'party': party,
            'district': widget.districtName,
            'state': widget.stateName,
            'constituency_id': widget.constituencyId,
            'isWinner': detailUrl.toLowerCase().contains('winner'),
            'avgRating': 0.0,
            'totalRatings': 0,
            'photoUrl': '',
            'position': position,
            'education': education,
            'age': age,
            'totalAssets': totalAssets,
            'liabilities': liabilities,
            'affidavit_pdfs': affidavitPdfs,
            'myneta_raw': parsed,
            'detail_page_url': detailUrl,
            'created_at': FieldValue.serverTimestamp(),
          };

          // upload image to Cloudinary if present
          if (imageUrl.isNotEmpty) {
            _addMessage('Downloading image: $imageUrl');
            try {
              final iResp = await http.get(Uri.parse(imageUrl));
              if (iResp.statusCode == 200 && iResp.bodyBytes.isNotEmpty) {
                final bytes = iResp.bodyBytes;
                final safeName = _sanitizeFilename('${widget.districtName}_${DateTime.now().millisecondsSinceEpoch}');
                final filename = '$safeName.jpg';
                final uploaded = await _uploadToCloudinary(bytes, filename);
                if (uploaded != null) record['photoUrl'] = uploaded;
              } else {
                _addMessage('Image download failed status=${iResp.statusCode}', printToConsole: true);
              }
            } catch (e) {
              _addMessage('Image download/upload error: $e', printToConsole: true);
            }
          } else {
            _addMessage('No image found on detail page');
          }

          // save to firestore
          _addMessage('Saving to Firestore: name="$name", party="$party"');
          try {
            final docRef = firestore.collection('politicians').doc();
            await docRef.set(record);
            _addMessage('Saved doc=${docRef.id}');
          } catch (e) {
            _addMessage('Firestore save error: $e', printToConsole: true);
          }

          processed += 1;
          _addMessage('Processed $processed of ${candidateLinks.length}');
        } catch (e) {
          _addMessage('Error processing detail $detailUrl : $e', printToConsole: true);
        }
      }

      _addMessage('🎉 Import complete. Total processed: $processed');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import done: $processed candidates')));
    } catch (e, st) {
      _addMessage('Fatal import error: $e', printToConsole: true);
      print(st);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  // ----- UI -----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin: Load Politicians (one-time)'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('State page: ${widget.statePage}'),
            Text('Constituency id: ${widget.constituencyId}'),
            Text('District: ${widget.districtName}'),
            const SizedBox(height: 10),
            if (_loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Import running... watch logs below'),
              const SizedBox(height: 8),
            ] else ...[
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _runImport,
                    icon: const Icon(Icons.download),
                    label: const Text('Run one-time import'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Confirm delete'),
                          content: Text('Delete all politicians where district == "${widget.districtName}"? This is irreversible.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true) await _deleteDistrictRecords(widget.districtName);
                    },
                    icon: const Icon(Icons.delete, color: Colors.white),
                    label: const Text('Delete district records'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Run once and remove this page from project.'),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: _messages.isEmpty
                    ? const Center(child: Text('No logs yet — press Run one-time import'))
                    : ListView.builder(
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(_messages[i], style: const TextStyle(fontSize: 12)),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

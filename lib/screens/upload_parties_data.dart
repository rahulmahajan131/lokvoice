import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const UploadPartiesApp());
}

class UploadPartiesApp extends StatelessWidget {
  const UploadPartiesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: UploadPartiesPage(),
    );
  }
}

class UploadPartiesPage extends StatefulWidget {
  const UploadPartiesPage({super.key});

  @override
  State<UploadPartiesPage> createState() => _UploadPartiesPageState();
}

class _UploadPartiesPageState extends State<UploadPartiesPage> {
  String _status = 'Uploading...';

  final List<Map<String, dynamic>> dummyParties = List.generate(50, (i) {
    final states = ['Madhya Pradesh', 'Uttar Pradesh', 'Rajasthan', 'Bihar', 'Maharashtra'];
    final districts = [
      'Indore', 'Bhopal', 'Varanasi', 'Jaipur', 'Gaya',
      'Nagpur', 'Ujjain', 'Lucknow', 'Jodhpur', 'Patna'
    ];

    final state = states[i % states.length];
    final district = districts[i % districts.length];

    return {
      'name': 'Party ${i + 1}',
      'description': 'This is a description for Party ${i + 1}. It is active in $district, $state.',
      'state': state,
      'district': district,
      'logoUrl': 'https://via.placeholder.com/150x150.png?text=Party+${i + 1}',
      'followers': [],
    };
  });

  @override
  void initState() {
    super.initState();
    _uploadParties();
  }

  Future<void> _uploadParties() async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final partiesCollection = FirebaseFirestore.instance.collection('parties');

      for (var party in dummyParties) {
        final docRef = partiesCollection.doc();
        batch.set(docRef, party);
      }

      await batch.commit();

      setState(() {
        _status = '✅ Uploaded ${dummyParties.length} parties successfully.';
      });
    } catch (e) {
      setState(() {
        _status = '❌ Upload failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Dummy Parties')),
      body: Center(child: Text(_status, textAlign: TextAlign.center)),
    );
  }
}
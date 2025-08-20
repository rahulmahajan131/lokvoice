import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../providers/circle_provider.dart';
import 'login_page.dart';
import 'home_page.dart';
import '../utils/india_states_districts.dart';

class CircleSelectionPage extends StatefulWidget {
  const CircleSelectionPage({Key? key}) : super(key: key);

  @override
  State<CircleSelectionPage> createState() => _CircleSelectionPageState();
}

class _CircleSelectionPageState extends State<CircleSelectionPage> {
  late List<String> states;
  List<String> districts = [];

  String? selectedState;
  String? selectedDistrict;
  final TextEditingController pinCodeController = TextEditingController();

  bool _submitted = false;
  bool _checkingCircle = true; // loading state

  @override
  void initState() {
    super.initState();
    states = indiaStatesDistricts.keys.toList()..sort();
    _checkIfCircleExists();
  }

  @override
  void dispose() {
    pinCodeController.dispose();
    super.dispose();
  }

  Future<void> _checkIfCircleExists() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();

    if (data != null && data['circle'] != null) {
      final circleData = Map<String, dynamic>.from(data['circle']);
      if (!mounted) return;

      context.read<CircleProvider>().setCircle(circleData);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } else {
      // No circle set, show form
      if (mounted) {
        setState(() => _checkingCircle = false);
      }
    }
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);

    if (selectedState == null) {
      _showSnackBar('Please select a state');
      return;
    }
    if (selectedDistrict == null) {
      _showSnackBar('Please select a district');
      return;
    }

    final pinCode = pinCodeController.text.trim();
    if (pinCode.isNotEmpty && !RegExp(r'^[0-9]{6}$').hasMatch(pinCode)) {
      _showSnackBar('Enter a valid 6-digit pin code or leave empty');
      return;
    }

    final circleData = {
      'state': selectedState,
      'district': selectedDistrict,
      'pinCode': pinCode.isEmpty ? null : pinCode,
    };

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not signed in');
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'circle': circleData}, SetOptions(merge: true));

      if (!mounted) return;

      context.read<CircleProvider>().setCircle(circleData);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } catch (e) {
      _showSnackBar('Failed to submit: $e');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    districts = selectedState == null ? [] : indiaStatesDistricts[selectedState!] ?? [];

    // 🔄 Show loader until we check Firestore
    if (_checkingCircle) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Select Your Circle', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose your area to see posts from people around you.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.transparent : Colors.black12,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Select State',
                      border: OutlineInputBorder(),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    value: selectedState,
                    isExpanded: true,
                    items: states.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedState = val;
                        selectedDistrict = null;
                      });
                    },
                    validator: (_) => _submitted && selectedState == null ? 'State required' : null,
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Select District',
                      border: OutlineInputBorder(),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    value: selectedDistrict,
                    isExpanded: true,
                    items: districts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedDistrict = val;
                      });
                    },
                    validator: (_) => _submitted && selectedDistrict == null ? 'District required' : null,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: pinCodeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pin Code (Optional)',
                      hintText: '6-digit area pin code',
                      border: OutlineInputBorder(),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      counterText: '',
                    ),
                    maxLength: 6,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Submit', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
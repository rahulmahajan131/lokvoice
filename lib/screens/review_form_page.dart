import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReviewFormPage extends StatefulWidget {
  final String politicianId;
  final String politicianName;

  const ReviewFormPage({
    super.key,
    required this.politicianId,
    required this.politicianName,
  });

  @override
  State<ReviewFormPage> createState() => _ReviewFormPageState();
}

class _ReviewFormPageState extends State<ReviewFormPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _reviewController = TextEditingController();

  final Map<String, double> _ratings = {
    'Communication': 0.0,
    'Development Work': 0.0,
    'Accessibility': 0.0,
    'Corruption-Free': 0.0,
    'Law & Order': 0.0,
  };

  bool _isLoading = false;

  Widget _buildStarSelector(String category, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(category, style: theme.textTheme.bodyMedium)),
          for (int i = 1; i <= 5; i++)
            IconButton(
              icon: Icon(
                i <= _ratings[category]! ? Icons.star : Icons.star_border,
                color: Colors.orange,
              ),
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _ratings[category] = i.toDouble();
                      });
                    },
            ),
        ],
      ),
    );
  }

  Future<void> _submitReview() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Navigator.of(context).pop(); // remove loading dialog
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final avgRating = _ratings.values.reduce((a, b) => a + b) / _ratings.length;
      final politicianDoc = FirebaseFirestore.instance
          .collection('politicians')
          .doc(widget.politicianId);

      final docSnapshot = await politicianDoc.get();
      if (!docSnapshot.exists) {
        await politicianDoc.set({
          'name': widget.politicianName,
          'avgRating': 0.0,
          'totalRatings': 0,
          'ratings': {for (var cat in _ratings.keys) cat: 0.0},
        });
      }

      await politicianDoc.collection('reviews').doc(user.uid).set({
        'userId': user.uid,
        'username': user.displayName ?? 'Anonymous',
        'comment': _reviewController.text.trim(),
        'ratings': _ratings,
        'overall': avgRating,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Aggregate all ratings again
      final reviewsSnapshot = await politicianDoc.collection('reviews').get();
      final total = reviewsSnapshot.docs.length;
      final aggregate = <String, double>{};
      _ratings.keys.forEach((k) => aggregate[k] = 0);

      for (var doc in reviewsSnapshot.docs) {
        final ratings = Map<String, dynamic>.from(doc['ratings']);
        ratings.forEach((k, v) {
          aggregate[k] = aggregate[k]! + (v as num).toDouble();
        });
      }

      final updatedRatings = <String, double>{};
      double sum = 0;
      aggregate.forEach((k, v) {
        final avg = v / total;
        updatedRatings[k] = avg;
        sum += avg;
      });

      await politicianDoc.update({
        'ratings': updatedRatings,
        'avgRating': sum / _ratings.length,
        'totalRatings': total,
      });

      if (!mounted) return;

      Navigator.of(context).pop(); // remove loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you for your review!')),
      );

      // Navigate and remove all previous routes
      Navigator.pushNamedAndRemoveUntil(context, '/rate', (route) => false);
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // remove loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting review: $e')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Rate & Review ${widget.politicianName}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              ..._ratings.keys.map((cat) => _buildStarSelector(cat, theme)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _reviewController,
                maxLines: 5,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Write your review',
                  labelStyle: theme.textTheme.bodyMedium,
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your review';
                  }
                  return null;
                },
                enabled: !_isLoading,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitReview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Submit Review', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
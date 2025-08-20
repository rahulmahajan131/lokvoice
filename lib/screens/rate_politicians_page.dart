import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/circle_provider.dart';
import 'footer_nav_bar.dart';
import 'review_form_page.dart';
import 'politician_profile_page.dart';

class RatePoliticiansPage extends StatefulWidget {
  const RatePoliticiansPage({Key? key}) : super(key: key);

  @override
  State<RatePoliticiansPage> createState() => _RatePoliticiansPageState();
}

class _RatePoliticiansPageState extends State<RatePoliticiansPage> {
  List<DocumentSnapshot> _politicians = [];
  bool _loading = true;
  String? _error;
  List<bool> _expandedList = [];
  List<bool> _showReviewsList = [];

  @override
  void initState() {
    super.initState();
    _loadPoliticians();
  }

  Future<void> _loadPoliticians() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final circleData = context.read<CircleProvider>().circleData;
      if (circleData == null) {
        setState(() {
          _error = 'Circle data not set.';
          _loading = false;
        });
        return;
      }

      final state = circleData['state'] as String;
      final district = circleData['district'] as String?;

      Query query = FirebaseFirestore.instance.collection('politicians').where('state', isEqualTo: state);
      if (district != null && district.isNotEmpty) {
        query = query.where('district', isEqualTo: district);
      }

      final querySnapshot = await query.get();
      setState(() {
        _politicians = querySnapshot.docs;
        _expandedList = List<bool>.filled(_politicians.length, false);
        _showReviewsList = List<bool>.filled(_politicians.length, false);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load politicians: $e';
        _loading = false;
      });
    }
  }

  Widget _buildStarRow(double rating, Color color) {
    int fullStars = rating.floor();
    bool hasHalfStar = (rating - fullStars) >= 0.5;
    List<Widget> stars = [];
    for (int i = 0; i < 5; i++) {
      if (i < fullStars) {
        stars.add(Icon(Icons.star, size: 20, color: color));
      } else if (i == fullStars && hasHalfStar) {
        stars.add(Icon(Icons.star_half, size: 20, color: color));
      } else {
        stars.add(Icon(Icons.star_border, size: 20, color: color));
      }
    }
    return Row(children: stars);
  }

  Widget _buildCategorySlider(String label, double rating, TextStyle labelStyle, Color starColor, TextStyle ratingStyle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          _buildStarRow(rating, starColor),
          const SizedBox(width: 6),
          Text(rating.toStringAsFixed(1), style: ratingStyle),
        ],
      ),
    );
  }

  Widget _buildReviewList(String politicianId, TextStyle usernameStyle, TextStyle commentStyle, Color cardColor, Color borderColor) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('politicians')
          .doc(politicianId)
          .collection('reviews')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
          );
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return Padding(
          padding: const EdgeInsets.all(12),
          child: Text('No reviews yet.', style: commentStyle),
        );

        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final overallRating = (data['overall'] ?? 0).toDouble();
            final comment = data['comment'] ?? '';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(data['username'] ?? 'Anonymous', style: usernameStyle),
                        _buildStarRow(overallRating, Theme.of(context).colorScheme.secondary),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (comment.isNotEmpty)
                      Text(comment, style: commentStyle),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final labelStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold) ?? const TextStyle(fontWeight: FontWeight.bold);
    final ratingStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final usernameStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold) ?? const TextStyle(fontWeight: FontWeight.bold);
    final commentStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final cardColor = theme.cardColor;
    final borderColor = theme.dividerColor;
    final starColor = theme.colorScheme.secondary;
    final linkColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Leader Ratings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
        automaticallyImplyLeading: false,
        backgroundColor: theme.colorScheme.primary,
        centerTitle: true,
        elevation: 1,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          : _error != null
              ? Center(child: Text(_error!, style: commentStyle))
              : _politicians.isEmpty
                  ? Center(child: Text('No active politicians found in your area.', style: commentStyle))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _politicians.length,
                      itemBuilder: (context, index) {
                        final doc = _politicians[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final ratings = (data['ratings'] as Map<String, dynamic>? ?? {})
                            .map((k, v) => MapEntry(k, (v as num).toDouble()));
                        final reviewCount = (data['totalRatings'] ?? 0);

                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PoliticianProfilePage(politicianId: doc.id),
                              ),
                            );
                          },
                          child: Card(
                            elevation: 3,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            color: cardColor,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundImage: data['photoUrl'] != null && data['photoUrl'].isNotEmpty
                                            ? NetworkImage(data['photoUrl'])
                                            : null,
                                        child: (data['photoUrl'] == null || data['photoUrl'].isEmpty)
                                            ? Icon(Icons.person, color: theme.iconTheme.color)
                                            : null,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(data['name'] ?? 'Unknown',
                                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 2),
                                            Text(data['position'] ?? '',
                                                style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.6))),
                                            Text('Party: ${data['party'] ?? ''}',
                                                style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.6))),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          _expandedList[index]
                                              ? Icons.keyboard_arrow_up
                                              : Icons.keyboard_arrow_down,
                                          color: theme.iconTheme.color,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _expandedList[index] = !_expandedList[index];
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      _buildStarRow((data['avgRating'] ?? 0).toDouble(), starColor),
                                      const SizedBox(width: 8),
                                      Text(
                                        (data['avgRating'] ?? 0).toStringAsFixed(1),
                                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _showReviewsList[index] = !_showReviewsList[index];
                                          });
                                        },
                                        child: Text(
                                          '($reviewCount reviews)',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: linkColor,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (_expandedList[index])
                                    ...ratings.entries
                                        .map((e) => _buildCategorySlider(e.key, e.value, labelStyle, starColor, ratingStyle))
                                        .toList(),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      icon: Icon(Icons.rate_review_outlined, color: theme.colorScheme.primary),
                                      label: Text("Rate & Review", style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ReviewFormPage(
                                              politicianId: doc.id,
                                              politicianName: data['name'] ?? 'Unknown',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  if (_showReviewsList[index]) _buildReviewList(doc.id, usernameStyle, commentStyle, cardColor, borderColor),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
       bottomNavigationBar: FooterNavBar(
              selectedIndex: 2,
              onTap: (i) {
                const routes = ['/home', '/news', '/rate', '/party', '/profile'];
                if (i < routes.length) Navigator.pushReplacementNamed(context, routes[i]);
              },
        ),
    );
  }
}
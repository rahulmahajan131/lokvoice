import 'package:flutter/material.dart';
import 'news_content.dart'; // adjust import path
import 'footer_nav_bar.dart';

class LocalNewsPage extends StatelessWidget {
  final String district;
  final String state;

  const LocalNewsPage({
    super.key,
    required this.district,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Local News'),
        backgroundColor: primaryColor,
      ),
      body: NewsContent(district: district, state: state),
     bottomNavigationBar: FooterNavBar(
                   selectedIndex: 1,
                   onTap: (i) {
                     const routes = ['/home', '/news', '/rate', '/party', '/profile'];
                     if (i < routes.length) Navigator.pushReplacementNamed(context, routes[i]);
                   },
         ),
    );
  }
}
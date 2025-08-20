import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'rate_politicians_page.dart';
import 'party_follow_page.dart';
import 'home_page.dart';
import 'local_news_page.dart';
import '../providers/circle_provider.dart';
import '../screens/profile_page.dart'; // Import ProfilePage

class FooterNavBar extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onTap;

  const FooterNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final circleData = context.watch<CircleProvider>().circleData;
    final theme = Theme.of(context);

    return BottomNavigationBar(
      currentIndex: selectedIndex,
      onTap: (index) {
        if (index == selectedIndex) return;

        switch (index) {
          case 0:
            if (circleData == null ||
                !circleData.containsKey('state') ||
                !circleData.containsKey('district')) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Circle data is missing. Please select your circle.'),
                ),
              );
              return;
            }
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomePage()),
            );
            break;
           case 1:
             final district = circleData?['district'] ?? 'Delhi'; // Fallback to 'Delhi'
              final state = circleData?['state'] ?? 'Madhya Pradesh'; // Fallback to 'Delhi'
             Navigator.pushReplacement(
               context,
               MaterialPageRoute(
                 builder: (_) => LocalNewsPage(district: district, state: state),
               ),
             );
             break;
          case 2:
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const RatePoliticiansPage()),
            );
            break;

          case 3:
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const PartyFollowPage()),
            );
            break;

          case 4:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            );
            break;
        }

        onTap(index);
      },
      selectedItemColor: theme.colorScheme.primary,
      unselectedItemColor: Colors.grey,
      backgroundColor: theme.colorScheme.surface,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.article),
          label: 'News',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.star),
          label: 'Rate',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.group),
          label: 'Local Parties',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}
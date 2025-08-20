import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'providers/circle_provider.dart';
import 'screens/login_page.dart';
import 'screens/circle_selection_page.dart';
import 'screens/home_page.dart';
import 'screens/profile_page.dart';
import 'screens/rate_politicians_page.dart';
import 'screens/party_follow_page.dart';
import 'screens/local_news_page.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final circleProvider = CircleProvider();
  await circleProvider.loadCircleData();

  runApp(
    ChangeNotifierProvider.value(
      value: circleProvider,
      child: const LokVoiceApp(),
    ),
  );
}

class LokVoiceApp extends StatelessWidget {
  const LokVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LokVoice',
      debugShowCheckedModeBanner: false,
     // 👇 Choose one of the three themes here
           theme: AppTheme.option3,   // Option 1
           // theme: AppTheme.politicalTheme, // Option 2
           // theme: AppTheme.cleanNewsTheme, // Option 3
      themeMode: ThemeMode.light, // This line keeps light theme enforced
      initialRoute: '/',
      routes: {
        '/': (context) => _getInitialScreen(context),
        '/login': (context) => const LoginPage(),
        '/circle': (context) => const CircleSelectionPage(),
        '/home': (context) => const HomePage(),
        '/profile': (context) => const ProfilePage(),
        '/rate': (context) => const RatePoliticiansPage(),
        '/party': (context) => const PartyFollowPage(),
        '/news': (context) {
          final circleData = context.read<CircleProvider>().circleData;
          final district = circleData?['district'] ?? 'Delhi';
          final state = circleData?['state'] ?? 'Madhya Pradesh';
          return LocalNewsPage(district: district, state: state);
        },
      },
    );
  }

  Widget _getInitialScreen(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final circleData = context.read<CircleProvider>().circleData;

    if (user == null) {
      return const LoginPage();
    } else if (circleData == null) {
      return const CircleSelectionPage();
    } else {
      return const HomePage();
    }
  }
}

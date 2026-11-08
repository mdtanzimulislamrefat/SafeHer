import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/contacts_store.dart';
import 'screens/circle_screen.dart';
import 'screens/home_screen.dart';
import 'services/sos_controller.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(SafeHerApp(prefs: prefs));
}

class SafeHerApp extends StatelessWidget {
  const SafeHerApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ContactsStore(prefs)),
        ChangeNotifierProvider(create: (_) => SosController(prefs)),
      ],
      child: MaterialApp(
        title: 'SafeHer',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          HomeScreen(),
          _ComingSoon(
            title: 'Safe Journey',
            text: 'Share your trip with your circle, check in on the way, and get a nudge if something looks off.',
          ),
          _ComingSoon(
            title: 'Ask SafeHer',
            text: 'Ask what to do or where to get help, in Bangla or English, with sources.',
          ),
          CircleScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SafeColors.line)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.place_outlined), selectedIcon: Icon(Icons.place), label: 'Journey'),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Ask',
            ),
            NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Circle'),
          ],
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: SafeText.heading(30)),
            const SizedBox(height: 8),
            Text(text, style: SafeText.small),
            const SizedBox(height: 16),
            const Text('Coming in the next build.', style: SafeText.bodyStrong),
          ],
        ),
      ),
    );
  }
}

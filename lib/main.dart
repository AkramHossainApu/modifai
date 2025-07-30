import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_page.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  Future<Widget> _getInitialPage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return const HomePage();
    }
    final prefs = await SharedPreferences.getInstance();
    final isAdmin = prefs.getBool('isAdmin') ?? false;
    if (isAdmin) {
      return const HomePage();
    } else {
      return const WelcomePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FutureBuilder<Widget>(
        future: _getInitialPage(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return snapshot.data!;
          }
          return const Scaffold(
            backgroundColor: Color(0xFF181A20),
            body: Center(child: CircularProgressIndicator()),
          );
        },
      ),
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
      },
    );
  }
}

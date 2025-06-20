import 'package:flutter/material.dart';
import 'welcome_page.dart';
import 'login_page.dart';
import 'home_page.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WelcomePage(),
      routes: {
        '/login': (context) => LoginPage(),
        '/home': (context) => HomePage(),
        // '/profile': (context) => ProfilePage(userName: 'Admin', email: 'admin@gmail.com'), // If you want named route
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'animated_circle.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sign_up_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final isAdmin = prefs.getBool('isAdmin') ?? false;
    if (isAdmin && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    try {
      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (!mounted) return;
      if (account != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isAdmin', true);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signed in as ${account.email}')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Google Sign-In failed: $error')));
    }
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final user = userCredential.user;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed: No user found in Auth')),
        );
        return;
      }
      // Get user data from Firebase Auth
      final userName = user.displayName ?? '';
      final userEmail = user.email ?? '';
      // Always sync with Firestore profile
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': userName,
        'email': userEmail,
        'createdAt': FieldValue.serverTimestamp(),
        'isAdmin': false,
      }, SetOptions(merge: true));
      final userProfile =
          (await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get())
              .data();
      final isAdmin = userProfile?['isAdmin'] == true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isAdmin', isAdmin);
      await prefs.setString('userName', userName);
      await prefs.setString('userEmail', userEmail);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains(
        "List<Object?>' is not a subtype of type 'PigeonUserDetails?",
      )) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final userName = user.displayName ?? '';
          final userEmail = user.email ?? '';
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          final userProfile = userDoc.data();
          final isAdmin = userProfile?['isAdmin'] == true;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isAdmin', isAdmin);
          await prefs.setString('userName', userName);
          await prefs.setString('userEmail', userEmail);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login successful despite type cast error.'),
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
          return;
        }
      }
      String errorMsg = 'Login error: ${e.toString()}';
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
            errorMsg = 'No user found for that email.';
            break;
          case 'wrong-password':
            errorMsg = 'Wrong password provided.';
            break;
          case 'invalid-email':
            errorMsg = 'Invalid email address.';
            break;
          default:
            errorMsg = 'Login error: ${e.message}';
        }
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMsg)));
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -100,
            child: AnimatedCircle(
              color: Colors.blueAccent.withAlpha((0.15 * 255).toInt()),
              size: 250,
              duration: 3000,
            ),
          ),
          Positioned(
            bottom: -80,
            right: -80,
            child: AnimatedCircle(
              color: Colors.purpleAccent.withAlpha((0.10 * 255).toInt()),
              size: 200,
              duration: 4000,
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF23242B),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/modifai_logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Login to ModifAI',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        TextField(
                          controller: _emailController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Email',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              color: Colors.blueAccent.shade100,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF23242B),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Password',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            prefixIcon: Icon(
                              Icons.lock_outline,
                              color: Colors.blueAccent.shade100,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF23242B),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent.shade200,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 60,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 6,
                          ),
                          onPressed: _handleLogin,
                          child: const Text(
                            'Login',
                            style: TextStyle(
                              fontSize: 20,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Divider(color: Colors.grey.shade700),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8.0),
                              child: Text(
                                "or",
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                            Expanded(
                              child: Divider(color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 2,
                            ),
                            icon: Image.asset(
                              'assets/google_logo.png',
                              height: 24,
                              width: 24,
                            ),
                            label: const Text(
                              'Continue with Google',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            onPressed: _handleGoogleSignIn,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don't have an account?",
                              style: TextStyle(color: Colors.white70),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SignUpPage(),
                                  ),
                                );
                              },
                              child: const Text(
                                "Sign Up",
                                style: TextStyle(
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

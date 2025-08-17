import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_page.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'massage/call_screen.dart';
import 'services/call_service.dart';
import 'dart:async';

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
      home: GlobalCallListener(
        child: FutureBuilder<Widget>(
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
      ),
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
      },
    );
  }
}

class GlobalCallListener extends StatefulWidget {
  final Widget child;
  const GlobalCallListener({required this.child, super.key});
  @override
  State<GlobalCallListener> createState() => _GlobalCallListenerState();
}

class _GlobalCallListenerState extends State<GlobalCallListener> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callSub;
  bool _showingCallDialog = false;

  @override
  void initState() {
    super.initState();
    _listenForCalls();
  }

  void _listenForCalls() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final myEmail = user.email!.trim().toLowerCase();
    final calls = FirebaseFirestore.instance.collection('calls');
    _callSub = calls.where('receiverId', isEqualTo: myEmail).snapshots().listen((
      query,
    ) {
      if (_showingCallDialog) return;
      for (var doc in query.docs) {
        final data = doc.data();
        if (data['status'] == 'ringing') {
          _showingCallDialog = true;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF23242B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    (data['isVideo'] ?? false) ? Icons.videocam : Icons.call,
                    color: Colors.greenAccent,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Incoming Call',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    data['callerName'] ?? 'Unknown',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data['callerId'] ?? '',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.call_end, color: Colors.white),
                        label: const Text(
                          'Reject',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                        ),
                        onPressed: () async {
                          await CallService.endCall(data['callerId'], myEmail);
                          // Clean up call doc after ending
                          await FirebaseFirestore.instance
                              .collection('calls')
                              .doc(doc.id)
                              .delete();
                          Navigator.of(context, rootNavigator: true).pop();
                          _showingCallDialog = false;
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.call, color: Colors.white),
                        label: const Text(
                          'Accept',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                        ),
                        onPressed: () async {
                          await CallService.acceptCall(
                            data['callerId'],
                            myEmail,
                          );
                          Navigator.of(context, rootNavigator: true).pop();
                          _showingCallDialog = false;
                          // Clean up call doc after accepting (optional, or do after call ends)
                          // await FirebaseFirestore.instance.collection('calls').doc(doc.id).delete();
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              fullscreenDialog: true,
                              builder: (_) => CallScreen(
                                isCaller: false,
                                callId: doc.id,
                                selfId: myEmail,
                                peerId: data['callerId'],
                                isVideo: data['isVideo'] ?? false,
                                callerName: data['callerName'],
                                callerEmail: data['callerId'],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ).then((_) {
            _showingCallDialog = false;
          });
          break;
        }
      }
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController _groupNameController = TextEditingController();
  String? _groupImagePath;

  void _pickGroupImage() async {
    final picker = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picker != null) {
      setState(() {
        _groupImagePath = picker.path;
      });
    }
  }

  void _removeGroupImage() {
    setState(() {
      _groupImagePath = null;
    });
  }

  void _createGroup() {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name.')),
      );
      return;
    }
    // TODO: Save group with name and image
    Navigator.of(context).pop({'name': groupName, 'image': _groupImagePath});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Create Group',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _pickGroupImage,
              child: _groupImagePath == null
                  ? CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.blueGrey.shade700,
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    )
                  : Stack(
                      alignment: Alignment.topRight,
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundImage: FileImage(File(_groupImagePath!)),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: _removeGroupImage,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _groupNameController,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: 'Group Name',
                labelStyle: const TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                ),
                filled: true,
                fillColor: Colors.grey[850],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Colors.blueAccent,
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Colors.blueAccent,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 36,
                  vertical: 16,
                ),
              ),
              onPressed: _createGroup,
              child: const Text(
                'Create Group',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'profile_page.dart';
import 'animated_circle.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'services/api_service.dart';
import 'package:photo_view/photo_view.dart';
<<<<<<< Updated upstream
import 'massage/m_home_page.dart';
=======
import 'package:shared_preferences/shared_preferences.dart';
>>>>>>> Stashed changes

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<Map<String, dynamic>> _chatHistory = [];

  final TextEditingController _chatController = TextEditingController();
  late FocusNode _chatFocusNode;
  bool _showOptions = false;
  bool _isRecording = false;
  late AnimationController _bgController;
  late AnimationController _optionController;

  String? _profileImagePath;

  final List<Map<String, String>> _suggestions = [
    {'title': 'Redesign my living room', 'subtitle': 'with a modern style'},
    {'title': 'Make my bedroom cozy', 'subtitle': 'using warm colors'},
    {'title': 'Add plants to my workspace', 'subtitle': 'for a fresh look'},
    {'title': 'Suggest furniture layout', 'subtitle': 'for a small apartment'},
    {'title': 'Create a minimalist kitchen', 'subtitle': 'with smart storage'},
    {'title': 'Decorate my dining area', 'subtitle': 'for family gatherings'},
  ];

  final ScrollController _chatScrollController = ScrollController();
  File? _pickedImage;
  bool _isLoading = false;

  final List<String> _placeholders = [
    "What's on your mind?",
    "Tell me your plan",
    "How can I help you today?",
    "Share your idea...",
    "What would you like to do?",
  ];
  late String _currentPlaceholder;

  final List<List<Map<String, dynamic>>> _chatSessions = [];
  int _currentSessionIndex = 0;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);

    _optionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _chatFocusNode = FocusNode();

    _chatController.addListener(() {
      setState(() {});
    });

    // Request focus when the widget is built
    Future.delayed(Duration.zero, () {
      _chatFocusNode.requestFocus();
    });

    // Set initial placeholder
    _currentPlaceholder = _placeholders[0];

    _loadProfileImage();
  }

  Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('profile_image_path');
    if (mounted) {
      setState(() {
        _profileImagePath = path;
      });
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    _bgController.dispose();
    _optionController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  void _toggleOptions() {
    setState(() {
      _showOptions = !_showOptions;
      if (_showOptions) {
        _optionController.forward();
      } else {
        _optionController.reverse();
      }
    });
  }

  void _handleOption(String option) {
    setState(() {
      _showOptions = false;
      _optionController.reverse();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Selected: $option')));
  }

  Future<void> _handleSend() async {
    final text = _chatController.text.trim();
    if (text.isNotEmpty) {
      // If an image is picked, send both image and prompt to AI for modification
      if (_pickedImage != null) {
        final imageToSend = _pickedImage!;
        setState(() {
          _chatHistory.add({
            "sender": "user",
            "text": text,
            "image": imageToSend.path,
          });
          _pickedImage =
              null; // Remove the image preview immediately after sending
          _chatController
              .clear(); // Clear the text box immediately after sending
          _isLoading = true;
        });
        // Show AI typing indicator (animated dots)
        setState(() {
          _chatHistory.add({"sender": "ai", "text": "[typing]"});
        });
        try {
          final decorated = await ApiService.getDecoratedImage(
            imageToSend,
            prompt: text,
            onProgress: (int p) {},
          );
          setState(() {
            // Remove typing indicator
            final idx = _chatHistory.lastIndexWhere(
              (msg) => msg['text'] == "[typing]",
            );
            if (idx != -1) _chatHistory.removeAt(idx);
            _chatHistory.add({"sender": "ai", "image": decorated.path});
          });
        } catch (e) {
          setState(() {
            final idx = _chatHistory.lastIndexWhere(
              (msg) => msg['text'] == "[typing]",
            );
            if (idx != -1) _chatHistory.removeAt(idx);
            _chatHistory.add({"sender": "ai", "text": "AI image error: $e"});
          });
        } finally {
          setState(() {
            _isLoading = false;
          });
        }
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_chatScrollController.hasClients) {
            _chatScrollController.animateTo(
              _chatScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
        return;
      }
      // If this is the first message in a new chat, start a new session
      if (_isNewChat) {
        _chatSessions.add([]);
        _currentSessionIndex = _chatSessions.length - 1;
      }
      setState(() {
        _chatHistory.add({'text': text, 'sender': 'user'});
        _chatSessions[_currentSessionIndex].add({
          'text': text,
          'sender': 'user',
        });
        _chatController.clear(); // Clear the text box immediately after sending
        _isLoading = true;
      });
      setState(() {
        _chatHistory.add({"sender": "ai", "text": "[typing]"});
      });
      try {
        final reply = await ApiService.getChatbotReply(text);
        setState(() {
          final idx = _chatHistory.lastIndexWhere(
            (msg) => msg['text'] == "[typing]",
          );
          if (idx != -1) _chatHistory.removeAt(idx);
          if (reply is File) {
            _chatHistory.add({'text': '[image:${reply.path}]', 'sender': 'ai'});
            _chatSessions[_currentSessionIndex].add({
              'text': '[image:${reply.path}]',
              'sender': 'ai',
            });
          } else {
            _chatHistory.add({'text': reply, 'sender': 'ai'});
            _chatSessions[_currentSessionIndex].add({
              'text': reply,
              'sender': 'ai',
            });
          }
        });
      } catch (e) {
        setState(() {
          final idx = _chatHistory.lastIndexWhere(
            (msg) => msg['text'] == "[typing]",
          );
          if (idx != -1) _chatHistory.removeAt(idx);
          _chatHistory.add({'text': "AI error: $e", 'sender': 'ai'});
          _chatSessions[_currentSessionIndex].add({
            'text': "AI error: $e",
            'sender': 'ai',
          });
        });
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  bool get _isNewChat => _chatHistory.isEmpty;

  @override
  Widget build(BuildContext context) {
    final double cardWidth = MediaQuery.of(context).size.width * 0.55;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF181A20),
      drawer: Drawer(
        backgroundColor: const Color(0xFF23242B),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Chat History",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const Divider(color: Colors.white24),
              // --- New Chat Option ---
              ListTile(
                leading: const Icon(Icons.add, color: Colors.blueAccent),
                title: const Text(
                  "New Chat",
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  setState(() {
                    _chatHistory.clear();
                    _pickedImage = null;
                    _isLoading = false;
                    _chatController.clear();
                    _currentPlaceholder = (_placeholders..shuffle()).first;
                    _currentSessionIndex =
                        _chatSessions.length; // new session index
                  });
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24),
              // --- Existing chat history ---
              Expanded(
                child: ListView.builder(
                  itemCount: _chatSessions.length,
                  itemBuilder: (context, index) {
                    final session = _chatSessions[index];
                    final firstMsg = session.isNotEmpty
                        ? session.first['text']
                        : "Empty chat";
                    return ListTile(
                      title: Text(
                        firstMsg.length > 30
                            ? "${firstMsg.substring(0, 30)}..."
                            : firstMsg,
                        style: const TextStyle(color: Colors.white),
                      ),
                      leading: const Icon(Icons.history, color: Colors.white54),
                      onTap: () {
                        setState(() {
                          _chatHistory
                            ..clear()
                            ..addAll(session);
                          _currentSessionIndex = index;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Animated background
          Positioned(
            top: -100,
            left: -100,
            child: AnimatedCircle(
              color: Colors.blueAccent.withAlpha(30),
              size: 250,
              duration: 3000,
            ),
          ),
          Positioned(
            bottom: -80,
            right: -80,
            child: AnimatedCircle(
              color: Colors.purpleAccent.withAlpha(25),
              size: 200,
              duration: 4000,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.only(
                    top: 18,
                    left: 16,
                    right: 16,
                    bottom: 10,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _scaffoldKey.currentState?.openDrawer(),
                        child: const Icon(
                          Icons.menu,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "ModifAI",
                        style: TextStyle(
                          color: Colors.blueAccent.shade100,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () async {
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ProfilePage(
                                userName: 'Admin',
                                email: 'admin@gmail.com',
                              ),
                            ),
                          );
                          if (result == true) {
                            _loadProfileImage();
                          }
                        },
                        child: _profileImagePath != null
                            ? CircleAvatar(
                                radius: 18,
                                backgroundImage: FileImage(File(_profileImagePath!)),
                                backgroundColor: Colors.white24,
                              )
                            : const CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.white24,
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                      ),
                      // Add button for massage home page
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const AddUserPage(),
                            ),
                          );
                        },
                        child: const CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.blueAccent,
                          child: Icon(
                            Icons.message,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Chat history
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ListView.builder(
                      controller: _chatScrollController,
                      itemCount: _chatHistory.length,
                      itemBuilder: (context, index) {
                        final msg = _chatHistory[index];
                        final isUser = (msg['sender'] ?? 'user') == 'user';
                        final String? text = msg['text']?.toString();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: isUser
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isUser)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.blueGrey[700],
                                    backgroundImage: AssetImage('assets/modifai_logo.png'),
                                  ),
                                ),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isUser
                                        ? Colors.blueAccent.shade100.withAlpha(50)
                                        : Colors.grey[600],
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft: isUser
                                          ? const Radius.circular(18)
                                          : const Radius.circular(4),
                                      bottomRight: isUser
                                          ? const Radius.circular(4)
                                          : const Radius.circular(18),
                                    ),
                                  ),
                                  child: text == "[typing]"
                                      ? AnimatedDots()
                                      : text == "[processing_image]"
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.blueAccent,
                                                value:
                                                    (msg['progress'] ?? 0) /
                                                    100,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              "Processing image...  0${msg['progress'] ?? 0}%",
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ],
                                        )
                                      : msg['image'] != null && (text == null || msg['sender'] == 'ai')
                                      ? GestureDetector(
                                          onTap: () {
                                            showDialog(
                                              context: context,
                                              builder: (_) => Dialog(
                                                backgroundColor:
                                                    Colors.transparent,
                                                child: Stack(
                                                  alignment: Alignment.topRight,
                                                  children: [
                                                    PhotoView(
                                                      imageProvider: FileImage(
                                                        File(msg['image']),
                                                      ),
                                                      backgroundDecoration:
                                                          const BoxDecoration(
                                                            color: Colors
                                                                .transparent,
                                                          ),
                                                    ),
                                                    Positioned(
                                                      top: 10,
                                                      right: 10,
                                                      child: IconButton(
                                                        icon: const Icon(
                                                          Icons.close,
                                                          color: Colors.white,
                                                          size: 32,
                                                        ),
                                                        onPressed: () =>
                                                            Navigator.of(
                                                              context,
                                                            ).pop(),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Image.file(
                                              File(msg['image']),
                                              width: 180,
                                              height: 180,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        )
                                      : msg['image'] != null && text != null
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Image.file(
                                                File(msg['image']),
                                                width: 120,
                                                height: 120,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              text,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ],
                                        )
                                      : text != null && text.startsWith('[image:')
                                      ? Builder(
                                          builder: (context) {
                                            final imagePath = text.replaceAll(RegExp(r'^\[image:|\]$'), '');
                                            final file = File(imagePath);
                                            if (!file.existsSync()) {
                                              return Text(
                                                "Image not ready yet.",
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              );
                                            }
                                            return GestureDetector(
                                              onTap: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (_) => Dialog(
                                                    backgroundColor:
                                                        Colors.transparent,
                                                    child: Stack(
                                                      alignment:
                                                          Alignment.topRight,
                                                      children: [
                                                        PhotoView(
                                                          imageProvider:
                                                              FileImage(
                                                                File(imagePath),
                                                              ),
                                                          backgroundDecoration:
                                                              const BoxDecoration(
                                                                color: Colors
                                                                    .transparent,
                                                              ),
                                                        ),
                                                        Positioned(
                                                          top: 10,
                                                          right: 10,
                                                          child: IconButton(
                                                            icon: const Icon(
                                                              Icons.close,
                                                              color:
                                                                  Colors.white,
                                                              size: 32,
                                                            ),
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  context,
                                                                ).pop(),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.file(
                                                  File(imagePath),
                                                  width: 120,
                                                  height: 120,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            );
                                          },
                                        )
                                      : Text(
                                          text ?? '',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                          ),
                                        ),
                                ),
                              ),
                              if (isUser)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: _profileImagePath != null
                                      ? CircleAvatar(
                                          radius: 16,
                                          backgroundImage: FileImage(File(_profileImagePath!)),
                                          backgroundColor: Colors.blueAccent,
                                        )
                                      : CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Colors.blueAccent,
                                          child: Icon(
                                            Icons.person,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Show picked image preview above chat bar
                if (_pickedImage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            image: DecorationImage(
                              image: FileImage(_pickedImage!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: -8,
                          right: -8,
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.redAccent,
                            ),
                            onPressed: () {
                              setState(() {
                                _pickedImage = null;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                // Suggestion bar a bit above the chat bar
                if (_chatController.text.isEmpty &&
                    _pickedImage == null &&
                    !_isLoading &&
                    _chatHistory
                        .isEmpty) // <-- Only show suggestions if chat is empty
                  Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: SizedBox(
                      height: 78,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        scrollDirection: Axis.horizontal,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final suggestion = _suggestions[index];
                          return SuggestionCard(
                            width: cardWidth > 200 ? 200 : cardWidth,
                            title: suggestion['title']!,
                            subtitle: suggestion['subtitle']!,
                            onTap: () {
                              setState(() {
                                _chatController.text =
                                    "${suggestion['title']} - ${suggestion['subtitle']}";
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                // Bottom chat bar
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 5,
                    top: 10,
                    left: 10,
                    right: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Plus button and options
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_showOptions) ...[
                            OptionButton(
                              icon: Icons.photo_library_rounded,
                              label: "Gallery",
                              color: Colors.pinkAccent,
                              onTap: () async {
                                final picker = ImagePicker();
                                final pickedFile = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  // Optionally, you can restrict to images only (default behavior)
                                );
                                if (pickedFile != null) {
                                  setState(() {
                                    _pickedImage = File(pickedFile.path);
                                    _showOptions = false;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            OptionButton(
                              icon: Icons.camera_alt_rounded,
                              label: "Camera",
                              color: Colors.orangeAccent,
                              onTap: () async {
                                final picker = ImagePicker();
                                final pickedFile = await picker.pickImage(
                                  source: ImageSource.camera,
                                  preferredCameraDevice: CameraDevice
                                      .front, // <-- Use front camera
                                );
                                if (pickedFile != null) {
                                  setState(() {
                                    _pickedImage = File(pickedFile.path);
                                    _showOptions = false;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            OptionButton(
                              icon: Icons.insert_drive_file_rounded,
                              label: "Files",
                              color: Colors.lightBlueAccent,
                              onTap: () => _handleOption("Files"),
                            ),
                            const SizedBox(height: 10),
                          ],
                          FloatingActionButton(
                            heroTag: "plus",
                            backgroundColor: Colors.grey[900],
                            onPressed: _toggleOptions,
                            mini: true,
                            elevation: 0,
                            child: Icon(
                              _showOptions ? Icons.close : Icons.add,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      // Voice message button (mic or send)
                      FloatingActionButton(
                        heroTag: "voice",
                        backgroundColor: Colors.grey[900],
                        onPressed: () {
                          setState(() {
                            if (_isRecording) {
                              _isRecording = false;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Voice message sent!'),
                                ),
                              );
                            } else {
                              _isRecording = true;
                            }
                          });
                        },
                        mini: true,
                        elevation: 0,
                        child: Icon(
                          _isRecording ? Icons.send_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Chat text field and send button
                      Flexible(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _chatController,
                                  focusNode: _chatFocusNode,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: _currentPlaceholder,
                                    hintStyle: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                  ),
                                  minLines: 1,
                                  maxLines: 4,
                                  onSubmitted: (_) {
                                    _handleSend();
                                    FocusScope.of(
                                      context,
                                    ).requestFocus(_chatFocusNode);
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.blueAccent,
                                  size: 24,
                                ),
                                onPressed:
                                    _isLoading ||
                                        _chatController.text.trim().isEmpty
                                    ? null
                                    : _handleSend,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SuggestionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final double width;

  const SuggestionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const OptionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey[900],
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      shadowColor: color.withAlpha((0.18 * 255).toInt()),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor: color.withAlpha((0.18 * 255).toInt()),
                radius: 16,
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnimatedDots extends StatefulWidget {
  const AnimatedDots({super.key});

  @override
  AnimatedDotsState createState() => AnimatedDotsState();
}

class AnimatedDotsState extends State<AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _dotCount;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat();
    _dotCount = StepTween(
      begin: 1,
      end: 3,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dotCount,
      builder: (context, child) {
        String dots = '.' * _dotCount.value;
        return Text(
          'AI is typing$dots',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontStyle: FontStyle.italic,
          ),
        );
      },
    );
  }
}

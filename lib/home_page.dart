import 'dart:math';
import 'package:flutter/material.dart';
import 'profile_page.dart';
import 'animated_circle.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<String> _chatHistory = [
    "Redesign my living room",
    "Make my bedroom cozy",
    "Add plants to my workspace",
    "Suggest furniture layout",
  ];

  final TextEditingController _chatController = TextEditingController();
  bool _showOptions = false;
  bool _isRecording = false;
  late AnimationController _bgController;
  late AnimationController _optionController;

  final List<Map<String, String>> _suggestions = [
    {'title': 'Redesign my living room', 'subtitle': 'with a modern style'},
    {'title': 'Make my bedroom cozy', 'subtitle': 'using warm colors'},
    {'title': 'Add plants to my workspace', 'subtitle': 'for a fresh look'},
    {'title': 'Suggest furniture layout', 'subtitle': 'for a small apartment'},
    {'title': 'Create a minimalist kitchen', 'subtitle': 'with smart storage'},
    {'title': 'Decorate my dining area', 'subtitle': 'for family gatherings'},
  ];

  final List<String> _placeholders = [
    "What's on your mind?",
    "Tell me your plan",
    "How can I help you today?",
    "Share your idea...",
    "What would you like to do?",
  ];

  late String _currentPlaceholder;
  final ScrollController _chatScrollController = ScrollController();
  File? _pickedImage;

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

    _setRandomPlaceholder();

    _chatController.addListener(() {
      setState(() {});
    });
  }

  void _setRandomPlaceholder() {
    final random = Random();
    _currentPlaceholder = _placeholders[random.nextInt(_placeholders.length)];
  }

  @override
  void dispose() {
    _chatController.dispose();
    _bgController.dispose();
    _optionController.dispose();
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

  void _handleSend() {
    final text = _chatController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _chatHistory.add(text);
        _chatController.clear();
        _setRandomPlaceholder();
      });
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
              Expanded(
                child: ListView.builder(
                  itemCount: _chatHistory.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text(
                        _chatHistory[index],
                        style: const TextStyle(color: Colors.white),
                      ),
                      leading: const Icon(Icons.history, color: Colors.white54),
                      onTap: () {
                        _chatController.text = _chatHistory[index];
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
              color: Colors.blueAccent.withOpacity(0.12),
              size: 250,
              duration: 3000,
            ),
          ),
          Positioned(
            bottom: -80,
            right: -80,
            child: AnimatedCircle(
              color: Colors.purpleAccent.withOpacity(0.10),
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
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ProfilePage(
                                userName: 'Admin',
                                email: 'admin@gmail.com',
                                imagePath: null,
                              ),
                            ),
                          );
                        },
                        child: const CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white24,
                          child: Icon(
                            Icons.person,
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
                        if (msg.startsWith("[image:")) {
                          final path = msg.substring(7, msg.length - 1);
                          return Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.shade100.withOpacity(
                                  0.2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(path),
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          );
                        }
                        return Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.shade100.withOpacity(
                                0.2,
                              ),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(18),
                                topRight: Radius.circular(18),
                                bottomLeft: Radius.circular(18),
                                bottomRight: Radius.circular(4),
                              ),
                            ),
                            child: Text(
                              _chatHistory[index],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
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
                        Positioned(
                          bottom: -8,
                          right: -8,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                            ),
                            child: const Text(
                              "Allow",
                              style: TextStyle(color: Colors.white),
                            ),
                            onPressed: () {
                              setState(() {
                                _chatHistory.add(
                                  "[image:${_pickedImage!.path}]",
                                );
                                _pickedImage = null;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                // Suggestion bar a bit above the chat bar
                if (_chatController.text.isEmpty && _pickedImage == null)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 28,
                    ), // Moderate space above chat bar
                    child: SizedBox(
                      height: 78,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        scrollDirection: Axis.horizontal,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final suggestion = _suggestions[index];
                          return _SuggestionCard(
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
                            _OptionButton(
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
                            _OptionButton(
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
                            _OptionButton(
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
                                  onTap: () {
                                    setState(() {
                                      _setRandomPlaceholder();
                                    });
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.blueAccent,
                                  size: 24,
                                ),
                                onPressed: _handleSend,
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

class _SuggestionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final double width;

  const _SuggestionCard({
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

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _OptionButton({
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
      shadowColor: color.withOpacity(0.18),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.18),
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

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chat_service.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:camera/camera.dart';

class AddUserPage extends StatefulWidget {
  const AddUserPage({super.key});

  @override
  State<AddUserPage> createState() => _AddUserPageState();
}

class _AddUserPageState extends State<AddUserPage> {
  List<String> _users = [];
  String? _currentUserEmail;
  List<Map<String, dynamic>> _firestoreUsers = [];
  Map<String, double> _chatLastTimestamps = {};
  Set<String> _unreadChats = {};
  Map<String, StreamSubscription> _chatSubscriptions = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadChatUsers();
  }

  @override
  void dispose() {
    for (final sub in _chatSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserEmail = prefs.getString('userEmail') ?? '';
    });
  }

  Future<void> _loadChatUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final userEmail = prefs.getString('userEmail') ?? '';
    final users = prefs.getStringList('chat_users_$userEmail') ?? [];
    setState(() {
      _users = users;
    });
  }

  Future<void> _saveChatUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final userEmail = prefs.getString('userEmail') ?? '';
    await prefs.setStringList('chat_users_$userEmail', _users);
  }

  Future<void> _fetchFirestoreUsers() async {
    final snapshot = await ChatService.getAllUsers();
    setState(() {
      _firestoreUsers = snapshot
          .where((u) => u['email'] != _currentUserEmail && u['name'].isNotEmpty)
          .toList();
    });
  }

  void _openChat(String userEmail) {
    if (_currentUserEmail == null) return;
    setState(() {
      _unreadChats.remove(userEmail); // Mark as read when opened
    });
    final user = _firestoreUsers.firstWhere(
      (u) => u['email'] == userEmail,
      orElse: () => {},
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserChatPage(
          userName: user['name'] ?? userEmail,
          userEmail: userEmail,
          currentUserEmail: _currentUserEmail!,
        ),
      ),
    ).then((_) {
      // When returning from chat, re-check unread status
      setState(() {
        _unreadChats.remove(userEmail);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchFirestoreUsers();
    _listenForChatUpdates();
  }

  void _listenForChatUpdates() {
    for (final chatUserEmail in _users) {
      final currentUser = _currentUserEmail;
      if (currentUser == null) continue;
      // Cancel previous subscription if exists
      _chatSubscriptions[chatUserEmail]?.cancel();
      _chatSubscriptions[chatUserEmail] =
          ChatService.chatStream(
            user1: currentUser,
            user2: chatUserEmail,
          ).listen((messages) {
            if (messages.isNotEmpty) {
              final lastMsg = messages.last;
              final lastTimestamp = (lastMsg['timestamp'] ?? 0).toDouble();
              final isFromOther =
                  (lastMsg['sender'] as String).trim().toLowerCase() !=
                  currentUser.trim().toLowerCase();
              setState(() {
                _chatLastTimestamps[chatUserEmail] = lastTimestamp;
                // Only mark as unread if the last message is from the other user and is new
                if (isFromOther &&
                    (_unreadChats.contains(chatUserEmail) == false ||
                        _chatLastTimestamps[chatUserEmail] != lastTimestamp)) {
                  _unreadChats.add(chatUserEmail);
                }
                // Move chat to top if new message from other user
                if (isFromOther) {
                  _users.remove(chatUserEmail);
                  _users.insert(0, chatUserEmail);
                }
              });
            }
          });
    }
    // Remove unread status for chats that are no longer in the list
    setState(() {
      _unreadChats.removeWhere((email) => !_users.contains(email));
    });
  }

  List<String> get _sortedUsers {
    // Separate users with and without messages
    final usersWithMsg = _users
        .where((u) => (_chatLastTimestamps[u] ?? 0) > 0)
        .toList();
    final usersNoMsg = _users
        .where((u) => (_chatLastTimestamps[u] ?? 0) == 0)
        .toList();
    // Sort users with messages by recency (descending)
    usersWithMsg.sort((a, b) {
      final aLastMsg = _chatLastTimestamps[a] ?? 0;
      final bLastMsg = _chatLastTimestamps[b] ?? 0;
      return bLastMsg.compareTo(aLastMsg);
    });
    // Keep users with no messages at the bottom, in their original order
    return [...usersWithMsg, ...usersNoMsg];
  }

  void _showAddUserSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        String? selectedUserEmail;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select user to chat',
                    style: TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    value: selectedUserEmail,
                    items: _firestoreUsers.map((user) {
                      return DropdownMenuItem<String>(
                        value: user['email'],
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.blueAccent.shade100,
                              radius: 14,
                              child: Text(
                                user['name'].isNotEmpty
                                    ? user['name'][0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              user['name'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setModalState(() {
                        selectedUserEmail = value;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'User',
                      labelStyle: const TextStyle(
                        color: Colors.blueAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Colors.blueAccent,
                          width: 1.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Colors.blueAccent,
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey[850],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    dropdownColor: Colors.grey[850],
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                      onPressed: () async {
                        if (selectedUserEmail == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select a user.'),
                            ),
                          );
                          return;
                        }
                        if (_users.contains(selectedUserEmail) ||
                            selectedUserEmail == _currentUserEmail) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('User already added or is you.'),
                            ),
                          );
                          return;
                        }
                        setState(() {
                          _users.add(selectedUserEmail!);
                        });
                        await _saveChatUsers();
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('User added!')));
                      },
                      child: const Text(
                        'Add',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
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
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 22, // smaller
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "ModifAI Message",
                        style: TextStyle(
                          color: Colors.blueAccent.shade100,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Colors.blueAccent,
                          size: 28,
                        ),
                        onPressed: _showAddUserSheet,
                        tooltip: 'Add user to chat',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 28),
                        const Text(
                          'Chats',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: _users.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No chats yet.',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 16,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _sortedUsers.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final chatUserEmail = _sortedUsers[index];
                                    final chatUser = _firestoreUsers.firstWhere(
                                      (u) => u['email'] == chatUserEmail,
                                      orElse: () => <String, dynamic>{},
                                    );
                                    final isHighlighted = _unreadChats.contains(
                                      chatUserEmail,
                                    );
                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 500,
                                      ),
                                      curve: Curves.easeInOut,
                                      decoration: BoxDecoration(
                                        color: isHighlighted
                                            ? Colors.blueAccent.withOpacity(
                                                0.18,
                                              )
                                            : Colors.grey[850],
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: isHighlighted
                                            ? [
                                                BoxShadow(
                                                  color: Colors.blueAccent
                                                      .withOpacity(0.18),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ]
                                            : [],
                                      ),
                                      child: ListTile(
                                        leading: Stack(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor:
                                                  Colors.blueAccent,
                                              child: Text(
                                                (chatUser['name'] ??
                                                            chatUserEmail)
                                                        .isNotEmpty
                                                    ? (chatUser['name'] ??
                                                              chatUserEmail)[0]
                                                          .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (isHighlighted)
                                              Positioned(
                                                right: 0,
                                                bottom: 0,
                                                child: Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: BoxDecoration(
                                                    color: Colors.blueAccent,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.white,
                                                      width: 2,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        title: Text(
                                          chatUser['name'] ?? chatUserEmail,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Text(
                                          chatUserEmail,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                          ),
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(
                                            Icons.chat_bubble_outline,
                                            color: Colors.blueAccent,
                                            size: 22,
                                          ),
                                          onPressed: () =>
                                              _openChat(chatUserEmail),
                                        ),
                                        onTap: () => _openChat(chatUserEmail),
                                      ),
                                    );
                                  },
                                ),
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
    );
  }
}

class AnimatedCircle extends StatelessWidget {
  final Color color;
  final double size;
  final int duration;

  const AnimatedCircle({
    super.key,
    required this.color,
    required this.size,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Duration(milliseconds: duration),
      curve: Curves.easeInOut,
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class UserChatPage extends StatefulWidget {
  final String userName;
  final String userEmail;
  final String currentUserEmail;
  const UserChatPage({
    super.key,
    required this.userName,
    required this.userEmail,
    required this.currentUserEmail,
  });

  @override
  State<UserChatPage> createState() => _UserChatPageState();
}

class _UserChatPageState extends State<UserChatPage> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _receiverName;
  String? _senderName;
  bool _isRecording = false;
  // For image picker
  String? _pickedImagePath;

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  Future<void> _loadNames() async {
    // Try to get both sender and receiver names from Firestore
    final users = await ChatService.getAllUsers();
    final sender = users.firstWhere(
      (u) =>
          (u['email'] as String).trim().toLowerCase() ==
          widget.currentUserEmail.trim().toLowerCase(),
      orElse: () => {'name': widget.currentUserEmail},
    );
    final receiver = users.firstWhere(
      (u) =>
          (u['email'] as String).trim().toLowerCase() ==
          widget.userEmail.trim().toLowerCase(),
      orElse: () => {'name': widget.userEmail},
    );
    setState(() {
      _senderName = sender['name'] ?? widget.currentUserEmail;
      _receiverName = receiver['name'] ?? widget.userEmail;
    });
  }

  String _displayName(String? nameOrEmail) {
    if (nameOrEmail == null) return '?';
    if (nameOrEmail.contains('@')) {
      // Convert email to username: before @, replace . with _, capitalize each part
      final user = nameOrEmail.split('@')[0].replaceAll('.', '_');
      return user
          .split('_')
          .map((s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '')
          .join('_');
    }
    // Capitalize each word in name
    return nameOrEmail
        .split(' ')
        .map((s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '')
        .join(' ');
  }

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    // Use usernames for sender and receiver
    String senderUsername = _displayName(_senderName);
    String receiverUsername = _displayName(_receiverName);
    try {
      await ChatService.sendMessage(
        sender: senderUsername,
        receiver: receiverUsername,
        text: text,
        timestamp: now,
      );
      _msgController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
    }
  }

  void _pickImage() async {
    // Use custom camera screen with back button
    final imagePath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          onImageCaptured: (path) {
            Navigator.of(context).pop(path);
          },
        ),
      ),
    );
    if (imagePath != null) {
      setState(() {
        _pickedImagePath = imagePath;
      });
    }
  }

  void _pickGalleryImage() async {
    final picker = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picker != null) {
      setState(() {
        _pickedImagePath = picker.path;
      });
    }
  }

  void _removePickedImage() {
    setState(() {
      _pickedImagePath = null;
    });
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });
    // Implement actual recording logic as needed
  }

  @override
  Widget build(BuildContext context) {
    final sender = widget.currentUserEmail.trim().toLowerCase();
    final receiver = widget.userEmail.trim().toLowerCase();
    final senderDisplay = _displayName(_senderName);
    final receiverDisplay = _displayName(_receiverName);
    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
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
                // Top bar with back, avatar, name, call, video call
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
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        child: Text(
                          widget.userName.isNotEmpty
                              ? widget.userName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.userName,
                              style: TextStyle(
                                color: Colors.blueAccent.shade100,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              widget.userEmail,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Container(
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(
                              10,
                            ), // square with rounded corners
                            boxShadow: [
                              BoxShadow(
                                color: Colors.greenAccent.withOpacity(0.18),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(8),
                          child: const Icon(
                            Icons.call_rounded,
                            color: Colors.greenAccent,
                            size: 28,
                          ),
                        ),
                        onPressed: () {
                          // Implement call logic
                        },
                        tooltip: 'Call',
                      ),
                      IconButton(
                        icon: Container(
                          decoration: BoxDecoration(
                            color: Colors.purpleAccent.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(
                              10,
                            ), // square with rounded corners
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purpleAccent.withOpacity(0.18),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(8),
                          child: const Icon(
                            Icons.videocam_rounded,
                            color: Colors.purpleAccent,
                            size: 28,
                          ),
                        ),
                        onPressed: () {
                          // Implement video call logic
                        },
                        tooltip: 'Video Call',
                      ),
                    ],
                  ),
                ),
                // Picked image preview
                if (_pickedImagePath != null)
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
                              image: FileImage(File(_pickedImagePath!)),
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
                              size: 20,
                            ), // smaller
                            onPressed: _removePickedImage,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Chat messages
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: ChatService.chatStream(
                      user1: sender,
                      user2: receiver,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final messages = snapshot.data ?? [];
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(
                            _scrollController.position.maxScrollExtent,
                          );
                        }
                      });
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 12,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isMe =
                              (msg['sender'] as String).trim() == senderDisplay;
                          return Row(
                            mainAxisAlignment: isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Column(
                                    children: [
                                      CircleAvatar(
                                        radius: 14, // smaller
                                        backgroundColor: Colors.blueAccent,
                                        child: Text(
                                          receiverDisplay.isNotEmpty
                                              ? receiverDisplay[0]
                                              : '?',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ), // smaller
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        receiverDisplay,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ), // smaller
                                      ),
                                    ],
                                  ),
                                ),
                              Flexible(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 8,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? Colors.blueAccent.shade100.withAlpha(
                                            50,
                                          )
                                        : Colors.grey[600],
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: isMe
                                          ? const Radius.circular(16)
                                          : const Radius.circular(4),
                                      bottomRight: isMe
                                          ? const Radius.circular(4)
                                          : const Radius.circular(16),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    msg['text'] ?? '',
                                    style: TextStyle(
                                      color: isMe
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              if (isMe)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Column(
                                    children: [
                                      CircleAvatar(
                                        radius: 14, // smaller
                                        backgroundColor: Colors.blueAccent,
                                        child: Text(
                                          senderDisplay.isNotEmpty
                                              ? senderDisplay[0]
                                              : '?',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ), // smaller
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        senderDisplay,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ), // smaller
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                // Chat input bar with camera, gallery, mic, send
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 10,
                    left: 10,
                    right: 10,
                    top: 5,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Camera icon
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(
                            10,
                          ), // square with rounded corners
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.orangeAccent,
                            size: 22,
                          ),
                          onPressed: _pickImage,
                          tooltip: 'Camera',
                        ),
                      ),
                      const SizedBox(width: 2),
                      // Gallery icon
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.pinkAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(
                            10,
                          ), // square with rounded corners
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.photo_library_rounded,
                            color: Colors.pinkAccent,
                            size: 22,
                          ),
                          onPressed: _pickGalleryImage,
                          tooltip: 'Gallery',
                        ),
                      ),
                      const SizedBox(width: 2),
                      // Mic/Send icon
                      Container(
                        decoration: BoxDecoration(
                          color:
                              (_isRecording
                                      ? Colors.greenAccent
                                      : Colors.blueAccent)
                                  .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(
                            10,
                          ), // square with rounded corners
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isRecording
                                ? Icons.send_rounded
                                : Icons.mic_rounded,
                            color: _isRecording
                                ? Colors.greenAccent
                                : Colors.blueAccent,
                            size: 22,
                          ),
                          onPressed: _toggleRecording,
                          tooltip: _isRecording ? 'Send Voice' : 'Record',
                        ),
                      ),
                      const SizedBox(width: 2),
                      // Chat box
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
                                  controller: _msgController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    hintText: 'Type a message...',
                                    hintStyle: TextStyle(color: Colors.white54),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.lightBlueAccent,
                                  size: 24,
                                ), // smaller
                                onPressed: _sendMessage,
                                tooltip: 'Send',
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

class CameraScreen extends StatefulWidget {
  final void Function(String? imagePath) onImageCaptured;
  const CameraScreen({Key? key, required this.onImageCaptured})
    : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isReady = false;
  bool _isTakingPicture = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _controller = CameraController(_cameras![0], ResolutionPreset.medium);
      await _controller!.initialize();
      setState(() {
        _isReady = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isTakingPicture)
      return;
    setState(() => _isTakingPicture = true);
    try {
      final XFile file = await _controller!.takePicture();
      widget.onImageCaptured(file.path);
      Navigator.of(context).pop();
    } catch (_) {
      setState(() => _isTakingPicture = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isReady && _controller != null)
            Center(child: CameraPreview(_controller!)),
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 32,
              ),
              onPressed: () {
                widget.onImageCaptured(null); // Cancel
                Navigator.of(context).pop();
              },
            ),
          ),
          if (_isReady)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: FloatingActionButton(
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.black,
                    size: 32,
                  ),
                  onPressed: _takePicture,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

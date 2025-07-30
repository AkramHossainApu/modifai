import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chat_service.dart';
import 'dart:async';

class AddUserPage extends StatefulWidget {
  const AddUserPage({super.key});

  @override
  State<AddUserPage> createState() => _AddUserPageState();
}

class _AddUserPageState extends State<AddUserPage> {
  String? _error;
  List<String> _users = [];
  String? _currentUserEmail;
  List<Map<String, dynamic>> _firestoreUsers = [];
  String? _selectedDropdownUserEmail;
  Map<String, dynamic>? _selectedDropdownUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadChatUsers();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserEmail = prefs.getString('userEmail') ?? '';
    });
  }

  Future<void> _loadChatUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final users = prefs.getStringList('chat_users') ?? [];
    setState(() {
      _users = users;
    });
  }

  Future<void> _saveChatUsers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('chat_users', _users);
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
    final user = _firestoreUsers.firstWhere((u) => u['email'] == userEmail, orElse: () => {});
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserChatPage(
          userName: user['name'] ?? userEmail,
          userEmail: userEmail,
          currentUserEmail: _currentUserEmail!,
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchFirestoreUsers();
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
                          size: 28,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "Start a Chat",
                        style: TextStyle(
                          color: Colors.blueAccent.shade100,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          color: Colors.grey[900],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 8,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.person_add, color: Colors.blueAccent),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: _selectedDropdownUserEmail,
                                        items: _firestoreUsers.map((user) {
                                          return DropdownMenuItem<String>(
                                            value: user['email'],
                                            child: Text(
                                              user['name'],
                                              style: const TextStyle(color: Colors.white),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (value) {
                                          setState(() {
                                            _selectedDropdownUserEmail = value;
                                            _selectedDropdownUser = _firestoreUsers.firstWhere((u) => u['email'] == value);
                                          });
                                        },
                                        decoration: InputDecoration(
                                          labelText: 'Select user to chat',
                                          labelStyle: const TextStyle(color: Colors.white70),
                                          border: InputBorder.none,
                                          filled: true,
                                          fillColor: Colors.grey[850],
                                        ),
                                        dropdownColor: Colors.grey[850],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        elevation: 4,
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                      ),
                                      onPressed: () async {
                                        if (_selectedDropdownUser == null) {
                                          setState(() => _error = 'Please select a user.');
                                          return;
                                        }
                                        if (_users.contains(_selectedDropdownUserEmail) || _selectedDropdownUserEmail == _currentUserEmail) {
                                          setState(() => _error = 'User already added or is you.');
                                          return;
                                        }
                                        setState(() {
                                          _users.add(_selectedDropdownUserEmail!);
                                          _selectedDropdownUserEmail = null;
                                          _selectedDropdownUser = null;
                                          _error = null;
                                        });
                                        await _saveChatUsers();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('User "${_selectedDropdownUser?['name'] ?? _selectedDropdownUserEmail}" added!')),
                                        );
                                      },
                                      child: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                    ),
                                  ],
                                ),
                                if (_error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                                  ),
                              ],
                            ),
                          ),
                        ),
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
                                  child: Text('No chats yet.', style: TextStyle(color: Colors.white54, fontSize: 16)),
                                )
                              : ListView.separated(
                                  itemCount: _users.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final chatUserEmail = _users[index];
                                    final chatUser = _firestoreUsers.firstWhere(
                                      (u) => u['email'] == chatUserEmail,
                                      orElse: () => <String, dynamic>{},
                                    );
                                    return Card(
                                      color: Colors.grey[850],
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 4,
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.blueAccent,
                                          child: Text(
                                            (chatUser['name'] ?? chatUserEmail).isNotEmpty ? (chatUser['name'] ?? chatUserEmail)[0].toUpperCase() : '?',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        title: Text(
                                          chatUser['name'] ?? chatUserEmail,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                        ),
                                        subtitle: Text(
                                          chatUserEmail,
                                          style: const TextStyle(color: Colors.white54),
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.chat_bubble_outline, color: Colors.blueAccent),
                                          onPressed: () => _openChat(chatUserEmail),
                                        ),
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
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
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

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  Future<void> _loadNames() async {
    // Try to get both sender and receiver names from Firestore
    final users = await ChatService.getAllUsers();
    final sender = users.firstWhere(
      (u) => (u['email'] as String).trim().toLowerCase() == widget.currentUserEmail.trim().toLowerCase(),
      orElse: () => {'name': widget.currentUserEmail},
    );
    final receiver = users.firstWhere(
      (u) => (u['email'] as String).trim().toLowerCase() == widget.userEmail.trim().toLowerCase(),
      orElse: () => {'name': widget.userEmail},
    );
    setState(() {
      _senderName = sender['name'] ?? widget.currentUserEmail;
      _receiverName = receiver['name'] ?? widget.userEmail;
    });
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

  String _displayName(String? nameOrEmail) {
    if (nameOrEmail == null) return '?';
    if (nameOrEmail.contains('@')) {
      // Convert email to username: before @, replace . with _, capitalize each part
      final user = nameOrEmail.split('@')[0].replaceAll('.', '_');
      return user.split('_').map((s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '').join('_');
    }
    // Capitalize each word in name
    return nameOrEmail.split(' ').map((s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final sender = widget.currentUserEmail.trim().toLowerCase();
    final receiver = widget.userEmail.trim().toLowerCase();
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
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        child: Text(
                          widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
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
                      const Spacer(),
                    ],
                  ),
                ),
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
                          // Compare sender in message to the current user's username
                          final senderDisplay = _displayName(_senderName);
                          final receiverDisplay = _displayName(_receiverName);
                          final isMe = (msg['sender'] as String).trim() == senderDisplay;
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
                                        radius: 16,
                                        backgroundColor: Colors.blueAccent,
                                        child: Text(
                                          receiverDisplay.isNotEmpty ? receiverDisplay[0] : '?',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        receiverDisplay,
                                        style: const TextStyle(color: Colors.white54, fontSize: 11),
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
                                    color: isMe ? Colors.blueAccent.shade100.withAlpha(50) : Colors.grey[600],
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
                                      color: isMe ? Colors.white : Colors.white70,
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
                                        radius: 16,
                                        backgroundColor: Colors.blueAccent,
                                        child: Text(
                                          senderDisplay.isNotEmpty ? senderDisplay[0] : '?',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        senderDisplay,
                                        style: const TextStyle(color: Colors.white54, fontSize: 11),
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
                Container(
                  color: const Color(0xFF23242B),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.blueAccent),
                        onPressed: _sendMessage,
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

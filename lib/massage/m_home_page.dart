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
  String? _selectedDropdownUserName;
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

  void _openChat(String username) {
    if (_currentUserEmail == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserChatPage(userName: username, currentUser: _currentUserEmail!),
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
                                        value: _selectedDropdownUserName,
                                        items: _firestoreUsers.map((user) {
                                          return DropdownMenuItem<String>(
                                            value: user['name'],
                                            child: Text(
                                              user['name'],
                                              style: const TextStyle(color: Colors.white),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (value) {
                                          setState(() {
                                            _selectedDropdownUserName = value;
                                            _selectedDropdownUser = _firestoreUsers.firstWhere((u) => u['name'] == value);
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
                                        if (_users.contains(_selectedDropdownUserName) || _selectedDropdownUserName == _currentUserEmail) {
                                          setState(() => _error = 'User already added or is you.');
                                          return;
                                        }
                                        setState(() {
                                          _users.add(_selectedDropdownUserName!);
                                          _selectedDropdownUserName = null;
                                          _selectedDropdownUser = null;
                                          _error = null;
                                        });
                                        await _saveChatUsers();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('User "$_selectedDropdownUserName" added!')),
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
                                    final chatUserName = _users[index];
                                    final chatUser = _firestoreUsers.firstWhere(
                                      (u) => u['name'] == chatUserName,
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
                                            chatUserName.isNotEmpty ? chatUserName[0].toUpperCase() : '?',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        title: Text(
                                          chatUserName,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                        ),
                                        subtitle: Text(
                                          chatUser['email'] ?? '',
                                          style: const TextStyle(color: Colors.white54),
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.chat_bubble_outline, color: Colors.blueAccent),
                                          onPressed: () => _openChat(chatUserName),
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
  final String currentUser;
  const UserChatPage({
    super.key,
    required this.userName,
    required this.currentUser,
  });

  @override
  State<UserChatPage> createState() => _UserChatPageState();
}

class _UserChatPageState extends State<UserChatPage> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    try {
      await ChatService.sendMessage(
        sender: widget.currentUser,
        receiver: widget.userName,
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
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        child: Text(
                          widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.userName,
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
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: ChatService.chatStream(
                      user1: widget.currentUser,
                      user2: widget.userName,
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
                          final isMe = msg['sender'] == widget.currentUser;
                          return Row(
                            mainAxisAlignment: isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.blueAccent,
                                    child: Text(
                                      widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
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
                                  child: CircleAvatar(
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

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
  final List<String> _users = [];
  String? _currentUserEmail;
  List<Map<String, dynamic>> _firestoreUsers = [];
  String? _selectedDropdownUserName;
  Map<String, dynamic>? _selectedDropdownUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchFirestoreUsers();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserEmail = prefs.getString('userEmail') ?? '';
    });
  }

  Future<void> _fetchFirestoreUsers() async {
    // Fetch all users from Firestore 'users' collection
    final snapshot = await ChatService.getAllUsers();
    setState(() {
      // Only exclude current user by email
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
        builder: (context) =>
            UserChatPage(userName: username, currentUser: _currentUserEmail!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF23242B),
        title: const Text(
          'Start a Chat',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                                _selectedDropdownUser = _firestoreUsers
                                    .firstWhere((u) => u['name'] == value);
                              });
                            },
                            decoration: InputDecoration(
                              labelText: 'Select user to chat',
                              labelStyle: const TextStyle(
                                color: Colors.white70,
                              ),
                              border: InputBorder.none,
                              filled: true,
                              fillColor: Colors.grey[850],
                            ),
                            dropdownColor: Colors.grey[850],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            if (_selectedDropdownUser == null) {
                              setState(() => _error = 'Please select a user.');
                              return;
                            }
                            if (_users.contains(_selectedDropdownUserName) ||
                                _selectedDropdownUserName ==
                                    _currentUserEmail) {
                              setState(
                                () => _error = 'User already added or is you.',
                              );
                              return;
                            }
                            setState(() {
                              _users.add(_selectedDropdownUserName!);
                              _selectedDropdownUserName = null;
                              _selectedDropdownUser = null;
                              _error = null;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'User "$_selectedDropdownUserName" added!',
                                ),
                              ),
                            );
                          },
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Chats',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _users.isEmpty
                  ? const Center(
                      child: Text(
                        'No chats yet.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final chatUserName = _users[index];
                        final chatUser = _firestoreUsers.firstWhere(
                          (u) => u['name'] == chatUserName,
                          orElse: () => <String, dynamic>{},
                        );
                        return Card(
                          color: Colors.grey[850],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blueAccent,
                              child: Text(
                                chatUserName.isNotEmpty
                                    ? chatUserName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              chatUserName,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              chatUser['email'] ?? '',
                              style: const TextStyle(color: Colors.white54),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                color: Colors.blueAccent,
                              ),
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF23242B),
        title: Row(
          children: [
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
            Text(widget.userName, style: const TextStyle(color: Colors.white)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(
        children: [
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
                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blueAccent : Colors.grey[800],
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
                              color: Colors.black.withValues(alpha: 0.08),
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
    );
  }
}

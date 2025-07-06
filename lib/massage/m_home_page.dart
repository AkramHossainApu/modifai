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
  final TextEditingController _usernameController = TextEditingController();
  String? _error;
  final List<String> _users = [];
  String? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUser = prefs.getString('userName') ?? 'Me';
    });
  }

  void _addUser() {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'Please enter a username.');
      return;
    }
    if (_users.contains(username) || username == _currentUser) {
      setState(() => _error = 'User already added or is you.');
      return;
    }
    setState(() {
      _users.add(username);
      _usernameController.clear();
      _error = null;
    });
  }

  void _openChat(String username) {
    if (_currentUser == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserChatPage(
          userName: username,
          currentUser: _currentUser!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF23242B),
        title: const Text('Start a Chat', style: TextStyle(color: Colors.white)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.person_add, color: Colors.blueAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _usernameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Enter username',
                          labelStyle: const TextStyle(color: Colors.white70),
                          errorText: _error,
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _addUser,
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Chats', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: _users.isEmpty
                  ? const Center(
                      child: Text('No users added yet.', style: TextStyle(color: Colors.white54)),
                    )
                  : ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return Card(
                          color: Colors.grey[850],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blueAccent,
                              child: Text(user.isNotEmpty ? user[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                            ),
                            title: Text(user, style: const TextStyle(color: Colors.white)),
                            trailing: IconButton(
                              icon: const Icon(Icons.chat_bubble_outline, color: Colors.blueAccent),
                              onPressed: () => _openChat(user),
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
  const UserChatPage({super.key, required this.userName, required this.currentUser});

  @override
  State<UserChatPage> createState() => _UserChatPageState();
}

class _UserChatPageState extends State<UserChatPage> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _loading = true);
    try {
      final history = await ChatService.getChatHistory(
        user1: widget.currentUser,
        user2: widget.userName,
      );
      setState(() {
        _messages = history;
        _loading = false;
      });
      // Scroll to bottom
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load chat history: $e')),
      );
    }
  }

  Future<void> _sendMessage() async {
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
      await _fetchHistory();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
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
              child: Text(widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg['sender'] == widget.currentUser;
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blueAccent : Colors.grey[800],
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                              bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
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
                            style: TextStyle(color: isMe ? Colors.white : Colors.white70, fontSize: 16),
                          ),
                        ),
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

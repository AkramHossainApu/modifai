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
  String? _selectedDropdownUserName;
  Map<String, dynamic>? _selectedDropdownUser;
  List<Map<String, dynamic>> _allUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserAndUsers();
    _loadFriendRequestsAndFriends();
  }

  List<String> _friendRequests = [];
  List<String> _friends = [];

  Future<void> _loadCurrentUserAndUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('userEmail') ?? '';
      setState(() {
        _currentUserEmail = email;
      });
      final users = await ChatService.getAllUsers();
      print('Fetched users from Firestore:');
      for (final u in users) {
        print(u);
      }
      final filtered = users
          .where((u) => u['email'] != email && (u['name'] ?? '').isNotEmpty)
          .toList();
      setState(() {
        _allUsers = filtered;
        _isLoading = false;
        _error = filtered.isEmpty
            ? 'No users found or userEmail missing.'
            : null;
      });
    } catch (e) {
      print('Error loading users: $e');
      setState(() {
        _isLoading = false;
        _error = 'Failed to load users: $e';
      });
    }
  }

  Future<void> _loadFriendRequestsAndFriends() async {
    if (_currentUserEmail == null) return;
    final reqs = await ChatService.getFriendRequests(_currentUserEmail!);
    final frs = await ChatService.getFriends(_currentUserEmail!);
    setState(() {
      _friendRequests = reqs;
      _friends = frs;
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

  Future<void> _sendFriendRequest(String toEmail) async {
    if (_currentUserEmail == null) return;
    await ChatService.sendFriendRequest(_currentUserEmail!, toEmail);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Friend request sent to $toEmail')));
  }

  Future<void> _acceptFriendRequest(String fromEmail) async {
    if (_currentUserEmail == null) return;
    await ChatService.acceptFriendRequest(_currentUserEmail!, fromEmail);
    await _loadFriendRequestsAndFriends();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('You are now friends with $fromEmail')),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_friendRequests.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Friend Requests',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ..._friendRequests.map(
                            (email) => Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    email,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () => _acceptFriendRequest(email),
                                  child: const Text('Accept'),
                                ),
                              ],
                            ),
                          ),
                          const Divider(color: Colors.white24),
                        ],
                      ),
                    const Text(
                      'All Users',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _allUsers.isEmpty
                        ? const Text(
                            'No other users found',
                            style: TextStyle(color: Colors.white54),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _allUsers.length,
                            itemBuilder: (context, idx) {
                              final user = _allUsers[idx];
                              final email = user['email'];
                              String buttonLabel;
                              VoidCallback? buttonAction;
                              Color? buttonColor;
                              if (_friends.contains(email)) {
                                buttonLabel = 'Chat';
                                buttonAction = () {
                                  setState(() {
                                    _users.add(user['name']);
                                    _selectedDropdownUserName = null;
                                    _selectedDropdownUser = null;
                                    _error = null;
                                  });
                                };
                                buttonColor = Colors.blueAccent;
                              } else if (_friendRequests.contains(email)) {
                                buttonLabel = 'Requested';
                                buttonAction = null;
                                buttonColor = Colors.orangeAccent;
                              } else {
                                buttonLabel = 'Add';
                                buttonAction = () => _sendFriendRequest(email);
                                buttonColor = Colors.green;
                              }
                              return ListTile(
                                leading: const Icon(
                                  Icons.person,
                                  color: Colors.white70,
                                ),
                                title: Text(
                                  user['name'],
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  email,
                                  style: const TextStyle(color: Colors.white54),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: buttonAction,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: buttonColor,
                                  ),
                                  child: Text(buttonLabel),
                                ),
                              );
                            },
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
                        final chatUser = _allUsers.firstWhere(
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

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chat_service.dart';
import '../services/group_chat_service.dart';
import 'user_chat_page.dart';
import 'animated_circle.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  late final ValueNotifier<bool> _fabExpanded = ValueNotifier(false);

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
    _fabExpanded.dispose();
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

  Future<void> _loadAllChatsForCurrentUser() async {
    if (_currentUserEmail == null) return;
    final username = _currentUserEmail!.split('@')[0];
    // Fetch user-to-user chat IDs from Firestore
    final chatDocs =
        await ChatService.getChatDocumentIds(); // Should return List<String>
    // Robustly match normal chats (user-to-user, 2 parts, any order)
    final userChats = chatDocs.where((id) {
      final parts = id.split('_');
      return parts.length == 2 && parts.contains(username);
    }).toList();
    // Fetch group chat IDs from Firestore
    final groupDocs =
        await GroupChatService.getGroupChatDocumentIds(); // Should return List<String>
    final groupChats = groupDocs
        .where(
          (id) => id.split('_').contains(username) && id.split('_').length > 2,
        )
        .toList();
    // Merge with local users
    final allChats = {..._users, ...userChats, ...groupChats}.toList();
    setState(() {
      _users = allChats;
    });
    await _saveChatUsers();
  }

  // Helper to check if a chat is a group chat
  bool _isGroupChat(String chatId) {
    // Group chat IDs have more than 2 emails joined by _
    return chatId.split('_').length > 2;
  }

  // Helper to get group name from group chatId
  Future<String> _getGroupName(String groupId) async {
    final users = groupId.split('_');
    // Try to get names from Firestore
    final snapshot = await ChatService.getAllUsers();
    final nameList = users.map((emailOrName) {
      final user = snapshot.firstWhere(
        (u) => u['name'] == emailOrName || u['email'] == emailOrName,
        orElse: () => {'name': emailOrName},
      );
      return user['name'] ?? emailOrName;
    }).toList();
    return nameList.join(', ');
  }

  // Helper to get group name and image from Firestore for group chats
  Future<Map<String, dynamic>> _getGroupInfo(String groupId) async {
    final doc = await FirebaseFirestore.instance.collection('group_chats').doc(groupId).get();
    if (doc.exists) {
      final data = doc.data() ?? {};
      return {
        'name': data['name'] ?? await _getGroupName(groupId),
        'image': data['image'],
      };
    }
    return {'name': await _getGroupName(groupId), 'image': null};
  }

  void _openChat(String chatId) async {
    if (_currentUserEmail == null) return;
    setState(() {
      _unreadChats.remove(chatId);
    });
    if (_isGroupChat(chatId)) {
      // Fetch group info (name, image) from Firestore
      final groupInfo = await _getGroupInfo(chatId);
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserChatPage(
            userName: groupInfo['name'] ?? chatId,
            userEmail: chatId, // Pass groupId as email
            currentUserEmail: _currentUserEmail!,
            isGroup: true,
          ),
        ),
      );
      // If group info was updated, refresh home page
      if (result != null && mounted) {
        await _loadAllChatsForCurrentUser();
        setState(() {});
      } else {
        setState(() {
          _unreadChats.remove(chatId);
        });
      }
    } else {
      final user = _firestoreUsers.firstWhere(
        (u) => u['email'] == chatId,
        orElse: () => {},
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserChatPage(
            userName: user['name'] ?? chatId,
            userEmail: chatId,
            currentUserEmail: _currentUserEmail!,
          ),
        ),
      );
      // When returning from chat, re-check unread status
      setState(() {
        _unreadChats.remove(chatId);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchFirestoreUsers();
    _loadAllChatsForCurrentUser();
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
        // Filter out users already in chat and current user
        final availableUsers = _firestoreUsers.where((user) {
          final email = user['email'];
          return !_users.contains(email) && email != _currentUserEmail;
        }).toList();
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
                    items: availableUsers.map((user) {
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
                        // Prevent duplicate user chat
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
                          if (!_users.contains(selectedUserEmail!)) {
                            _users.add(selectedUserEmail!);
                          }
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
    // Animation state for FAB

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
                      // Add User Icon
                      IconButton(
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Colors.blueAccent,
                          size: 28,
                        ),
                        onPressed: _showAddUserSheet,
                        tooltip: 'Add user to chat',
                      ),
                      // Create Group Icon (added next to Add User)
                      IconButton(
                        icon: const Icon(
                          Icons.group_add_rounded,
                          color: Colors.purpleAccent,
                          size: 28,
                        ),
                        onPressed: () => _showCreateGroupDialog(context),
                        tooltip: 'Create Group',
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
                                    final chatId = _sortedUsers[index];
                                    final isGroup = _isGroupChat(chatId);
                                    final isHighlighted = _unreadChats.contains(chatId);
                                    if (isGroup) {
                                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                        stream: FirebaseFirestore.instance
                                            .collection('group_chats')
                                            .doc(chatId)
                                            .snapshots(),
                                        builder: (context, snapshot) {
                                          final data = snapshot.data?.data() ?? {};
                                          final groupName = data['name'] ?? chatId;
                                          final groupImage = data['image'];
                                          return AnimatedContainer(
                                            duration: const Duration(milliseconds: 500),
                                            curve: Curves.easeInOut,
                                            decoration: BoxDecoration(
                                              color: isHighlighted
                                                  ? Colors.blueAccent.withOpacity(0.18)
                                                  : Colors.grey[850],
                                              borderRadius: BorderRadius.circular(16),
                                              boxShadow: isHighlighted
                                                  ? [
                                                      BoxShadow(
                                                        color: Colors.blueAccent.withOpacity(0.18),
                                                        blurRadius: 12,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ]
                                                  : [],
                                            ),
                                            child: ListTile(
                                              leading: groupImage != null
                                                  ? CircleAvatar(backgroundImage: NetworkImage(groupImage), radius: 24)
                                                  : CircleAvatar(backgroundColor: Colors.blueAccent, radius: 24, child: Text(groupName.isNotEmpty ? groupName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
                                              title: Text(groupName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                              subtitle: Text(chatId, style: const TextStyle(color: Colors.white54)),
                                              onTap: () => _openChat(chatId),
                                            ),
                                          );
                                        },
                                      );
                                    } else {
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
                                          onLongPress: () {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                backgroundColor: Colors.grey[900],
                                                title: const Text(
                                                  'Delete Chat',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                content: const Text(
                                                  'Are you sure you want to delete this chat?',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    child: const Text(
                                                      'Cancel',
                                                      style: TextStyle(
                                                        color: Colors.blueAccent,
                                                      ),
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.of(ctx).pop(),
                                                  ),
                                                  ElevatedButton(
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.redAccent,
                                                        ),
                                                    child: const Text(
                                                      'Delete',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    onPressed: () async {
                                                      Navigator.of(ctx).pop();
                                                      setState(() {
                                                        _users.remove(
                                                          chatUserEmail,
                                                        );
                                                      });
                                                      await _saveChatUsers();
                                                      if (_isGroupChat(
                                                        chatUserEmail,
                                                      )) {
                                                        // Delete group chat document from Firestore
                                                        await FirebaseFirestore.instance
                                                            .collection('group_chats')
                                                            .doc(chatUserEmail)
                                                            .delete();
                                                        // Optionally: delete all group messages subcollection
                                                        final messages = await FirebaseFirestore.instance
                                                            .collection('group_chats')
                                                            .doc(chatUserEmail)
                                                            .collection('messages')
                                                            .get();
                                                        for (final doc in messages.docs) {
                                                          await doc.reference.delete();
                                                        }
                                                      } else {
                                                        // Delete user-to-user chat document and all messages from Firestore
                                                        final chatId = await ChatService.getChatIdByUsernames(_currentUserEmail!, chatUserEmail);
                                                        // Delete all messages in the chat
                                                        final messages = await FirebaseFirestore.instance
                                                            .collection('chats')
                                                            .doc(chatId)
                                                            .collection('messages')
                                                            .get();
                                                        for (final doc in messages.docs) {
                                                          await doc.reference.delete();
                                                        }
                                                        // Delete the chat document itself
                                                        await FirebaseFirestore.instance
                                                            .collection('chats')
                                                            .doc(chatId)
                                                            .delete();
                                                      }
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Chat deleted!',
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    }
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
          // Floating Action Button for Add User / Create Group
        ],
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context) {
    List<String> selectedEmails = [];
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Create Group',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select users to add to group:',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 200,
                  child: ListView(
                    shrinkWrap: true,
                    children: _firestoreUsers.map((user) {
                      return CheckboxListTile(
                        value: selectedEmails.contains(user['email']),
                        title: Text(
                          user['name'],
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          user['email'],
                          style: const TextStyle(color: Colors.white54),
                        ),
                        onChanged: (checked) {
                          if (checked == true) {
                            selectedEmails.add(user['email']);
                          } else {
                            selectedEmails.remove(user['email']);
                          }
                          (context as Element).markNeedsBuild();
                        },
                        checkColor: Colors.white,
                        activeColor: Colors.purpleAccent,
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.blueAccent),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
              ),
              onPressed: () async {
                if (selectedEmails.isEmpty || _currentUserEmail == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Select at least one user.')),
                  );
                  return;
                }
                final groupUsers = [_currentUserEmail!, ...selectedEmails];
                groupUsers.sort();
                // Save group in Firestore
                await GroupChatService.createGroupChat(groupUsers);
                // Save group locally for all members
                final groupId = await GroupChatService.getGroupChatId(
                  groupUsers,
                );
                for (final email in groupUsers) {
                  final prefs = await SharedPreferences.getInstance();
                  final userChats =
                      prefs.getStringList('chat_users_$email') ?? [];
                  if (!userChats.contains(groupId)) {
                    userChats.add(groupId);
                    await prefs.setStringList('chat_users_$email', userChats);
                  }
                }
                setState(() {
                  _users.add(groupId);
                });
                await _saveChatUsers();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Group created!')));
              },
              child: const Text(
                'Create',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}

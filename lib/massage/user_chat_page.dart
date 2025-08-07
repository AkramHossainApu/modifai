import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/chat_service.dart';
import '../services/group_chat_service.dart';
import '../services/api_service.dart';
import 'chat_profile_page.dart';
import 'animated_circle.dart';
import 'camera_screen.dart';
import 'image_with_aspect.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserChatPage extends StatefulWidget {
  final String userName;
  final String userEmail;
  final String currentUserEmail;
  final bool isGroup;
  const UserChatPage({
    super.key,
    required this.userName,
    required this.userEmail,
    required this.currentUserEmail,
    this.isGroup = false,
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
  String? _pickedImagePath;
  List<Map<String, dynamic>> _lastChatMessages = [];
  String? _groupImageUrl;
  String? _groupName;
  bool _showingAtSuggestion = false;

  @override
  void initState() {
    super.initState();
    _loadNames();
    if (widget.isGroup) {
      _fetchGroupInfo();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.isGroup) {
      _fetchGroupInfo();
    }
  }

  @override
  void didUpdateWidget(covariant UserChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isGroup && oldWidget.userEmail != widget.userEmail) {
      _fetchGroupInfo();
    }
  }

  Future<void> _loadNames() async {
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

  Future<void> _fetchGroupInfo() async {
    final doc = await FirebaseFirestore.instance.collection('group_chats').doc(widget.userEmail).get();
    if (doc.exists) {
      final data = doc.data() ?? {};
      setState(() {
        _groupName = data['name'] ?? widget.userName;
        _groupImageUrl = data['image'];
      });
    }
  }

  String _displayName(String? nameOrEmail) {
    if (nameOrEmail == null) return '?';
    if (nameOrEmail.contains('@')) {
      final user = nameOrEmail.split('@')[0].replaceAll('.', '_');
      return user
          .split('_')
          .map((s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '')
          .join('_');
    }
    return nameOrEmail
        .split(' ')
        .map((s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '')
        .join(' ');
  }

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty && _pickedImagePath == null) return;
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    String senderUsername = _displayName(_senderName);
    String receiverUsername = _displayName(_receiverName);
    String? imageUrl;
    try {
      // Handle image upload if needed (unchanged)
      if (_pickedImagePath != null) {
        final file = File(_pickedImagePath!);
        final exists = await file.exists();
        if (!exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image file does not exist or cannot be accessed.'),
            ),
          );
          return;
        }
        imageUrl = await ChatService.uploadImageAndGetUrl(_pickedImagePath!);
        if (imageUrl == null || !imageUrl.startsWith('http')) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image upload failed.')),
          );
          return;
        }
      }
      // --- AI @askmodifai logic ---
      if (text.trim().toLowerCase().startsWith('@askmodifai')) {
        final aiPrompt = text.replaceFirst(RegExp(r'^@askmodifai', caseSensitive: false), '').trim();
        // Save the user's @askmodifai message as normal
        await ChatService.sendMessage(
          sender: senderUsername,
          receiver: receiverUsername,
          text: text,
          timestamp: now,
          imagePath: imageUrl,
        );
        _msgController.clear();
        setState(() {
          _pickedImagePath = null;
          // Show ModifAI typing indicator in chat
          _lastChatMessages.add({
            'sender': 'ModifAI',
            'receiver': senderUsername,
            'text': '[typing]',
            'timestamp': now + 0.0001,
          });
        });
        if (aiPrompt.isNotEmpty) {
          try {
            String aiReply;
            // --- AI can read user-to-user messages and respond to commands ---
            if (aiPrompt.toLowerCase().contains('summarize')) {
              // Get last 5 user-to-user messages (excluding AI messages)
              final userMessages = _lastChatMessages
                .where((msg) => (msg['sender'] as String?)?.toLowerCase() != 'modifai')
                .toList();
              final last5 = userMessages.length >= 5
                ? userMessages.sublist(userMessages.length - 5)
                : userMessages;
              final chatText = last5.map((m) =>
                '${m['sender']}: ${m['text'] ?? ''}').join('\n');
              aiReply = await ApiService.getChatbotReply(
                'Summarize the following chat between users:\n$chatText'
              );
            } else {
              aiReply = await ApiService.getChatbotReply(aiPrompt);
            }
            // Remove the typing indicator
            setState(() {
              final idx = _lastChatMessages.lastIndexWhere(
                (msg) => msg['sender'] == 'ModifAI' && msg['text'] == '[typing]'
              );
              if (idx != -1) _lastChatMessages.removeAt(idx);
            });
            // Save the AI response to Firestore in the same chat document
            final chatId = await ChatService.getUserToUserChatId(senderUsername, receiverUsername);
            await ChatService.sendMessage(
              sender: 'ModifAI',
              receiver: chatId,
              text: aiReply,
              timestamp: now + 0.001,
              imagePath: null,
              chatIdOverride: chatId,
            );
            // Immediately show the AI message in the chat UI
            setState(() {
              _lastChatMessages.add({
                'sender': 'ModifAI',
                'receiver': chatId,
                'text': aiReply,
                'timestamp': now + 0.001,
              });
            });
          } catch (e) {
            setState(() {
              final idx = _lastChatMessages.lastIndexWhere(
                (msg) => msg['sender'] == 'ModifAI' && msg['text'] == '[typing]'
              );
              if (idx != -1) _lastChatMessages.removeAt(idx);
              _lastChatMessages.add({
                'sender': 'ModifAI',
                'receiver': senderUsername,
                'text': 'AI error: $e',
                'timestamp': now + 0.001,
              });
            });
            final chatId = await ChatService.getUserToUserChatId(senderUsername, receiverUsername);
            await ChatService.sendMessage(
              sender: 'ModifAI',
              receiver: chatId,
              text: 'AI error: $e',
              timestamp: now + 0.001,
              imagePath: null,
              chatIdOverride: chatId,
            );
          }
        }
        return;
      }
      // --- Normal message logic ---
      await ChatService.sendMessage(
        sender: senderUsername,
        receiver: receiverUsername,
        text: text,
        timestamp: now,
        imagePath: imageUrl,
      );
      _msgController.clear();
      setState(() {
        _pickedImagePath = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
    }
  }

  void _pickImage() async {
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

  void _openProfile() async {
    // If group, pass group name/image
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatProfilePage(
          userName: widget.isGroup ? (_groupName ?? widget.userName) : widget.userName,
          userEmail: widget.userEmail,
          chatMessages: _lastChatMessages,
        ),
      ),
    );
    // If group info was updated, refresh and propagate up
    if (result != null && widget.isGroup && mounted) {
      await _fetchGroupInfo();
      setState(() {});
      // Pop with result so home page can refresh too
      Navigator.of(context).pop(result);
    }
  }

  Widget _buildColoredText(String text) {
    final modifaiPattern = RegExp(r'(@askmodifai)', caseSensitive: false);
    final spans = <TextSpan>[];
    int start = 0;
    final matches = modifaiPattern.allMatches(text);
    for (final match in matches) {
      if (match.start > start) {
        spans.add(TextSpan(
          text: text.substring(start, match.start),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 16),
      ));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ));
    }
    return RichText(text: TextSpan(children: spans));
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
                  child: widget.isGroup
                      ? StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('group_chats')
                              .doc(widget.userEmail)
                              .snapshots(),
                          builder: (context, snapshot) {
                            final data = snapshot.data?.data() ?? {};
                            final groupName = data['name'] ?? widget.userName;
                            final groupImageUrl = data['image'];
                            return Row(
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
                                GestureDetector(
                                  onTap: _openProfile,
                                  child: groupImageUrl != null
                                      ? CircleAvatar(
                                          backgroundImage: NetworkImage(groupImageUrl),
                                          radius: 22,
                                        )
                                      : CircleAvatar(
                                          backgroundColor: Colors.blueAccent,
                                          radius: 22,
                                          child: Text(
                                            groupName.isNotEmpty ? groupName[0].toUpperCase() : '?',
                                            style: const TextStyle(color: Colors.white),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _openProfile,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          groupName,
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
                                ),
                                IconButton(
                                  icon: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(10),
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
                                  onPressed: () {},
                                  tooltip: 'Call',
                                ),
                                IconButton(
                                  icon: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.purpleAccent.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(10),
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
                                  onPressed: () {},
                                  tooltip: 'Video Call',
                                ),
                              ],
                            );
                          },
                        )
                      : Row(
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
                            GestureDetector(
                              onTap: _openProfile,
                              child: CircleAvatar(
                                backgroundColor: Colors.blueAccent,
                                radius: 22,
                                child: Text(
                                  widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: _openProfile,
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
                            ),
                            IconButton(
                              icon: Container(
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(10),
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
                              onPressed: () {},
                              tooltip: 'Call',
                            ),
                            IconButton(
                              icon: Container(
                                decoration: BoxDecoration(
                                  color: Colors.purpleAccent.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(10),
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
                              onPressed: () {},
                              tooltip: 'Video Call',
                            ),
                          ],
                        ),
                ),
                Expanded(
                  child: widget.isGroup
                      ? StreamBuilder<List<Map<String, dynamic>>>(
                          stream: GroupChatService.groupChatStream(
                            widget.userEmail,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              _lastChatMessages = snapshot.data!;
                            }
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
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
                                final senderStr = (msg['sender'] as String?)?.trim() ?? '';
                                final isAI = senderStr.toLowerCase() == 'modifai';
                                final isMe = !isAI && senderStr == senderDisplay;
                                final senderName = isAI ? 'ModifAI' : _displayName(msg['sender']);
                                if (isAI) {
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Column(
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: Colors.blueGrey[700],
                                            backgroundImage: const AssetImage('assets/modifai_logo.png'),
                                          ),
                                          const SizedBox(height: 2),
                                          const Text(
                                            'ModifAI',
                                            style: TextStyle(
                                              color: Colors.purpleAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 6),
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final maxBubbleWidth = MediaQuery.of(context).size.width * 0.7;
                                          return Container(
                                            margin: const EdgeInsets.symmetric(vertical: 1),
                                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[800],
                                              borderRadius: const BorderRadius.only(
                                                topLeft: Radius.circular(16),
                                                topRight: Radius.circular(16),
                                                bottomLeft: Radius.circular(16),
                                                bottomRight: Radius.circular(4),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.10),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                                            child: Builder(
                                              builder: (context) {
                                                final hasImage = msg['image'] != null && (msg['image'] as String).isNotEmpty;
                                                final hasText = (msg['text'] ?? '').toString().isNotEmpty;
                                                if (hasImage) {
                                                  return ImageWithAspect(
                                                    imagePath: msg['image'],
                                                    textWidget: hasText
                                                        ? Padding(
                                                            padding: const EdgeInsets.only(top: 6.0),
                                                            child: _buildColoredText(msg['text'] ?? ''),
                                                          )
                                                        : null,
                                                  );
                                                } else if (hasText) {
                                                  return _buildColoredText(msg['text'] ?? '');
                                                } else {
                                                  return const SizedBox.shrink();
                                                }
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  );
                                }
                                // User/group message (original UI)
                                return Row(
                                  mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (!isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8.0),
                                        child: Column(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: Colors.blueAccent,
                                              child: Text(
                                                senderName.isNotEmpty ? senderName[0] : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              senderName,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final maxBubbleWidth = MediaQuery.of(context).size.width * 0.7;
                                        return Container(
                                          margin: const EdgeInsets.symmetric(vertical: 2),
                                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                                          decoration: BoxDecoration(
                                            color: isMe
                                                ? Colors.blueAccent.withOpacity(0.22)
                                                : Colors.grey[800],
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(16),
                                              topRight: const Radius.circular(16),
                                              bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                                              bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.10),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                                          child: Builder(
                                            builder: (context) {
                                              final hasImage = msg['image'] != null && (msg['image'] as String).isNotEmpty;
                                              final hasText = (msg['text'] ?? '').toString().isNotEmpty;
                                              if (hasImage) {
                                                return ImageWithAspect(
                                                  imagePath: msg['image'],
                                                  textWidget: hasText
                                                      ? _buildColoredText(msg['text'] ?? '')
                                                      : null,
                                                );
                                              } else if (hasText) {
                                                return _buildColoredText(msg['text'] ?? '');
                                              } else {
                                                return const SizedBox.shrink();
                                              }
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                    if (isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8.0),
                                        child: Column(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: Colors.blueAccent,
                                              child: Text(
                                                senderName.isNotEmpty ? senderName[0] : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              senderName,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        )
                      : StreamBuilder<List<Map<String, dynamic>>>(
                          stream: ChatService.chatStream(
                            user1: sender,
                            user2: receiver,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              _lastChatMessages = snapshot.data!;
                            }
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
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
                                final senderStr = (msg['sender'] as String?)?.trim() ?? '';
                                final isAI = senderStr.toLowerCase() == 'modifai';
                                final isMe = !isAI && senderStr == senderDisplay;
                                return Row(
                                  mainAxisAlignment: isMe
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (!isMe && !isAI)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        child: Column(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: Colors.blueAccent,
                                              child: Text(
                                                receiverDisplay.isNotEmpty
                                                    ? receiverDisplay[0]
                                                    : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              receiverDisplay,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (isAI)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        child: Column(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: Colors.blueGrey[700],
                                              backgroundImage: const AssetImage('assets/modifai_logo.png'),
                                            ),
                                            const SizedBox(height: 2),
                                            const Text(
                                              'ModifAI',
                                              style: TextStyle(
                                                color: Colors.purpleAccent,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final maxBubbleWidth = MediaQuery.of(context).size.width * 0.7;
                                        return Container(
                                          margin: const EdgeInsets.symmetric(vertical: 1),
                                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                                          decoration: BoxDecoration(
                                            color: isAI
                                                ? Colors.purpleAccent.withOpacity(0.18)
                                                : isMe
                                                    ? Colors.blueAccent.withOpacity(0.22)
                                                    : Colors.grey[800],
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(18),
                                              topRight: const Radius.circular(18),
                                              bottomLeft: isMe || isAI ? const Radius.circular(18) : const Radius.circular(4),
                                              bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.10,
                                                ),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                                          child: Builder(
                                            builder: (context) {
                                              final hasImage =
                                                  msg['image'] != null &&
                                                  (msg['image'] as String)
                                                      .isNotEmpty;
                                              final hasText = (msg['text'] ?? '')
                                                  .toString()
                                                  .isNotEmpty;
                                              if (hasImage) {
                                                return ImageWithAspect(
                                                  imagePath: msg['image'],
                                                  textWidget: hasText
                                                      ? Text(
                                                          msg['text'] ?? '',
                                                          style: const TextStyle(
                                                            fontSize: 16,
                                                          ),
                                                        )
                                                      : null,
                                                );
                                              } else if (hasText) {
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 8,
                                                        horizontal: 12,
                                                      ),
                                                  child: Text(
                                                    msg['text'] ?? '',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                );
                                              } else {
                                                return const SizedBox.shrink();
                                              }
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                    if (isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 8.0,
                                        ),
                                        child: Column(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: Colors.blueAccent,
                                              child: Text(
                                                senderDisplay.isNotEmpty ? senderDisplay[0] : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              senderDisplay,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 10,
                                              ),
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
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
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
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.pinkAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
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
                      Container(
                        decoration: BoxDecoration(
                          color:
                              (_isRecording
                                      ? Colors.greenAccent
                                      : Colors.blueAccent)
                                  .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
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
                      Flexible(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 0,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_pickedImagePath != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 4.0,
                                      top: 4.0,
                                    ),
                                    child: Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.file(
                                            File(_pickedImagePath!),
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: GestureDetector(
                                            onTap: _removePickedImage,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                SizedBox(
                                  height: 48,
                                  child: Stack(
                                    children: [
                                      TextField(
                                        controller: _msgController,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                        decoration: const InputDecoration(
                                          hintText: 'Type a message...',
                                          hintStyle: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 15,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                        ),
                                        minLines: 1,
                                        maxLines: 1,
                                        onChanged: (val) {
                                          final wasShowing = _showingAtSuggestion;
                                          _showingAtSuggestion = val.endsWith('@');
                                          if (wasShowing != _showingAtSuggestion) setState(() {});
                                        },
                                        onTap: () {
                                          // Show suggestion if cursor is after @
                                          final text = _msgController.text;
                                          _showingAtSuggestion = text.endsWith('@');
                                          setState(() {});
                                        },
                                      ),
                                      if (_showingAtSuggestion)
                                        Positioned(
                                          left: 0,
                                          bottom: 48,
                                          child: Material(
                                            color: Colors.grey[900],
                                            elevation: 4,
                                            borderRadius: BorderRadius.circular(8),
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(8),
                                              onTap: () {
                                                _msgController.text = '@askmodifai ';
                                                _msgController.selection = TextSelection.fromPosition(
                                                  TextPosition(offset: _msgController.text.length),
                                                );
                                                _showingAtSuggestion = false;
                                                setState(() {});
                                              },
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                child: Text(
                                                  '@askmodifai',
                                                  style: TextStyle(
                                                    color: Colors.blueAccent,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          color: Colors.lightBlueAccent,
                          size: 28,
                        ),
                        onPressed: _sendMessage,
                        tooltip: 'Send',
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

// AI Chat Dialog Widget
class _AIChatDialog extends StatefulWidget {
  final String initialPrompt;
  final List<Map<String, dynamic>> chatHistory;
  const _AIChatDialog({required this.initialPrompt, required this.chatHistory});
  @override
  State<_AIChatDialog> createState() => _AIChatDialogState();
}

class _AIChatDialogState extends State<_AIChatDialog> {
  final TextEditingController _aiController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _aiMessages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _aiMessages = [
      {'sender': 'ai', 'text': 'How can I help you?'},
    ];
    if (widget.initialPrompt.trim().length > 12) {
      // If user typed a prompt after @askmodifai, send it immediately
      Future.delayed(Duration(milliseconds: 300), () => _sendAI(widget.initialPrompt.replaceFirst(RegExp(r'^@askmodifai', caseSensitive: false), '').trim()));
    }
  }

  void _sendAI(String prompt) async {
    if (prompt.isEmpty) return;
    setState(() {
      _aiMessages.add({'sender': 'user', 'text': prompt});
      _loading = true;
    });
    try {
      final reply = await ApiService.getChatbotReply(prompt);
      setState(() {
        _aiMessages.add({'sender': 'ai', 'text': reply});
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _aiMessages.add({'sender': 'ai', 'text': 'AI error: $e'});
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF23242B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        height: 520,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.smart_toy, color: Colors.purpleAccent, size: 28),
                  const SizedBox(width: 10),
                  const Text('ModifAI Assistant', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _aiMessages.length,
                itemBuilder: (context, idx) {
                  final msg = _aiMessages[idx];
                  final isUser = msg['sender'] == 'user';
                  return Container(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.blueAccent.withOpacity(0.22) : Colors.purpleAccent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        msg['text'] ?? '',
                        style: TextStyle(
                          color: isUser ? Colors.white : Colors.purpleAccent.shade100,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _aiController,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Ask something, or type /summarize',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      minLines: 1,
                      maxLines: 2,
                      onSubmitted: (val) {
                        if (!_loading) _sendAI(val.trim());
                        _aiController.clear();
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.lightBlueAccent),
                    onPressed: _loading
                        ? null
                        : () {
                            final val = _aiController.text.trim();
                            if (val.isNotEmpty) _sendAI(val);
                            _aiController.clear();
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.summarize, color: Colors.orangeAccent),
                    tooltip: 'Summarize this chat',
                    onPressed: _loading
                        ? null
                        : () async {
                            // Summarize the chat history
                            final chatText = widget.chatHistory.map((m) => m['text']).whereType<String>().join('\n');
                            if (chatText.isEmpty) return;
                            setState(() {
                              _aiMessages.add({'sender': 'user', 'text': '[Summarize the chat]'});
                              _loading = true;
                            });
                            try {
                              final reply = await ApiService.getChatbotReply('Summarize this chat: $chatText');
                              setState(() {
                                _aiMessages.add({'sender': 'ai', 'text': reply});
                                _loading = false;
                              });
                            } catch (e) {
                              setState(() {
                                _aiMessages.add({'sender': 'ai', 'text': 'AI error: $e'});
                                _loading = false;
                              });
                            }
                            _scrollToBottom();
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

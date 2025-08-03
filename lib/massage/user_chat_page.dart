import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/chat_service.dart';
import '../services/group_chat_service.dart';
import 'chat_profile_page.dart';
import 'animated_circle.dart';
import 'camera_screen.dart';
import 'image_with_aspect.dart';

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

  @override
  void initState() {
    super.initState();
    _loadNames();
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Image upload failed.')));
          return;
        }
      }
      if (widget.isGroup) {
        await GroupChatService.sendGroupMessage(
          groupId: widget.userEmail,
          sender: senderUsername,
          text: text,
          timestamp: now,
          imagePath: imageUrl,
        );
      } else {
        await ChatService.sendMessage(
          sender: senderUsername,
          receiver: receiverUsername,
          text: text,
          timestamp: now,
          imagePath: imageUrl,
        );
      }
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

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatProfilePage(
          userName: widget.userName,
          userEmail: widget.userEmail,
          chatMessages: _lastChatMessages,
        ),
      ),
    );
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
                      GestureDetector(
                        onTap: _openProfile,
                        child: CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Text(
                            widget.userName.isNotEmpty
                                ? widget.userName[0].toUpperCase()
                                : '?',
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
                                final isMe =
                                    (msg['sender'] as String).trim() ==
                                    senderDisplay;
                                final senderName = _displayName(msg['sender']);
                                return Row(
                                  mainAxisAlignment: isMe
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (!isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        child: Column(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor:
                                                  Colors.blueAccent,
                                              child: Text(
                                                senderName.isNotEmpty
                                                    ? senderName[0]
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
                                              senderName,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Flexible(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        padding: EdgeInsets.zero,
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? Colors.blueAccent.withOpacity(
                                                  0.22,
                                                )
                                              : Colors.grey[800],
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
                                              color: Colors.black.withOpacity(
                                                0.10,
                                              ),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
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
                                      ),
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
                                              backgroundColor:
                                                  Colors.blueAccent,
                                              child: Text(
                                                senderName.isNotEmpty
                                                    ? senderName[0]
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
                                final isMe =
                                    (msg['sender'] as String).trim() ==
                                    senderDisplay;
                                return Row(
                                  mainAxisAlignment: isMe
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (!isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        child: Column(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor:
                                                  Colors.blueAccent,
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
                                    Flexible(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        padding: EdgeInsets.zero,
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? Colors.blueAccent.withOpacity(
                                                  0.22,
                                                )
                                              : Colors.grey[800],
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
                                              color: Colors.black.withOpacity(
                                                0.10,
                                              ),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
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
                                      ),
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
                                              backgroundColor:
                                                  Colors.blueAccent,
                                              child: Text(
                                                senderDisplay.isNotEmpty
                                                    ? senderDisplay[0]
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
                                  child: TextField(
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

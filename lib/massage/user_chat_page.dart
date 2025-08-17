import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/chat_service.dart';
import '../services/group_chat_service.dart';
import '../services/api_service.dart';
import '../services/call_service.dart';
import 'chat_profile_page.dart';
import 'animated_circle.dart';
import 'camera_screen.dart';
import 'image_with_aspect.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import 'call_screen.dart';

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
  String? _pickedAudioPath;
  final AudioRecorder _audioRecorder = AudioRecorder();
  List<Map<String, dynamic>> _lastChatMessages = [];
  String? _groupName;
  bool _showingAtSuggestion = false;
  bool _showRecordingDialog = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _callStream;
  bool _isCalling = false;
  bool _isRinging = false;
  bool _isInCall = false;
  bool _isVideoCall = false;
  String? _callPeerName;
  String? _callPeerEmail;

  @override
  void initState() {
    super.initState();
    _loadNames();
    if (widget.isGroup) {
      _fetchGroupInfo();
    }
    _listenForIncomingCalls();
  }

  void _listenForIncomingCalls() {
    final myEmail = widget.currentUserEmail.trim().toLowerCase();
    final peerEmail = widget.userEmail.trim().toLowerCase();
    _callStream = CallService.callStream(myEmail, peerEmail);
    _callStream!.listen((doc) async {
      final data = doc.data();
      if (data == null) return;
      debugPrint('Call doc: ' + data.toString());
      final status = data['status'] as String?;
      final isVideo = data['isVideo'] as bool? ?? false;
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final created = (data['created'] ?? data['timestamp'] ?? 0).toDouble();
      // Only show dialog if call is recent and status is 'ringing'
      if (status == 'ringing' &&
          data['receiverId'] == myEmail &&
          (now - created).abs() <= 30) {
        setState(() {
          _isRinging = true;
          _isVideoCall = isVideo;
          _callPeerName = data['callerName'];
          _callPeerEmail = data['callerId'];
        });
        _showIncomingCallDialog();
      } else if (status == 'accepted') {
        // Only show in-call if we are already ringing or calling
        if (_isRinging || _isCalling) {
          setState(() {
            _isInCall = true;
            _isCalling = false;
            _isRinging = false;
          });
          Navigator.of(
            context,
            rootNavigator: true,
          ).pop(); // Close ringing dialog
          _showInCallDialog();
        }
      } else if (status == 'ended') {
        setState(() {
          _isCalling = false;
          _isRinging = false;
          _isInCall = false;
        });
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop(); // Close any call dialog
        // Clean up call doc if not already deleted
        try {
          await CallService.deleteCallDoc(myEmail, peerEmail);
        } catch (_) {}
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Call ended.')));
      }
    });
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
    final doc = await FirebaseFirestore.instance
        .collection('group_chats')
        .doc(widget.userEmail)
        .get();
    if (doc.exists) {
      final data = doc.data() ?? {};
      setState(() {
        _groupName = data['name'] ?? widget.userName;
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

  String _formatTimestamp(double timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());
    return DateFormat('hh:mm a').format(dt); // e.g., 02:15 PM
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      _recordingTimer?.cancel();
      setState(() {
        _isRecording = false;
        _pickedAudioPath = path;
        _showRecordingDialog = false;
      });
    } else {
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );
      setState(() {
        _isRecording = true;
        _pickedAudioPath = null;
        _showRecordingDialog = true;
        _recordingDuration = Duration.zero;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_isRecording) {
          setState(() {
            _recordingDuration = Duration(seconds: timer.tick);
          });
        }
      });
    }
  }

  Widget _buildRecordingDialog() {
    return Center(
      child: Material(
        color: Colors.black54,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                _formatDuration(_recordingDuration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Recording...',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: _toggleRecording,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildAudioPreview() {
    if (_pickedAudioPath == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey[900],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.audiotrack, color: Colors.orangeAccent),
          const SizedBox(width: 10),
          const Text(
            'Audio ready to send',
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.redAccent),
            onPressed: () {
              setState(() {
                _pickedAudioPath = null;
              });
            },
          ),
        ],
      ),
    );
  }

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty && _pickedImagePath == null && _pickedAudioPath == null)
      return;
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    String senderUsername = _displayName(_senderName);
    String receiverUsername = _displayName(_receiverName);
    String? imageUrl;
    String? audioUrl;
    try {
      // Handle image upload if needed
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
      // Handle audio upload if needed
      if (_pickedAudioPath != null) {
        final file = File(_pickedAudioPath!);
        final exists = await file.exists();
        if (!exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audio file does not exist or cannot be accessed.'),
            ),
          );
          return;
        }
        audioUrl = await ChatService.uploadImageAndGetUrl(_pickedAudioPath!);
        if (audioUrl == null || !audioUrl.startsWith('http')) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Audio upload failed.')));
          return;
        }
      }
      // --- GROUP CHAT LOGIC ---
      if (widget.isGroup) {
        await GroupChatService.sendGroupMessage(
          groupId: widget.userEmail,
          sender: senderUsername,
          text: text,
          timestamp: now,
          imagePath: imageUrl,
          audioPath: audioUrl,
        );
        _msgController.clear();
        setState(() {
          _pickedImagePath = null;
          _pickedAudioPath = null;
        });
        return;
      }
      // --- AI @askmodifai logic ---
      if (text.trim().toLowerCase().startsWith('@askmodifai')) {
        final aiPrompt = text
            .replaceFirst(RegExp(r'^@askmodifai', caseSensitive: false), '')
            .trim();
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
          _pickedAudioPath = null;
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
                  .where(
                    (msg) =>
                        (msg['sender'] as String?)?.toLowerCase() != 'modifai',
                  )
                  .toList();
              final last5 = userMessages.length >= 5
                  ? userMessages.sublist(userMessages.length - 5)
                  : userMessages;
              final chatText = last5
                  .map((m) => '${m['sender']}: ${m['text'] ?? ''}')
                  .join('\n');
              aiReply = await ApiService.getChatbotReply(
                'Summarize the following chat between users:\n$chatText',
              );
            } else {
              aiReply = await ApiService.getChatbotReply(aiPrompt);
            }
            // Remove the typing indicator
            setState(() {
              final idx = _lastChatMessages.lastIndexWhere(
                (msg) =>
                    msg['sender'] == 'ModifAI' && msg['text'] == '[typing]',
              );
              if (idx != -1) _lastChatMessages.removeAt(idx);
            });
            // Save the AI response to Firestore in the same chat document
            final chatId = await ChatService.getUserToUserChatId(
              senderUsername,
              receiverUsername,
            );
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
                (msg) =>
                    msg['sender'] == 'ModifAI' && msg['text'] == '[typing]',
              );
              if (idx != -1) _lastChatMessages.removeAt(idx);
              _lastChatMessages.add({
                'sender': 'ModifAI',
                'receiver': senderUsername,
                'text': 'AI error: $e',
                'timestamp': now + 0.001,
              });
            });
            final chatId = await ChatService.getUserToUserChatId(
              senderUsername,
              receiverUsername,
            );
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
        audioPath: audioUrl,
      );
      _msgController.clear();
      setState(() {
        _pickedImagePath = null;
        _pickedAudioPath = null;
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

  void _openProfile() async {
    // If group, pass group name/image
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatProfilePage(
          userName: widget.isGroup
              ? (_groupName ?? widget.userName)
              : widget.userName,
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
        spans.add(
          TextSpan(
            text: text.substring(start, match.start),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: const TextStyle(
            color: Colors.purpleAccent,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(start),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }
    return RichText(text: TextSpan(children: spans));
  }

  void _startCall({required bool isVideo}) async {
    setState(() {
      _isCalling = true;
      _isVideoCall = isVideo;
    });
    final callerId = widget.currentUserEmail.trim().toLowerCase();
    final receiverId = widget.userEmail.trim().toLowerCase();
    final callId = CallService.getCallDocId(callerId, receiverId);
    debugPrint('Starting call with callId: ' + callId);
    await CallService.startCall(
      callerId: callerId,
      callerName: _senderName ?? widget.currentUserEmail,
      receiverId: receiverId,
      receiverName: _receiverName ?? widget.userEmail,
      isVideo: isVideo,
    );
    _showCallingDialog(callId, callerId, receiverId);
  }

  void _showCallingDialog(String callId, String callerId, String receiverId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF23242B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              _isVideoCall ? Icons.videocam : Icons.call,
              color: Colors.blueAccent,
            ),
            const SizedBox(width: 10),
            Text('Calling...', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              widget.userName,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              widget.userEmail,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.call_end, color: Colors.white),
              label: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () async {
                await CallService.endCall(callerId, receiverId);
                setState(() {
                  _isCalling = false;
                });
                Navigator.of(context, rootNavigator: true).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showInCallDialog() {
    final callerId = widget.currentUserEmail.trim().toLowerCase();
    final receiverId = widget.userEmail.trim().toLowerCase();
    final callId = CallService.getCallDocId(callerId, receiverId);
    debugPrint('Opening CallScreen with callId: ' + callId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          isCaller: _isCalling,
          callId: callId,
          selfId: callerId,
          peerId: receiverId,
          isVideo: _isVideoCall,
          callerName: _senderName,
          callerEmail: callerId,
        ),
      ),
    );
  }

  void _showIncomingCallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF23242B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              _isVideoCall ? Icons.videocam : Icons.call,
              color: Colors.greenAccent,
            ),
            const SizedBox(width: 10),
            const Text('Incoming Call', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              _callPeerName ?? 'Unknown',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              _callPeerEmail ?? '',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.call_end, color: Colors.white),
                  label: const Text(
                    'Reject',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                  onPressed: () async {
                    await CallService.endCall(
                      _callPeerEmail!,
                      widget.currentUserEmail.trim().toLowerCase(),
                    );
                    setState(() {
                      _isRinging = false;
                    });
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.call, color: Colors.white),
                  label: const Text(
                    'Accept',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                  ),
                  onPressed: () async {
                    await CallService.acceptCall(
                      _callPeerEmail!,
                      widget.currentUserEmail.trim().toLowerCase(),
                    );
                    setState(() {
                      _isInCall = true;
                      _isRinging = false;
                    });
                    Navigator.of(context, rootNavigator: true).pop();
                    // Open the real call screen
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) {
                          final myEmail = widget.currentUserEmail
                              .trim()
                              .toLowerCase();
                          final peerEmail = _callPeerEmail!;
                          final callId = CallService.getCallDocId(
                            peerEmail,
                            myEmail,
                          );
                          debugPrint(
                            'Accepting call, opening CallScreen with callId: ' +
                                callId,
                          );
                          return CallScreen(
                            isCaller: false,
                            callId: callId,
                            selfId: myEmail,
                            peerId: peerEmail,
                            isVideo: _isVideoCall,
                            callerName: _callPeerName,
                            callerEmail: _callPeerEmail,
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sender = widget.currentUserEmail.trim().toLowerCase();
    final receiver = widget.userEmail.trim().toLowerCase();
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
                                  child: CircleAvatar(
                                    backgroundColor: Colors.blueAccent,
                                    radius: 22,
                                    child: Text(
                                      groupName.isNotEmpty
                                          ? groupName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _openProfile,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                      color: Colors.greenAccent.withOpacity(
                                        0.18,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.greenAccent.withOpacity(
                                            0.18,
                                          ),
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
                                  onPressed: () => _startCall(isVideo: false),
                                  tooltip: 'Call',
                                ),
                                IconButton(
                                  icon: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.purpleAccent.withOpacity(
                                        0.18,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.purpleAccent
                                              .withOpacity(0.18),
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
                                  onPressed: () => _startCall(isVideo: true),
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
                                      color: Colors.greenAccent.withOpacity(
                                        0.18,
                                      ),
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
                              onPressed: () => _startCall(isVideo: false),
                              tooltip: 'Call',
                            ),
                            IconButton(
                              icon: Container(
                                decoration: BoxDecoration(
                                  color: Colors.purpleAccent.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.purpleAccent.withOpacity(
                                        0.18,
                                      ),
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
                              onPressed: () => _startCall(isVideo: true),
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
                            // Sort messages by timestamp ascending
                            final messages = [...(snapshot.data ?? [])]
                              ..sort(
                                (a, b) => ((a['timestamp'] ?? 0).toDouble())
                                    .compareTo(
                                      (b['timestamp'] ?? 0).toDouble(),
                                    ),
                              );
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_scrollController.hasClients) {
                                _scrollController.jumpTo(
                                  _scrollController.position.maxScrollExtent,
                                );
                              }
                            });
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: ListView.builder(
                                key: ValueKey(messages.length),
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 12,
                                ),
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final msg = messages[index];
                                  final senderStr =
                                      (msg['sender'] as String?)?.trim() ?? '';
                                  final isAI =
                                      senderStr.toLowerCase() == 'modifai';
                                  final isMe =
                                      !isAI &&
                                      senderStr == _displayName(_senderName);
                                  final senderName = isAI
                                      ? 'ModifAI'
                                      : _displayName(msg['sender']);
                                  final timeStr = _formatTimestamp(
                                    (msg['timestamp'] ?? 0).toDouble(),
                                  );
                                  String? imageToShow;
                                  if (msg['image'] != null &&
                                      (msg['image'] as String).isNotEmpty) {
                                    imageToShow = msg['image'];
                                  }
                                  if (msg['audio'] != null &&
                                      (msg['audio'] as String).isNotEmpty) {
                                    // Audio message: time at the bottom, left for sent, right for received
                                    return Row(
                                      mainAxisAlignment: isMe
                                          ? MainAxisAlignment.end
                                          : MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (!isMe)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8.0,
                                            ),
                                            child: Column(
                                              children: [
                                                CircleAvatar(
                                                  backgroundColor:
                                                      Colors.blueAccent,
                                                  radius: 16,
                                                  child: Text(
                                                    senderName.isNotEmpty
                                                        ? senderName[0]
                                                              .toUpperCase()
                                                        : '?',
                                                    style: const TextStyle(
                                                      color: Colors.white,
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
                                        Column(
                                          crossAxisAlignment: isMe
                                              ? CrossAxisAlignment.start
                                              : CrossAxisAlignment.end,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                if (isMe)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          right: 6.0,
                                                          top: 2,
                                                        ),
                                                    child: Text(
                                                      timeStr,
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.white54,
                                                      ),
                                                    ),
                                                  ),
                                                Container(
                                                  margin:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 4,
                                                      ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isMe
                                                        ? Colors.blueAccent
                                                              .withOpacity(0.22)
                                                        : Colors.orangeAccent
                                                              .withOpacity(
                                                                0.18,
                                                              ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                  ),
                                                  child: _AudioPlayerWidget(
                                                    audioUrl: msg['audio'],
                                                  ),
                                                ),
                                                if (!isMe)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: 6.0,
                                                          top: 2,
                                                        ),
                                                    child: Text(
                                                      timeStr,
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.white54,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        if (isMe)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8.0,
                                            ),
                                            child: Column(
                                              children: [
                                                CircleAvatar(
                                                  backgroundColor:
                                                      Colors.blueAccent,
                                                  radius: 16,
                                                  child: Text(
                                                    senderName.isNotEmpty
                                                        ? senderName[0]
                                                              .toUpperCase()
                                                        : '?',
                                                    style: const TextStyle(
                                                      color: Colors.white,
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
                                  }
                                  if (isAI) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Column(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor:
                                                  Colors.blueGrey[700],
                                              backgroundImage: const AssetImage(
                                                'assets/modifai_logo.png',
                                              ),
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
                                            final maxBubbleWidth =
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.7;
                                            return Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 1,
                                                  ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 2,
                                                    horizontal: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[800],
                                                borderRadius:
                                                    const BorderRadius.only(
                                                      topLeft: Radius.circular(
                                                        16,
                                                      ),
                                                      topRight: Radius.circular(
                                                        16,
                                                      ),
                                                      bottomLeft:
                                                          Radius.circular(16),
                                                      bottomRight:
                                                          Radius.circular(4),
                                                    ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.10),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              constraints: BoxConstraints(
                                                maxWidth: maxBubbleWidth,
                                              ),
                                              child: Builder(
                                                builder: (context) {
                                                  final hasImage =
                                                      msg['image'] != null &&
                                                      (msg['image'] as String)
                                                          .isNotEmpty;
                                                  final hasText =
                                                      (msg['text'] ?? '')
                                                          .toString()
                                                          .isNotEmpty;
                                                  if (hasImage) {
                                                    return ImageWithAspect(
                                                      imagePath: msg['image'],
                                                      textWidget: hasText
                                                          ? Padding(
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                    top: 6.0,
                                                                  ),
                                                              child:
                                                                  _buildColoredText(
                                                                    msg['text'] ??
                                                                        '',
                                                                  ),
                                                            )
                                                          : null,
                                                    );
                                                  } else if (hasText) {
                                                    return _buildColoredText(
                                                      msg['text'] ?? '',
                                                    );
                                                  } else {
                                                    return const SizedBox.shrink();
                                                  }
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                        Column(
                                          children: [
                                            Text(
                                              timeStr,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  }
                                  // User/group message (original UI)
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
                                      Column(
                                        crossAxisAlignment: isMe
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: EdgeInsets.only(
                                              left: isMe ? 0 : 4,
                                              right: isMe ? 4 : 0,
                                              bottom: 2,
                                            ),
                                            child: Text(
                                              timeStr,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.white54,
                                              ),
                                            ),
                                          ),
                                          LayoutBuilder(
                                            builder: (context, constraints) {
                                              final maxBubbleWidth =
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.7;
                                              return Container(
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 2,
                                                    ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isMe
                                                      ? Colors.blueAccent
                                                            .withOpacity(0.22)
                                                      : Colors.grey[800],
                                                  borderRadius: isMe
                                                      ? const BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          topRight:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          bottomLeft:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          bottomRight:
                                                              Radius.circular(
                                                                4,
                                                              ),
                                                        )
                                                      : const BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          topRight:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          bottomLeft:
                                                              Radius.circular(
                                                                4,
                                                              ),
                                                          bottomRight:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                        ),
                                                ),
                                                constraints: BoxConstraints(
                                                  maxWidth: maxBubbleWidth,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if (imageToShow != null)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 4,
                                                              bottom: 4,
                                                            ),
                                                        child: ImageWithAspect(
                                                          imagePath:
                                                              imageToShow,
                                                        ),
                                                      ),
                                                    if (msg['text'] != null &&
                                                        (msg['text'] as String)
                                                            .isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 2,
                                                              bottom: 2,
                                                            ),
                                                        child:
                                                            _buildColoredText(
                                                              msg['text'] ?? '',
                                                            ),
                                                      ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ],
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
                              ),
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
                            // Sort messages by timestamp ascending
                            final messages = [...(snapshot.data ?? [])]
                              ..sort(
                                (a, b) => ((a['timestamp'] ?? 0).toDouble())
                                    .compareTo(
                                      (b['timestamp'] ?? 0).toDouble(),
                                    ),
                              );
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_scrollController.hasClients) {
                                _scrollController.jumpTo(
                                  _scrollController.position.maxScrollExtent,
                                );
                              }
                            });
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: ListView.builder(
                                key: ValueKey(messages.length),
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 12,
                                ),
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final msg = messages[index];
                                  final senderStr =
                                      (msg['sender'] as String?)?.trim() ?? '';
                                  final isAI =
                                      senderStr.toLowerCase() == 'modifai';
                                  final isMe =
                                      !isAI &&
                                      senderStr == _displayName(_senderName);
                                  final senderName = isAI
                                      ? 'ModifAI'
                                      : _displayName(msg['sender']);
                                  final timeStr = _formatTimestamp(
                                    (msg['timestamp'] ?? 0).toDouble(),
                                  );
                                  String? imageToShow;
                                  if (msg['image'] != null &&
                                      (msg['image'] as String).isNotEmpty) {
                                    imageToShow = msg['image'];
                                  }
                                  if (msg['audio'] != null &&
                                      (msg['audio'] as String).isNotEmpty) {
                                    // Audio message: time at the bottom, left for sent, right for received
                                    return Row(
                                      mainAxisAlignment: isMe
                                          ? MainAxisAlignment.end
                                          : MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (!isMe)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8.0,
                                            ),
                                            child: Column(
                                              children: [
                                                CircleAvatar(
                                                  backgroundColor:
                                                      Colors.blueAccent,
                                                  radius: 16,
                                                  child: Text(
                                                    senderName.isNotEmpty
                                                        ? senderName[0]
                                                              .toUpperCase()
                                                        : '?',
                                                    style: const TextStyle(
                                                      color: Colors.white,
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
                                        Column(
                                          crossAxisAlignment: isMe
                                              ? CrossAxisAlignment.start
                                              : CrossAxisAlignment.end,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                if (isMe)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          right: 6.0,
                                                          top: 2,
                                                        ),
                                                    child: Text(
                                                      timeStr,
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.white54,
                                                      ),
                                                    ),
                                                  ),
                                                Container(
                                                  margin:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 4,
                                                      ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isMe
                                                        ? Colors.blueAccent
                                                              .withOpacity(0.22)
                                                        : Colors.orangeAccent
                                                              .withOpacity(
                                                                0.18,
                                                              ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                  ),
                                                  child: _AudioPlayerWidget(
                                                    audioUrl: msg['audio'],
                                                  ),
                                                ),
                                                if (!isMe)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: 6.0,
                                                          top: 2,
                                                        ),
                                                    child: Text(
                                                      timeStr,
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.white54,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        if (isMe)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8.0,
                                            ),
                                            child: Column(
                                              children: [
                                                CircleAvatar(
                                                  backgroundColor:
                                                      Colors.blueAccent,
                                                  radius: 16,
                                                  child: Text(
                                                    senderName.isNotEmpty
                                                        ? senderName[0]
                                                              .toUpperCase()
                                                        : '?',
                                                    style: const TextStyle(
                                                      color: Colors.white,
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
                                  }
                                  if (isAI) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Column(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor:
                                                  Colors.blueGrey[700],
                                              backgroundImage: const AssetImage(
                                                'assets/modifai_logo.png',
                                              ),
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
                                            final maxBubbleWidth =
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.7;
                                            return Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 1,
                                                  ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 2,
                                                    horizontal: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[800],
                                                borderRadius:
                                                    const BorderRadius.only(
                                                      topLeft: Radius.circular(
                                                        16,
                                                      ),
                                                      topRight: Radius.circular(
                                                        16,
                                                      ),
                                                      bottomLeft:
                                                          Radius.circular(16),
                                                      bottomRight:
                                                          Radius.circular(4),
                                                    ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.10),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              constraints: BoxConstraints(
                                                maxWidth: maxBubbleWidth,
                                              ),
                                              child: Builder(
                                                builder: (context) {
                                                  final hasImage =
                                                      msg['image'] != null &&
                                                      (msg['image'] as String)
                                                          .isNotEmpty;
                                                  final hasText =
                                                      (msg['text'] ?? '')
                                                          .toString()
                                                          .isNotEmpty;
                                                  if (hasImage) {
                                                    return ImageWithAspect(
                                                      imagePath: msg['image'],
                                                      textWidget: hasText
                                                          ? Padding(
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                    top: 6.0,
                                                                  ),
                                                              child:
                                                                  _buildColoredText(
                                                                    msg['text'] ??
                                                                        '',
                                                                  ),
                                                            )
                                                          : null,
                                                    );
                                                  } else if (hasText) {
                                                    return _buildColoredText(
                                                      msg['text'] ?? '',
                                                    );
                                                  } else {
                                                    return const SizedBox.shrink();
                                                  }
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                        Column(
                                          children: [
                                            Text(
                                              timeStr,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  }
                                  // User/group message (original UI)
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
                                      Column(
                                        crossAxisAlignment: isMe
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: EdgeInsets.only(
                                              left: isMe ? 0 : 4,
                                              right: isMe ? 4 : 0,
                                              bottom: 2,
                                            ),
                                            child: Text(
                                              timeStr,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.white54,
                                              ),
                                            ),
                                          ),
                                          LayoutBuilder(
                                            builder: (context, constraints) {
                                              final maxBubbleWidth =
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.7;
                                              return Container(
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 2,
                                                    ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isMe
                                                      ? Colors.blueAccent
                                                            .withOpacity(0.22)
                                                      : Colors.grey[800],
                                                  borderRadius: isMe
                                                      ? const BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          topRight:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          bottomLeft:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          bottomRight:
                                                              Radius.circular(
                                                                4,
                                                              ),
                                                        )
                                                      : const BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          topRight:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          bottomLeft:
                                                              Radius.circular(
                                                                4,
                                                              ),
                                                          bottomRight:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                        ),
                                                ),
                                                constraints: BoxConstraints(
                                                  maxWidth: maxBubbleWidth,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if (imageToShow != null)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 4,
                                                              bottom: 4,
                                                            ),
                                                        child: ImageWithAspect(
                                                          imagePath:
                                                              imageToShow,
                                                        ),
                                                      ),
                                                    if (msg['text'] != null &&
                                                        (msg['text'] as String)
                                                            .isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 2,
                                                              bottom: 2,
                                                            ),
                                                        child:
                                                            _buildColoredText(
                                                              msg['text'] ?? '',
                                                            ),
                                                      ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ],
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
                              ),
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
                                    padding: const EdgeInsets.only(top: 4.0),
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
                                if (_pickedAudioPath != null)
                                  _buildAudioPreview(),
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
                                          final wasShowing =
                                              _showingAtSuggestion;
                                          _showingAtSuggestion = val.endsWith(
                                            '@',
                                          );
                                          if (wasShowing !=
                                              _showingAtSuggestion)
                                            setState(() {});
                                        },
                                        onTap: () {
                                          // Show suggestion if cursor is after @
                                          final text = _msgController.text;
                                          _showingAtSuggestion = text.endsWith(
                                            '@',
                                          );
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
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              onTap: () {
                                                _msgController.text =
                                                    '@askmodifai ';
                                                _msgController.selection =
                                                    TextSelection.fromPosition(
                                                      TextPosition(
                                                        offset: _msgController
                                                            .text
                                                            .length,
                                                      ),
                                                    );
                                                _showingAtSuggestion = false;
                                                setState(() {});
                                              },
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 10,
                                                ),
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
                if (_showRecordingDialog) _buildRecordingDialog(),
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
      Future.delayed(
        Duration(milliseconds: 300),
        () => _sendAI(
          widget.initialPrompt
              .replaceFirst(RegExp(r'^@askmodifai', caseSensitive: false), '')
              .trim(),
        ),
      );
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
                  const Icon(
                    Icons.smart_toy,
                    color: Colors.purpleAccent,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'ModifAI Assistant',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
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
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    margin: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 12,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
                        color: isUser
                            ? Colors.blueAccent.withOpacity(0.22)
                            : Colors.purpleAccent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        msg['text'] ?? '',
                        style: TextStyle(
                          color: isUser
                              ? Colors.white
                              : Colors.purpleAccent.shade100,
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
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
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
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Colors.lightBlueAccent,
                    ),
                    onPressed: _loading
                        ? null
                        : () {
                            final val = _aiController.text.trim();
                            if (val.isNotEmpty) _sendAI(val);
                            _aiController.clear();
                          },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.summarize,
                      color: Colors.orangeAccent,
                    ),
                    tooltip: 'Summarize this chat',
                    onPressed: _loading
                        ? null
                        : () async {
                            // Summarize the chat history
                            final chatText = widget.chatHistory
                                .map((m) => m['text'])
                                .whereType<String>()
                                .join('\n');
                            if (chatText.isEmpty) return;
                            setState(() {
                              _aiMessages.add({
                                'sender': 'user',
                                'text': '[Summarize the chat]',
                              });
                              _loading = true;
                            });
                            try {
                              final reply = await ApiService.getChatbotReply(
                                'Summarize this chat: $chatText',
                              );
                              setState(() {
                                _aiMessages.add({
                                  'sender': 'ai',
                                  'text': reply,
                                });
                                _loading = false;
                              });
                            } catch (e) {
                              setState(() {
                                _aiMessages.add({
                                  'sender': 'ai',
                                  'text': 'AI error: $e',
                                });
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

class _AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  const _AudioPlayerWidget({required this.audioUrl});
  @override
  State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  late AudioPlayer _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initAudio();
    _player.positionStream.listen((pos) {
      setState(() {
        _position = pos;
      });
    });
    _player.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
    });
  }

  Future<void> _initAudio() async {
    try {
      final d = await _player.setUrl(widget.audioUrl);
      setState(() {
        _duration = d ?? Duration.zero;
        _isReady = true;
      });
    } catch (e) {
      setState(() {
        _duration = Duration.zero;
        _isReady = false;
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sliderMax = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final sliderValue = _position.inMilliseconds.clamp(0, sliderMax).toDouble();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.orangeAccent,
          ),
          onPressed: _isReady
              ? () {
                  if (_isPlaying) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                }
              : null,
        ),
        SizedBox(
          width: 100,
          child: Slider(
            value: sliderValue,
            min: 0,
            max: sliderMax,
            onChanged: (v) async {
              await _player.seek(Duration(milliseconds: v.toInt()));
            },
            activeColor: Colors.orangeAccent,
            inactiveColor: Colors.orangeAccent.withOpacity(0.3),
          ),
        ),
        Text(
          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

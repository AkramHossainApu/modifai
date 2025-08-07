import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/chat_service.dart';

class ChatProfilePage extends StatefulWidget {
  final String userName;
  final String userEmail;
  final List<Map<String, dynamic>> chatMessages;
  const ChatProfilePage({
    super.key,
    required this.userName,
    required this.userEmail,
    required this.chatMessages,
  });

  @override
  State<ChatProfilePage> createState() => _ChatProfilePageState();
}

class _ChatProfilePageState extends State<ChatProfilePage> {
  String? _groupName;
  String? _groupImage;

  @override
  void initState() {
    super.initState();
    _groupName = widget.userName;
    _fetchGroupInfo();
  }

  Future<void> _fetchGroupInfo() async {
    final isGroup = widget.userEmail.split('_').length > 2;
    if (isGroup) {
      final doc = await FirebaseFirestore.instance.collection('group_chats').doc(widget.userEmail).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        setState(() {
          _groupName = data['name'] ?? widget.userName;
          _groupImage = data['image'];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isGroup = widget.userEmail.split('_').length > 2;
    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      appBar: isGroup
          ? PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('group_chats')
                    .doc(widget.userEmail)
                    .snapshots(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data() ?? {};
                  final groupName = data['name'] ?? widget.userName;
                  return AppBar(
                    backgroundColor: Colors.blueAccent.shade100,
                    elevation: 0,
                    title: Text('$groupName Profile', style: const TextStyle(color: Colors.white)),
                    iconTheme: const IconThemeData(color: Colors.white),
                    actions: [
                      if (isGroup && (widget.userEmail.toLowerCase().contains('akram') || widget.userEmail.toLowerCase().contains('faysal') || widget.userEmail.toLowerCase().contains('tasha')))
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white),
                          tooltip: 'Edit Group Name & Image',
                          onPressed: () async {
                            final result = await showDialog(
                              context: context,
                              builder: (ctx) => _EditGroupDialog(
                                groupId: widget.userEmail,
                                currentName: groupName,
                              ),
                            );
                            if (result != null && result is Map) {
                              await _fetchGroupInfo();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group info updated!')));
                            }
                          },
                        ),
                    ],
                  );
                },
              ),
            )
          : AppBar(
              backgroundColor: Colors.blueAccent.shade100,
              elevation: 0,
              title: Text('${widget.userName} Profile', style: const TextStyle(color: Colors.white)),
              iconTheme: const IconThemeData(color: Colors.white),
            ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Row(
            children: [
              isGroup
                  ? StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('group_chats')
                          .doc(widget.userEmail)
                          .snapshots(),
                      builder: (context, snapshot) {
                        final data = snapshot.data?.data() ?? {};
                        final groupName = data['name'] ?? widget.userName;
                        final groupImage = data['image'];
                        final hasImage = groupImage != null && groupImage.isNotEmpty;
                        return hasImage
                            ? CircleAvatar(
                                backgroundImage: NetworkImage(groupImage),
                                radius: 32,
                              )
                            : CircleAvatar(
                                backgroundColor: Colors.blueAccent,
                                radius: 32,
                                child: Text(
                                  groupName.isNotEmpty ? groupName[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white, fontSize: 28),
                                ),
                              );
                      },
                    )
                  : CircleAvatar(
                      backgroundColor: Colors.blueAccent,
                      radius: 32,
                      child: Text(
                        widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontSize: 28),
                      ),
                    ),
              const SizedBox(width: 18),
              Expanded(
                child: isGroup
                    ? StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('group_chats')
                            .doc(widget.userEmail)
                            .snapshots(),
                        builder: (context, snapshot) {
                          final data = snapshot.data?.data() ?? {};
                          final groupName = data['name'] ?? widget.userName;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(groupName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
                              Text(widget.userEmail, style: const TextStyle(color: Colors.white54, fontSize: 15)),
                            ],
                          );
                        },
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
                          Text(widget.userEmail, style: const TextStyle(color: Colors.white54, fontSize: 15)),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          // Options as grid
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              _profileOption(context, Icons.block, 'Block', Colors.redAccent, () {}),
              _profileOption(context, Icons.report, 'Report', Colors.orangeAccent, () {}),
              _profileOption(context, Icons.archive, 'Archive', Colors.blueGrey, () {}),
              _profileOption(context, Icons.delete, 'Delete', Colors.red, () {}),
              _profileOption(context, Icons.notifications_off, 'Mute', Colors.grey, () {}),
            ],
          ),
          const SizedBox(height: 32),
          // Images section
          // Links section
          // Files section
        ],
      ),
    );
  }

  Widget _profileOption(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.grey[900],
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _ZoomableImageDialog extends StatefulWidget {
  final String imgPath;
  const _ZoomableImageDialog({required this.imgPath});

  @override
  State<_ZoomableImageDialog> createState() => _ZoomableImageDialogState();
}

class _ZoomableImageDialogState extends State<_ZoomableImageDialog> {
  double _scale = 1.0;

  void _handleDoubleTap() {
    setState(() {
      if (_scale > 1.1) {
        _scale = 1.0;
      } else {
        _scale = 2.5;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(0),
      child: Stack(
        children: [
          GestureDetector(
            onDoubleTap: _handleDoubleTap,
            child: Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                scaleEnabled: true,
                panEnabled: true,
                child: AnimatedScale(
                  scale: _scale,
                  duration: const Duration(milliseconds: 200),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: Image.file(
                      File(widget.imgPath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 32,
            child: FloatingActionButton(
              backgroundColor: Colors.blueAccent,
              heroTag: 'download',
              onPressed: () async {
                // TODO: Implement download logic
                Navigator.of(context).pop();
              },
              child: const Icon(Icons.download_rounded, color: Colors.white, size: 28),
            ),
          ),
          Positioned(
            bottom: 32,
            right: 32,
            child: FloatingActionButton(
              backgroundColor: Colors.redAccent,
              heroTag: 'close',
              onPressed: () => Navigator.of(context).pop(),
              child: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditGroupDialog extends StatefulWidget {
  final String groupId;
  final String currentName;
  const _EditGroupDialog({required this.groupId, required this.currentName});

  @override
  State<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends State<_EditGroupDialog> {
  final TextEditingController _nameController = TextEditingController();
  String? _pickedImagePath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.currentName;
  }

  Future<void> _pickImage() async {
    final picker = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picker != null) {
      setState(() {
        _pickedImagePath = picker.path;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    String? imageUrl;
    if (_pickedImagePath != null) {
      imageUrl = await ChatService.uploadImageAndGetUrl(_pickedImagePath!);
    }
    final groupDoc = FirebaseFirestore.instance.collection('group_chats').doc(widget.groupId);
    final updateData = {'name': _nameController.text.trim()};
    if (imageUrl != null) updateData['image'] = imageUrl;
    await groupDoc.set(updateData, SetOptions(merge: true));
    setState(() => _loading = false);
    if (mounted) Navigator.of(context).pop({'name': _nameController.text.trim(), 'image': imageUrl});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF23242B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Edit Group Info', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _pickImage,
              child: _pickedImagePath == null
                  ? CircleAvatar(radius: 36, backgroundColor: Colors.blueGrey.shade700, child: const Icon(Icons.camera_alt, color: Colors.white, size: 32))
                  : CircleAvatar(radius: 36, backgroundImage: FileImage(File(_pickedImagePath!))),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Group Name',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  onPressed: _loading ? null : _save,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
                  child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

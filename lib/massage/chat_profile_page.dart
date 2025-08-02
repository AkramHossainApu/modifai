import 'package:flutter/material.dart';
import 'dart:io';

class ChatProfilePage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final images = chatMessages.where((msg) => msg['image'] != null && (msg['image'] as String).isNotEmpty).toList();
    final links = chatMessages.where((msg) => msg['text'] != null && _isLink(msg['text'])).toList();
    final files = chatMessages.where((msg) => msg['file'] != null && (msg['file'] as String).isNotEmpty).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF181A20),
      appBar: AppBar(
        backgroundColor: Colors.blueAccent.shade100,
        elevation: 0,
        title: Text('$userName Profile', style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          // Profile header
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blueAccent,
                radius: 32,
                child: Text(
                  userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 28),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
                    Text(userEmail, style: const TextStyle(color: Colors.white54, fontSize: 15)),
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
          if (images.isNotEmpty) ...[
            const Text('Images', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: images.length,
              itemBuilder: (context, idx) {
                final imgPath = images[idx]['image'];
                return GestureDetector(
                  onTap: () => _openImageViewer(context, imgPath),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(File(imgPath), fit: BoxFit.cover),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
          // Links section
          if (links.isNotEmpty) ...[
            const Text('Links', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            const SizedBox(height: 10),
            ...links.map((msg) => Card(
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.link, color: Colors.blueAccent),
                title: Text(msg['text'], style: const TextStyle(color: Colors.white)),
                onTap: () {},
              ),
            )),
            const SizedBox(height: 32),
          ],
          // Files section
          if (files.isNotEmpty) ...[
            const Text('Files', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            const SizedBox(height: 10),
            ...files.map((msg) => Card(
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.insert_drive_file, color: Colors.green),
                title: Text(msg['file'], style: const TextStyle(color: Colors.white)),
                onTap: () {},
              ),
            )),
          ],
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

  bool _isLink(String? text) {
    if (text == null) return false;
    final urlPattern = r'^(http|https):\/\/';
    return RegExp(urlPattern).hasMatch(text.trim());
  }

  void _openImageViewer(BuildContext context, String imgPath) {
    showDialog(
      context: context,
      builder: (context) {
        return _ZoomableImageDialog(imgPath: imgPath);
      },
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
  double _baseScale = 1.0;

  void _handleDoubleTap() {
    setState(() {
      if (_scale > 1.1) {
        _scale = 1.0;
        _baseScale = 1.0;
      } else {
        _scale = 2.5;
        _baseScale = 2.5;
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

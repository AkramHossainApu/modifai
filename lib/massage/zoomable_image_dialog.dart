import 'package:flutter/material.dart';
import 'dart:io';

class ZoomableImageDialog extends StatefulWidget {
  final String imgPath;
  const ZoomableImageDialog({required this.imgPath});

  @override
  State<ZoomableImageDialog> createState() => _ZoomableImageDialogState();
}

class _ZoomableImageDialogState extends State<ZoomableImageDialog> {
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
              heroTag: 'download_chat',
              onPressed: () async {
                // TODO: Implement download logic
                Navigator.of(context).pop();
              },
              child: const Icon(
                Icons.download_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            right: 32,
            child: FloatingActionButton(
              backgroundColor: Colors.redAccent,
              heroTag: 'close_chat',
              onPressed: () => Navigator.of(context).pop(),
              child: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

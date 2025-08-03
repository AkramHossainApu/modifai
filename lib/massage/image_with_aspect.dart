import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui';
import 'zoomable_image_dialog.dart';

class ImageWithAspect extends StatelessWidget {
  final String imagePath;
  final Widget? textWidget;
  const ImageWithAspect({required this.imagePath, this.textWidget});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final imgWidth = screenWidth * 0.5;
    final isNetwork = imagePath.startsWith('http');
    if (isNetwork) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  return Dialog(
                    backgroundColor: Colors.black,
                    child: Image.network(imagePath, fit: BoxFit.contain),
                  );
                },
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                imagePath,
                width: imgWidth,
                height: imgWidth,
                fit: BoxFit.contain,
              ),
            ),
          ),
          if (textWidget != null)
            Padding(
              padding: const EdgeInsets.only(
                top: 12,
                left: 12,
                right: 12,
                bottom: 8,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: imgWidth * 0.08,
                  color: Colors.white,
                ),
                child: textWidget!,
              ),
            ),
        ],
      );
    } else {
      return FutureBuilder<Size>(
        future: _getImageSize(imagePath),
        builder: (context, snapshot) {
          final size = snapshot.data ?? const Size(120, 120);
          final aspectRatio = size.width / size.height;
          final imgHeight = imgWidth / aspectRatio;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return ZoomableImageDialog(imgPath: imagePath);
                    },
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(imagePath),
                    width: imgWidth,
                    height: imgHeight,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              if (textWidget != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: 12,
                    left: 12,
                    right: 12,
                    bottom: 8,
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: imgWidth * 0.08,
                      color: Colors.white,
                    ),
                    child: textWidget!,
                  ),
                ),
            ],
          );
        },
      );
    }
  }

  Future<Size> _getImageSize(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final image = await decodeImageFromList(bytes);
    return Size(image.width.toDouble(), image.height.toDouble());
  }
}

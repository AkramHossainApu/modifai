import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraScreen extends StatefulWidget {
  final void Function(String? imagePath) onImageCaptured;
  const CameraScreen({Key? key, required this.onImageCaptured})
    : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isReady = false;
  bool _isTakingPicture = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _controller = CameraController(_cameras![0], ResolutionPreset.medium);
      await _controller!.initialize();
      setState(() {
        _isReady = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isTakingPicture)
      return;
    setState(() => _isTakingPicture = true);
    try {
      final XFile file = await _controller!.takePicture();
      widget.onImageCaptured(file.path);
      Navigator.of(context).pop();
    } catch (_) {
      setState(() => _isTakingPicture = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isReady && _controller != null)
            Center(child: CameraPreview(_controller!)),
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 32,
              ),
              onPressed: () {
                widget.onImageCaptured(null); // Cancel
                Navigator.of(context).pop();
              },
            ),
          ),
          if (_isReady)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: FloatingActionButton(
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.black,
                    size: 32,
                  ),
                  onPressed: _takePicture,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_signal_service.dart';
import 'dart:async';

class CallScreen extends StatefulWidget {
  final bool isCaller;
  final String callId;
  final String selfId;
  final String peerId;
  final bool isVideo;
  final String? callerName;
  final String? callerEmail;
  const CallScreen({
    super.key,
    required this.isCaller,
    required this.callId,
    required this.selfId,
    required this.peerId,
    required this.isVideo,
    this.callerName,
    this.callerEmail,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  late WebRTCSignalService _signalService;
  bool _inCalling = true;
  bool _micEnabled = true;
  bool _camEnabled = true;
  bool _remoteConnected = false;
  Timer? _timer;
  int _callSeconds = 0;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _signalService = WebRTCSignalService(widget.callId);
    _initRenderers();
    _startCall();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _callSeconds++;
      });
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _startCall() async {
    try {
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      };
      debugPrint('Creating peer connection...');
      _peerConnection = await createPeerConnection(config);
      debugPrint('Getting user media...');
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideo,
      });
      debugPrint('Got local stream: \\${_localStream?.id}');
      _localRenderer.srcObject = _localStream;
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
      _peerConnection!.onTrack = (event) {
        debugPrint('onTrack: kind=\\${event.track.kind}');
        if (event.track.kind == 'video' || event.track.kind == 'audio') {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
            _remoteConnected = true;
          });
        }
      };
      _peerConnection!.onIceCandidate = (candidate) {
        debugPrint('onIceCandidate: \\${candidate.candidate}');
        _signalService.addIceCandidate(candidate.toMap(), widget.selfId);
      };
      if (widget.isCaller) {
        debugPrint('Caller: creating offer...');
        RTCSessionDescription offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        debugPrint('Set local offer, sending to Firestore...');
        await _signalService.setSDP('offer', offer.toMap());
        // Listen for answer
        _signalService.sdpStream('answer').listen((doc) async {
          debugPrint('Caller: got answer doc: exists=\\${doc.exists}');
          if (doc.exists && doc.data() != null) {
            final answer = doc.data()!;
            debugPrint('Caller: setting remote description (answer)...');
            await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(answer['sdp'], answer['type']),
            );
          }
        });
      } else {
        // Callee listens for offer
        debugPrint('Callee: waiting for offer...');
        _signalService.sdpStream('offer').listen((doc) async {
          debugPrint('Callee: got offer doc: exists=\\${doc.exists}');
          if (doc.exists && doc.data() != null) {
            final offer = doc.data()!;
            debugPrint('Callee: setting remote description (offer)...');
            await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(offer['sdp'], offer['type']),
            );
            debugPrint('Callee: creating answer...');
            RTCSessionDescription answer = await _peerConnection!
                .createAnswer();
            await _peerConnection!.setLocalDescription(answer);
            debugPrint('Callee: set local answer, sending to Firestore...');
            await _signalService.setSDP('answer', answer.toMap());
          }
        });
      }
      // Listen for ICE candidates
      debugPrint('Listening for ICE candidates from peer: \\${widget.peerId}');
      _signalService.iceCandidatesStream(widget.peerId).listen((snapshot) {
        for (var doc in snapshot.docChanges) {
          final data = doc.doc.data();
          debugPrint('Received ICE candidate from peer: \\${data}');
          if (data != null) {
            _peerConnection!
                .addCandidate(
                  RTCIceCandidate(
                    data['candidate'],
                    data['sdpMid'],
                    data['sdpMLineIndex'],
                  ),
                )
                .catchError((e) {
                  debugPrint('Error adding ICE candidate: \\${e}');
                });
          }
        }
      });
    } catch (e) {
      setState(() {
        _errorMsg = 'Call error: $e';
      });
      debugPrint('Call error: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peerConnection?.close();
    _localStream?.dispose();
    _signalService.cleanup();
    super.dispose();
  }

  void _toggleMic() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      for (var track in audioTracks) {
        track.enabled = !track.enabled;
        _micEnabled = track.enabled;
      }
      setState(() {});
    }
  }

  void _toggleCamera() {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      for (var track in videoTracks) {
        track.enabled = !track.enabled;
        _camEnabled = track.enabled;
      }
      setState(() {});
    }
  }

  void _switchCamera() async {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await Helper.switchCamera(videoTracks[0]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          widget.isVideo
              ? RTCVideoView(_remoteRenderer)
              : Center(child: Icon(Icons.call, color: Colors.green, size: 120)),
          if (widget.isVideo)
            Positioned(
              right: 20,
              top: 40,
              child: SizedBox(
                width: 120,
                height: 160,
                child: RTCVideoView(_localRenderer, mirror: true),
              ),
            ),
          // Show caller info at the top
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: Column(
                children: [
                  if (widget.callerName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 2.0),
                      child: Text(
                        'Caller: ${widget.callerName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  if (widget.callerEmail != null)
                    Text(
                      widget.callerEmail!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 40,
            child: Center(
              child: Column(
                children: [
                  if (_errorMsg != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 8),
                      color: Colors.red.withOpacity(0.8),
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  if (_remoteConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatDuration(_callSeconds),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  backgroundColor: _micEnabled ? Colors.blue : Colors.grey,
                  heroTag: 'mic',
                  child: Icon(_micEnabled ? Icons.mic : Icons.mic_off),
                  onPressed: _toggleMic,
                ),
                const SizedBox(width: 20),
                if (widget.isVideo)
                  FloatingActionButton(
                    backgroundColor: _camEnabled ? Colors.blue : Colors.grey,
                    heroTag: 'cam',
                    child: Icon(
                      _camEnabled ? Icons.videocam : Icons.videocam_off,
                    ),
                    onPressed: _toggleCamera,
                  ),
                if (widget.isVideo) const SizedBox(width: 20),
                if (widget.isVideo)
                  FloatingActionButton(
                    backgroundColor: Colors.orange,
                    heroTag: 'switch',
                    child: const Icon(Icons.cameraswitch),
                    onPressed: _switchCamera,
                  ),
                const SizedBox(width: 20),
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  heroTag: 'end',
                  child: const Icon(Icons.call_end),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
          if (!_remoteConnected && _errorMsg == null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    widget.isCaller ? 'Calling...' : 'Connecting...',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

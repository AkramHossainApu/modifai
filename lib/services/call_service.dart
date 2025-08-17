import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CallService {
  static final _calls = FirebaseFirestore.instance.collection('calls');

  // Initiate a call
  static Future<void> startCall({
    required String callerId,
    required String callerName,
    required String receiverId,
    required String receiverName,
    required bool isVideo,
  }) async {
    final callId = _callDocId(callerId, receiverId);
    await _calls.doc(callId).set({
      'callerId': callerId,
      'callerName': callerName,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'isVideo': isVideo,
      'status': 'ringing',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // Listen for call events
  static Stream<DocumentSnapshot<Map<String, dynamic>>> callStream(
    String callerId,
    String receiverId,
  ) {
    final callId = _callDocId(callerId, receiverId);
    return _calls.doc(callId).snapshots();
  }

  // Accept call
  static Future<void> acceptCall(String callerId, String receiverId) async {
    final callId = _callDocId(callerId, receiverId);
    await _calls.doc(callId).update({'status': 'accepted'});
  }

  // Reject or end call
  static Future<void> endCall(String callerId, String receiverId) async {
    final callId = _callDocId(callerId, receiverId);
    await _calls.doc(callId).update({'status': 'ended'});
    await Future.delayed(const Duration(seconds: 1));
    await _calls.doc(callId).delete();
  }

  // Explicitly delete a call document
  static Future<void> deleteCallDoc(String callerId, String receiverId) async {
    final callId = _callDocId(callerId, receiverId);
    await _calls.doc(callId).delete();
  }

  // Public method to get call doc id
  static String getCallDocId(String callerId, String receiverId) {
    return _callDocId(callerId, receiverId);
  }

  static String _callDocId(String callerId, String receiverId) {
    // Unique doc id for a call between two users
    return callerId.hashCode <= receiverId.hashCode
        ? '${callerId}_$receiverId'
        : '${receiverId}_$callerId';
  }
}

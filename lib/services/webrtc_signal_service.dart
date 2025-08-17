import 'package:cloud_firestore/cloud_firestore.dart';

class WebRTCSignalService {
  final String callId;
  final CollectionReference _calls = FirebaseFirestore.instance.collection(
    'calls',
  );

  WebRTCSignalService(this.callId);

  // Set local SDP offer/answer
  Future<void> setSDP(String type, Map<String, dynamic> sdp) async {
    await _calls.doc(callId).collection('signals').doc(type).set(sdp);
  }

  // Listen for remote SDP offer/answer
  Stream<DocumentSnapshot<Map<String, dynamic>>> sdpStream(String type) {
    return _calls.doc(callId).collection('signals').doc(type).snapshots();
  }

  // Add ICE candidate
  Future<void> addIceCandidate(
    Map<String, dynamic> candidate,
    String forUser,
  ) async {
    await _calls
        .doc(callId)
        .collection('signals')
        .doc('candidates')
        .collection(forUser)
        .add(candidate);
  }

  // Listen for ICE candidates
  Stream<QuerySnapshot<Map<String, dynamic>>> iceCandidatesStream(
    String forUser,
  ) {
    return _calls
        .doc(callId)
        .collection('signals')
        .doc('candidates')
        .collection(forUser)
        .snapshots();
  }

  // Clean up signaling data
  Future<void> cleanup() async {
    final signals = _calls.doc(callId).collection('signals');
    final snap = await signals.get();
    for (var doc in snap.docs) {
      await doc.reference.delete();
    }
  }
}

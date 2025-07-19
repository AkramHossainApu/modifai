import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  static const String baseUrl = 'http://localhost:8000'; // Change if needed

  static Future<void> sendMessage({
    required String sender,
    required String receiver,
    required String text,
    required double timestamp,
  }) async {
    // Use a consistent chatId for both users
    final chatId = _getChatId(sender, receiver);
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
          'sender': sender,
          'receiver': receiver,
          'text': text,
          'timestamp': timestamp,
        });
  }

  static Future<List<Map<String, dynamic>>> getChatHistory({
    required String user1,
    required String user2,
  }) async {
    final chatId = _getChatId(user1, user2);
    final snapshot = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp')
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  static String _getChatId(String user1, String user2) {
    // Ensure chatId is the same for both users
    final sorted = [user1, user2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      // Use 'name' as username
      return {'name': data['name'] ?? '', 'email': data['email'] ?? ''};
    }).toList();
  }

  static Stream<List<Map<String, dynamic>>> chatStream({
    required String user1,
    required String user2,
  }) {
    final chatId = _getChatId(user1, user2);
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  static Future<void> initializeFCM() async {
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    // Store the token in Firestore for each user
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && token != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'fcmToken': token},
      );
    }
  }

  static void listenForMessages(Function(RemoteMessage) onMessage) {
    FirebaseMessaging.onMessage.listen(onMessage);
  }
}

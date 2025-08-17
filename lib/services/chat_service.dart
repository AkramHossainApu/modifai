import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ChatService {
  // Automatically select backend URL based on platform
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8000';
    } else if (Platform.isAndroid) {
      // Android emulator
      return 'http://10.0.2.2:8000';
    } else {
      // iOS simulator, desktop, or real device (update to your LAN IP if needed)
      return 'http://localhost:8000';
    }
  }

  static Future<String> _getUsernameFromEmail(String email) async {
    // Try to get the user's name from Firestore, fallback to email username part
    final users = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (users.docs.isNotEmpty) {
      final name = users.docs.first.data()['name'] ?? '';
      if (name.isNotEmpty) {
        // Remove spaces, capitalize each word, join with _
        return name
            .trim()
            .split(RegExp(r'\s+'))
            .map((s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '')
            .join('_');
      }
    }
    // Fallback: use email before @, replace . and - with _, capitalize
    final user = email.split('@')[0].replaceAll(RegExp(r'[.\-]'), '_');
    return user
        .split('_')
        .map((s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '')
        .join('_');
  }

  static Future<String> getChatIdByUsernames(String user1, String user2) async {
    final name1 = await _getUsernameFromEmail(user1.trim().toLowerCase());
    final name2 = await _getUsernameFromEmail(user2.trim().toLowerCase());
    final sorted = [name1, name2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  static Future<void> sendMessage({
    required String sender,
    required String receiver,
    required String text,
    required double timestamp,
    String? imagePath, // Optional image path
    String? audioPath, // Optional audio path
    String? chatIdOverride, // NEW: allow explicit chatId
  }) async {
    final chatId =
        chatIdOverride ?? await getChatIdByUsernames(sender, receiver);
    final messageData = {
      'sender': sender,
      'receiver': receiver,
      'text': text,
      'timestamp': timestamp,
    };
    if (imagePath != null && imagePath.isNotEmpty) {
      messageData['image'] = imagePath;
    }
    if (audioPath != null && audioPath.isNotEmpty) {
      messageData['audio'] = audioPath;
    }
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageData);
  }

  static Future<List<Map<String, dynamic>>> getChatHistory({
    required String user1,
    required String user2,
  }) async {
    final chatId = await getChatIdByUsernames(user1, user2);
    final snapshot = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp')
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  static Stream<List<Map<String, dynamic>>> chatStream({
    required String user1,
    required String user2,
  }) async* {
    final chatId = await getChatIdByUsernames(user1, user2);
    yield* FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList(),
        );
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

  // Send a friend request from currentUserEmail to targetEmail
  static Future<void> sendFriendRequest(
    String fromEmail,
    String toEmail,
  ) async {
    final usersRef = FirebaseFirestore.instance.collection('users');
    final toUser = await usersRef
        .where('email', isEqualTo: toEmail)
        .limit(1)
        .get();
    if (toUser.docs.isEmpty) return;
    final toUserId = toUser.docs.first.id;
    await usersRef
        .doc(toUserId)
        .collection('friend_requests')
        .doc(fromEmail)
        .set({'from': fromEmail, 'timestamp': FieldValue.serverTimestamp()});
  }

  // Accept a friend request
  static Future<void> acceptFriendRequest(
    String currentEmail,
    String fromEmail,
  ) async {
    final usersRef = FirebaseFirestore.instance.collection('users');
    // Get current user doc
    final currentUser = await usersRef
        .where('email', isEqualTo: currentEmail)
        .limit(1)
        .get();
    if (currentUser.docs.isEmpty) return;
    final currentUserId = currentUser.docs.first.id;
    // Get from user doc
    final fromUser = await usersRef
        .where('email', isEqualTo: fromEmail)
        .limit(1)
        .get();
    if (fromUser.docs.isEmpty) return;
    final fromUserId = fromUser.docs.first.id;
    // Add each other as friends
    await usersRef.doc(currentUserId).collection('friends').doc(fromEmail).set({
      'email': fromEmail,
    });
    await usersRef.doc(fromUserId).collection('friends').doc(currentEmail).set({
      'email': currentEmail,
    });
    // Remove the friend request
    await usersRef
        .doc(currentUserId)
        .collection('friend_requests')
        .doc(fromEmail)
        .delete();
  }

  // Get friend requests for a user
  static Future<List<String>> getFriendRequests(String currentEmail) async {
    final usersRef = FirebaseFirestore.instance.collection('users');
    final currentUser = await usersRef
        .where('email', isEqualTo: currentEmail)
        .limit(1)
        .get();
    if (currentUser.docs.isEmpty) return [];
    final currentUserId = currentUser.docs.first.id;
    final reqs = await usersRef
        .doc(currentUserId)
        .collection('friend_requests')
        .get();
    return reqs.docs.map((doc) => doc.id).toList();
  }

  // Get friends for a user
  static Future<List<String>> getFriends(String currentEmail) async {
    final usersRef = FirebaseFirestore.instance.collection('users');
    final currentUser = await usersRef
        .where('email', isEqualTo: currentEmail)
        .limit(1)
        .get();
    if (currentUser.docs.isEmpty) return [];
    final currentUserId = currentUser.docs.first.id;
    final friends = await usersRef
        .doc(currentUserId)
        .collection('friends')
        .get();
    return friends.docs.map((doc) => doc.id).toList();
  }

  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {'name': data['name'] ?? '', 'email': data['email'] ?? ''};
    }).toList();
  }

  static Future<String?> uploadImageAndGetUrl(String filePath) async {
    final uri = Uri.parse('$baseUrl/upload_drive');
    final req = http.MultipartRequest('POST', uri);
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    final rsp = await req.send();
    final body = await rsp.stream.bytesToString();
    if (rsp.statusCode == 200) {
      final data = jsonDecode(body);
      return data['url'] as String?;
    }
    print('Drive upload failed: $body');
    return null;
  }

  static Future<void> deleteUserChat(String user1, String user2) async {
    final chatId = await getChatIdByUsernames(user1, user2);
    await FirebaseFirestore.instance.collection('chats').doc(chatId).delete();
  }

  static Future<List<String>> getChatDocumentIds() async {
    final snapshot = await FirebaseFirestore.instance.collection('chats').get();
    return snapshot.docs.map((doc) => doc.id).toList();
  }

  /// Returns the user-to-user chatId for two users, regardless of sender/receiver order.
  static Future<String> getUserToUserChatId(String user1, String user2) async {
    return await getChatIdByUsernames(user1, user2);
  }

  /// Usage for AI response:
  /// await ChatService.sendMessage(
  ///   sender: 'ModifAI',
  ///   receiver: chatId, // e.g. "User1_User2"
  ///   text: aiReply,
  ///   timestamp: ...,
  ///   chatIdOverride: chatId,
  /// );

  static Future<void> deleteMessage({
    required String chatId,
    required String messageId,
    String? imageUrl,
    String? audioUrl,
  }) async {
    // Delete the message from Firestore
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
    // Delete image/audio from Google Drive if present
    if ((imageUrl != null && imageUrl.isNotEmpty) ||
        (audioUrl != null && audioUrl.isNotEmpty)) {
      final uri = Uri.parse(' {baseUrl}/delete_drive');
      final body = <String, dynamic>{};
      if (imageUrl != null && imageUrl.isNotEmpty) body['url'] = imageUrl;
      if (audioUrl != null && audioUrl.isNotEmpty) body['audioUrl'] = audioUrl;
      try {
        await http.post(
          uri,
          body: jsonEncode(body),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        print('Failed to delete file from Drive: $e');
      }
    }
  }

  static Future<void> deleteUserMessage({
    required String sender,
    required String receiver,
    required String messageId,
    String? imageUrl,
    String? audioUrl,
  }) async {
    final chatId = await getChatIdByUsernames(sender, receiver);
    await deleteMessage(
      chatId: chatId,
      messageId: messageId,
      imageUrl: imageUrl,
      audioUrl: audioUrl,
    );
  }
}

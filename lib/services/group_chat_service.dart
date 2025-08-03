import 'package:cloud_firestore/cloud_firestore.dart';

class GroupChatService {
  static Future<String> getGroupChatId(List<String> emails) async {
    // Get names for all emails
    final usersSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('email', whereIn: emails)
        .get();
    final names = usersSnapshot.docs
        .map((doc) => doc.data()['name'] ?? doc.data()['email'])
        .toList();
    names.sort();
    return names.join('_');
  }

  static Future<void> createGroupChat(List<String> emails) async {
    final groupId = await getGroupChatId(emails);
    await FirebaseFirestore.instance.collection('group_chats').doc(groupId).set(
      {'users': emails, 'createdAt': DateTime.now().millisecondsSinceEpoch},
    );
  }

  static Future<void> sendGroupMessage({
    required String groupId,
    required String sender,
    required String text,
    required double timestamp,
    String? imagePath,
  }) async {
    final messageData = {
      'sender': sender,
      'text': text,
      'timestamp': timestamp,
    };
    if (imagePath != null && imagePath.isNotEmpty) {
      messageData['image'] = imagePath;
    }
    await FirebaseFirestore.instance
        .collection('group_chats')
        .doc(groupId)
        .collection('messages')
        .add(messageData);
  }

  static Stream<List<Map<String, dynamic>>> groupChatStream(String groupId) {
    return FirebaseFirestore.instance
        .collection('group_chats')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  static Future<List<Map<String, dynamic>>> getAllGroupsForUser(
    String email,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('group_chats')
        .where('users', arrayContains: email)
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  static Future<void> deleteGroupChat(String groupId) async {
    await FirebaseFirestore.instance
        .collection('group_chats')
        .doc(groupId)
        .delete();
  }

  static Future<List<String>> getGroupChatDocumentIds() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('group_chats')
        .get();
    return snapshot.docs.map((doc) => doc.id).toList();
  }
}

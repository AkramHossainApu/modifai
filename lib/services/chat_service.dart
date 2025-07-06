import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatService {
  static const String baseUrl = 'http://localhost:8000'; // Change if needed

  static Future<void> sendMessage({
    required String sender,
    required String receiver,
    required String text,
    required double timestamp,
  }) async {
    final url = Uri.parse('$baseUrl/chat/send');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sender': sender,
        'receiver': receiver,
        'text': text,
        'timestamp': timestamp,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send message');
    }
  }

  static Future<List<Map<String, dynamic>>> getChatHistory({
    required String user1,
    required String user2,
  }) async {
    final url = Uri.parse('$baseUrl/chat/history?user1=$user1&user2=$user2');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch chat history');
    }
  }
}

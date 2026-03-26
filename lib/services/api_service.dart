import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ApiService {
  static const String baseUrl = 'http://10.0.2.2:8000';

  /// OpenAI image generation
  static Future<File> generateOpenAIImage(String prompt) async {
    var response = await http.post(
      Uri.parse('$baseUrl/generate_openai_image'),
      body: {'prompt': prompt},
    );
    if (response.statusCode == 200 &&
        response.headers['content-type']?.contains('image/png') == true) {
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/openai_reply_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else {
      throw Exception('OpenAI image error: ${response.body}');
    }
  }

  /// OpenAI chat (text)
  static Future<String> openaiChat(String message) async {
    var response = await http.post(
      Uri.parse('$baseUrl/openai_chat'),
      body: {'message': message},
    );
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      return decoded['reply'] ?? '';
    } else {
      throw Exception('OpenAI chat error: ${response.body}');
    }
  }

  /// Gemini chat (text)
  static Future<dynamic> geminiChat({required String chatId, required String message}) async {
    var response = await http.post(
      Uri.parse('$baseUrl/gemini_chat'),
      body: {'chat_id': chatId, 'message': message},
    );
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      return decoded['reply'] ?? '';
    } else {
      throw Exception('Gemini chat error: ${response.body}');
    }
  }
}

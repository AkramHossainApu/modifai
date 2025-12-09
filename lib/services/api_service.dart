import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ApiService {
  static const String baseUrl = 'http://10.0.2.2:8000';

  /// Single-turn Gemini image generation
  static Future<dynamic> generateGeminiImage(
    String prompt,
    File imageFile,
  ) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/generate_gemini_image'),
    );
    request.fields['prompt'] = prompt;
    request.files.add(
      await http.MultipartFile.fromPath('file', imageFile.path),
    );
    final response = await request.send();
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('application/json')) {
      final respStr = await response.stream.bytesToString();
      return json.decode(respStr)['text'];
    } else if (contentType.contains('image/png')) {
      final bytes = await response.stream.toBytes();
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/gemini_reply_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      return file;
    } else {
      throw Exception('Unknown response type: $contentType');
    }
  }

  /// Multi-turn Gemini chat (text and image)
  static Future<dynamic> geminiChat({
    required String chatId,
    required String message,
    File? imageFile,
  }) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/gemini_chat'),
    );
    request.fields['chat_id'] = chatId;
    request.fields['message'] = message;
    if (imageFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );
    }
    final response = await request.send();
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('application/json')) {
      final respStr = await response.stream.bytesToString();
      final decoded = json.decode(respStr);
      return decoded['results'] ?? decoded;
    } else if (contentType.contains('image/png')) {
      final bytes = await response.stream.toBytes();
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/gemini_chat_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      return file;
    } else {
      throw Exception('Unknown response type: $contentType');
    }
  }
}

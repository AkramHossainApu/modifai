import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ApiService {
  static const String baseUrl = 'http://10.0.2.2:8000';

  /// Returns either a String (text reply) or  a File (image)
  static Future<dynamic> getChatbotReply(String message) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat'),
      body: {'message': message},
    );
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('application/json')) {
      return json.decode(response.body)['reply'];
    } else if (contentType.contains('image/png')) {
      // Save image to temp dir
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/ai_reply_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else {
      throw Exception('Unknown response type: $contentType');
    }
  }

  static Future<File> getDecoratedImage(
    File imageFile, {
    String prompt =
        "a beautiful, modern, cozy, well-lit interior design for this room",
  }) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/decorate'));
    request.files.add(
      await http.MultipartFile.fromPath('file', imageFile.path),
    );
    request.fields['prompt'] = prompt;
    var response = await request.send();
    if (response.statusCode == 200) {
      final bytes = await response.stream.toBytes();
      final file = File(
        '${imageFile.parent.path}/decorated_${imageFile.uri.pathSegments.last}',
      );
      await file.writeAsBytes(bytes);
      return file;
    } else {
      throw Exception('Failed to get decorated image');
    }
  }
}

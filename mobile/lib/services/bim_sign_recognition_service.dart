import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// A word plus its accumulated BIM travel phrase, returned by the Python model.
class BimSignRecognition {
  const BimSignRecognition({
    required this.word,
    required this.confidence,
    required this.glosses,
    required this.malay,
    required this.chinese,
    required this.english,
    required this.matched,
  });

  final String word;
  final double confidence;
  final List<String> glosses;
  final String malay;
  final String chinese;
  final String english;
  final bool matched;

  factory BimSignRecognition.fromJson(Map<String, dynamic> json) {
    return BimSignRecognition(
      word: json['word'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      glosses: (json['glosses'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      malay: json['malay'] as String? ?? '',
      chinese: json['chinese'] as String? ?? '',
      english: json['english'] as String? ?? '',
      matched: json['matched'] as bool? ?? false,
    );
  }
}

class BimSignRecognitionException implements Exception {
  const BimSignRecognitionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// BIM-only client for the Python SLR model.
///
/// Its endpoint is deliberately separate from the existing general
/// [SignTranslationService], so ASL/CSL never call this API or depend on the
/// BIM model being online.
class BimSignRecognitionService {
  BimSignRecognitionService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<BimSignRecognition> recognizeVideo({
    required String videoPath,
    required List<String> previousGlosses,
  }) async {
    final endpoint = dotenv.maybeGet('BIM_SIGN_API_URL')?.trim() ?? '';
    if (endpoint.isEmpty) {
      throw const BimSignRecognitionException(
        'BIM recognition is not configured. Add BIM_SIGN_API_URL to .env.',
      );
    }

    final clip = File(videoPath);
    if (!await clip.exists()) {
      throw const BimSignRecognitionException(
        'The recorded BIM video is unavailable.',
      );
    }

    final request = http.MultipartRequest('POST', Uri.parse(endpoint))
      ..headers['Accept'] = 'application/json'
      ..fields['glosses'] = jsonEncode(previousGlosses)
      ..files.add(await http.MultipartFile.fromPath('video', videoPath));

    try {
      final client = _client;
      final streamed =
          await (client == null ? request.send() : client.send(request))
              .timeout(const Duration(seconds: 20));
      final body = await streamed.stream.bytesToString();
      final payload = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw BimSignRecognitionException(_errorMessage(payload));
      }
      if (payload is! Map<String, dynamic>) {
        throw const BimSignRecognitionException(
          'BIM service returned an invalid response.',
        );
      }
      return BimSignRecognition.fromJson(payload);
    } on BimSignRecognitionException {
      rethrow;
    } on SocketException {
      throw const BimSignRecognitionException(
        'Cannot reach BIM recognition. Check that the BIM service is running.',
      );
    } on HttpException {
      throw const BimSignRecognitionException(
        'BIM recognition connection failed.',
      );
    } on FormatException {
      throw const BimSignRecognitionException(
        'BIM service returned unreadable data.',
      );
    }
  }

  String _errorMessage(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final detail = payload['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is Map<String, dynamic>) {
        final message = detail['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    }
    return 'BIM could not recognise that sign. Keep your hands and face visible, then try again.';
  }
}

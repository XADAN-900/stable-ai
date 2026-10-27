import 'dart:convert';

import 'package:http/http.dart' as http;

/// Gerçek LLM erişimi (ücretsiz, anahtarsız, kayıt gerektirmeyen uç nokta).
///
/// İstek herhangi bir nedenle başarısız olursa (yok, 429, zaman aşımı,
/// bozum cevap) `null` döner ve çağıran taraf cihazda çalışan kural
/// tabanlı motora döner. Böylece uygulama internetsiz de çalışır.
class Ai {
  static final Uri _chatUri =
      Uri.parse('https://text.pollinations.ai/openai/chat/completions');

  static const Duration timeout = Duration(seconds: 25);

  static String systemPrompt(String lang, String? userName) {
    final who = (userName == null || userName.isEmpty)
        ? ''
        : ' Kullanıcının adı $userName, zaman zaman ona hitap edebilirsin.';
    switch (lang) {
      case 'tr':
        return 'Sen Stable AI\'sın: samimi, yardımsever ve kısa cevap veren bir sohbet asistanısın. '
            'Kullanıcının yazdığı dilde cevap ver (Türkçe konuşuyorsa Türkçe).'
            'Kod sorularında net ve uygulanabilir yaz.$who';
      case 'de':
        return 'Du bist Stable AI: ein freundlicher, hilfsbereiter Chat-Assistent mit kurzen Antworten. '
            'Antworte in der Sprache des Nutzers (Deutsch, wenn er Deutsch schreibt).'
            'Bei Programmierfragen sei konkret und umsetzbar.$who';
      default:
        return 'You are Stable AI: a friendly, helpful chat assistant who keeps answers short. '
            'Reply in the language the user writes in. '
            'For coding questions be concrete and actionable.$who';
    }
  }

  /// Sohbet geçmişinin tamamını gönderir; sohbetin son mesajı kullanıcı
  /// mesajı olmalıdır.
  static Future<String?> chat({
    required String lang,
    required List<Map<String, String>> history,
  }) async {
    if (history.isEmpty) return null;
    final trimmed =
        history.length > 14 ? history.sublist(history.length - 14) : history;
    final body = jsonEncode({
      'model': 'openai',
      'stream': false,
      'messages': [
        {'role': 'system', 'content': systemPrompt(lang, null)},
        ...trimmed,
      ],
    });

    // 1. Motor: OpenAI uyumlu sohbet tamamlama.
    try {
      final res = await http
          .post(
            _chatUri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        final content = _extract(jsonDecode(utf8.decode(res.bodyBytes)));
        if (content != null) return content;
      }
    } catch (_) {
      // ikinci motora geç
    }

    // 2. Motor: düz metin uç noktası (POST engellenirse bu devreye girer).
    try {
      final prompt = _plain(lang, trimmed);
      final res = await http
          .get(Uri.parse(
              'https://text.pollinations.ai/${Uri.encodeComponent(prompt)}'))
          .timeout(timeout);
      if (res.statusCode == 200) {
        final text = utf8.decode(res.bodyBytes).trim();
        if (text.isNotEmpty &&
            !text.startsWith('{') &&
            !text.contains('"error"')) {
          return text;
        }
      }
    } catch (_) {
      // yerel motor devreye girer
    }
    return null;
  }

  /// OpenAI cevabından düz metni çeker.
  static String? _extract(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map<String, dynamic>) return null;
    final message = first['message'];
    if (message is! Map<String, dynamic>) return null;
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) return content.trim();
    return null;
  }

  /// GET uç noktası için kısa, düz bir istek metni üretir.
  static String _plain(String lang, List<Map<String, String>> msgs) {
    final sb = StringBuffer(systemPrompt(lang, null))..writeln();
    final tail = msgs.length > 4 ? msgs.sublist(msgs.length - 4) : msgs;
    for (final m in tail) {
      final role = m['role'] == 'user' ? 'Kullanıcı' : 'Sen';
      sb.writeln('$role: ${m['content']}');
    }
    sb.write('Sen:');
    var s = sb.toString().trim();
    if (s.length > 700) s = s.substring(s.length - 700);
    return s;
  }
}

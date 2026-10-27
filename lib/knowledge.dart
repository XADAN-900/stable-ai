import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'bot.dart';
import 'update.dart';

/// Depodaki `stable_ai_kb.json` ile bilgi tabanını günceller.
///
/// İnternet varsa dosya çekilip cihaza kaydedilir; yoksa en son kaydedilmiş
/// (güncellenmiş) sürüm açılışta yüklenmeye devam eder. Bu yüzden uygulama
/// internetsizken de "güncellenmiş hali" ile çalışır.
class Knowledge {
  static const String file = 'stable_ai_kb.json';

  static String url(String repo, {String ref = 'main'}) =>
      'https://raw.githubusercontent.com/${repo.trim()}/$ref/$file';

  /// Depodan günceller. Başarısızsa sessizce false döner.
  static Future<bool> sync(String repo) async {
    if (!AppUpdater.validRepo(repo)) return false;
    try {
      final res = await http
          .get(Uri.parse(url(repo)))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return false;
      final text = utf8.decode(res.bodyBytes);
      final data = jsonDecode(text);
      if (data is! Map<String, dynamic>) return false;
      if (!Bot.applyKnowledge(data)) return false;
      final p = await SharedPreferences.getInstance();
      await p.setString('kb', text);
      await p.setInt('kbAt', DateTime.now().millisecondsSinceEpoch);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Başlangıçta cihazda kayıtlı (son güncellenmiş) bilgi tabanını yükler.
  static Future<bool> loadCached() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('kb');
    if (raw == null || raw.isEmpty) return false;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return false;
      return Bot.applyKnowledge(data);
    } catch (_) {
      return false;
    }
  }

  /// Son başarılı güncellemenin zamanı (yoksa null).
  static Future<DateTime?> lastSynced() async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt('kbAt');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

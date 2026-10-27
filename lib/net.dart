import 'package:http/http.dart' as http;

/// İnternet erişimini hızlı tespit eder; sonuç kısa süre önbelleklenir.
///
/// Amaç: bağlantı yokken LLM'in 25 sn zaman aşımını beklemek yerine doğrudan
/// cihazdaki son güncellenmiş motoru kullanmak.
class Net {
  static bool _online = false;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  /// true: internet var ve LLM servisine ulaşılabilir.
  /// false: yok → yerel motor devrede.
  static Future<bool> isOnline() async {
    final now = DateTime.now();
    if (now.difference(_at).inSeconds < 30) return _online;
    try {
      final r = await http
          .get(Uri.parse('https://text.pollinations.ai/models'))
          .timeout(const Duration(seconds: 4));
      _online = r.statusCode == 200 && r.body.trim().isNotEmpty;
    } catch (_) {
      _online = false;
    }
    _at = now;
    return _online;
  }

  /// Açılışta önbelleği doldurur (zamanlamayı sıfırlar).
  static Future<void> warmUp() async {
    _at = DateTime.fromMillisecondsSinceEpoch(0);
    await isOnline();
  }
}

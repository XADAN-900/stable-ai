import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// GitHub Releases tabanlı kendini güncelleme (saf Dart tarafı).
///
/// Akış: depodaki `releases/latest` çekilir, etiket kurulu sürümden yeniyse
/// ilk `.apk` varlığı indirilir. Kurulum Flutter/Android tarafında
/// `lib/installer.dart` üzerinden yapılır.
class UpdateInfo {
  final String version;
  final String apkUrl;
  final String releaseUrl;
  const UpdateInfo(this.version, this.apkUrl, this.releaseUrl);
}

class AppUpdater {
  /// Ayarlar boş bırakılırsa kullanılan gömülü depo.
  /// Yeni sürüm çıkınca bu depodaki Release'ten APK indirilir.
  static const String defaultRepo = 'XADAN-900/stable-ai';

  /// Ayarlar alanı öncelikli, boşsa gömülü depo kullanılır.
  static String repoFor(String userRepo) {
    final u = userRepo.trim();
    return u.isNotEmpty ? u : defaultRepo;
  }

  /// `owner/repo` biçiminde olmalı.
  static bool validRepo(String repo) =>
      RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(repo.trim()) &&
      !repo.contains('OWNER');

  /// a > b mi? "v1.2.10" gibi etiketleri sayısal olarak karşılaştırır.
  static bool newer(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parts(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[^\d]+'))
      .where((s) => s.isNotEmpty)
      .map((s) => int.tryParse(s) ?? 0)
      .toList();

  /// Yeni sürüm varsa döndürür, yoksa null.
  static Future<UpdateInfo?> check(String repo, String currentVersion) async {
    if (!validRepo(repo)) return null;
    final uri = Uri.parse(
        'https://api.github.com/repos/${repo.trim()}/releases/latest');
    final res = await http.get(uri, headers: const {
      'Accept': 'application/vnd.github+json'
    }).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map<String, dynamic>) return null;

    final tag = data['tag_name'];
    if (tag is! String || tag.isEmpty) return null;
    if (!newer(tag, currentVersion)) return null;

    String? apkUrl;
    final assets = data['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map<String, dynamic>) continue;
        final name = a['name'];
        final url = a['browser_download_url'];
        if (name is String &&
            name.toLowerCase().endsWith('.apk') &&
            url is String) {
          apkUrl = url;
          break;
        }
      }
    }
    if (apkUrl == null) return null;

    final html = data['html_url'];
    return UpdateInfo(
        _parts(tag).join('.'), apkUrl, html is String ? html : '');
  }

  /// APK'yı `dir` içine indirir; ilerleme 0..1 olarak çağrılır.
  static Future<File> download(
    UpdateInfo u,
    Directory dir,
    void Function(double progress) onProgress,
  ) async {
    final file = File('${dir.path}/stable_ai_update.apk');
    final sink = file.openWrite();

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(u.apkUrl));
      final resp = await client.send(req).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200 && resp.statusCode != 302) {
        throw HttpException('HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength ?? 0;
      var got = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress((got / total).clamp(0.0, 1.0));
      }
      await sink.flush();
    } finally {
      await sink.close();
      client.close();
    }
    onProgress(1);
    return file;
  }
}

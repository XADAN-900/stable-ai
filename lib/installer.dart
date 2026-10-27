import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Kurulum tarafı (Flutter/Android kanalları).
///
/// `MainActivity.kt` içindeki `stable_ai/install` kanalı, indirilen APK'yı
/// sistem kurulum ekranında açar; izin yoksa "Bu kaynaktan izin ver"
/// ekranına yönlendirir.
class Installer {
  static const MethodChannel _channel = MethodChannel('stable_ai/install');

  /// Kurulu uygulamanın sürümü (pubspec version).
  static Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  /// APK'nın ineceği dizin (uygulamaya özel, okunabilir).
  static Future<Directory> downloadDir() => getApplicationDocumentsDirectory();

  /// Sistem kurulum ekranını açar.
  /// Sonuç: `installer_launched` | `permission_required`.
  static Future<String?> install(String path) =>
      _channel.invokeMethod<String>('installApk', {'path': path});
}

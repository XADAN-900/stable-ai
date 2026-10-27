import 'dart:async';

import 'package:flutter/material.dart';

import 'installer.dart';
import 'strings.dart';
import 'update.dart';

/// APK indirme + sistem kurulumu akışı.
///
/// Ayarlar'daki "Sürümü kontrol et" ve açılıştaki otomatik güncelleme
/// teklifi bu tek akışı paylaşır.
Future<void> runUpdateFlow(
  BuildContext context,
  String lang,
  UpdateInfo upd,
) async {
  String t(String k) => L10n.t(lang, k);
  if (!context.mounted) return;

  var prog = 0.0;
  StateSetter setD = (_) {};
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        setD = set;
        return AlertDialog(
          title: Text(t('downloading')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: prog == 0 ? null : prog),
              const SizedBox(height: 14),
              Text('${(prog * 100).round()}%'),
            ],
          ),
        );
      },
    ),
  ));

  String? path;
  Object? err;
  try {
    final dir = await Installer.downloadDir();
    final f = await AppUpdater.download(upd, dir, (p) {
      prog = p;
      setD(() {});
    });
    path = f.path;
  } catch (e) {
    err = e;
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // indirme penceresi

  if (path == null) {
    _snack(context, '${t('updateErr')}${err == null ? '' : ': $err'}');
    return;
  }

  final r = await Installer.install(path);
  if (!context.mounted) return;
  if (r == 'permission_required') {
    _snack(context, t('permHint'));
  } else {
    _snack(context, t('installHint'));
  }
}

void _snack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Yeni sürüm varsa kullanıcıya sorar; kabul ederse indirme/kurma akışı açılır.
Future<void> offerUpdate(
  BuildContext context,
  String lang,
  UpdateInfo upd,
) async {
  String t(String k) => L10n.t(lang, k);
  if (!context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(t('updateFound')),
      content: Text('${t('updateTo')} ${upd.version}'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false), child: Text(t('later'))),
        FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t('installBtn'))),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await runUpdateFlow(context, lang, upd);
  }
}

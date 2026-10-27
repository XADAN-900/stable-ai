import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stable_ai/bot.dart';
import 'package:stable_ai/net.dart';
import 'package:stable_ai/update.dart';

/// Saf Dart testleri: Flutter binding'i başlatılmaz, bu yüzden gerçek
/// ağ isteği yapılabilir (TestWidgetsFlutterBinding HttpClient'i 400'e çeker).
void main() {
  group('AppUpdater', () {
    test('depo formatı doğrulanır', () {
      expect(AppUpdater.validRepo('kullanici/depo'), isTrue);
      expect(AppUpdater.validRepo('yanlis'), isFalse);
      expect(AppUpdater.validRepo(''), isFalse);
      expect(AppUpdater.validRepo('a/b/c'), isFalse);
    });

    test('sürüm karşılaştırması sayısal yapılır', () {
      expect(AppUpdater.newer('v1.0.1', '1.0.0'), isTrue);
      expect(AppUpdater.newer('v1.10.0', '1.9.9'), isTrue);
      expect(AppUpdater.newer('2.0.0', '1.99.99'), isTrue);
      expect(AppUpdater.newer('1.0.0', '1.0.0'), isFalse);
      expect(AppUpdater.newer('0.118.3', '1.0.0'), isFalse);
    });

    test('gerçek GitHub Releases kontrolü yeni sürümü bulur', () async {
      final u =
          await AppUpdater.check('streetcomplete/StreetComplete', '1.0.0');
      expect(u, isNotNull, reason: 'v64.0 etiketi 1.0.0\'dan yeni olmalı');
      expect(u!.version, '64.0');
      expect(u.apkUrl, endsWith('.apk'));
      expect(u.apkUrl, contains('github.com'));
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('kurulu sürüm yeniyse null döner', () async {
      final u =
          await AppUpdater.check('streetcomplete/StreetComplete', '99.0.0');
      expect(u, isNull);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('yayınlanmamış depo null döner', () async {
      expect(await AppUpdater.check('kullanici/depo', '1.0.0'), isNull);
    });

    test('geçersiz depo null döner ve ağ isteği yapmaz', () async {
      expect(await AppUpdater.check('yanlis', '1.0.0'), isNull);
    });

    test('internet yoklaması bağlıyken true döner', () async {
      expect(await Net.isOnline(), isTrue);
    });
  });

  group('Bilgi tabanı (çevrimdışı güncellenmiş hali)', () {
    test('stable_ai_kb.json uygulanır ve cevap üretir', () {
      final data = jsonDecode(File('stable_ai_kb.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(Bot.applyKnowledge(data), isTrue);

      final tr = Bot.reply('güncelleme nasıl yapılır', 'tr', null).text;
      expect(tr, contains('Güncelleme'));

      final en = Bot.reply('how do updates work', 'en', null).text;
      expect(en, contains('Updates'));
    });

    test('boş/geçersiz veri reddedilir', () {
      expect(Bot.applyKnowledge({'tr': <dynamic>[]}), isFalse);
      expect(
          Bot.applyKnowledge({
            'tr': [
              {'keys': <dynamic>[]}
            ]
          }),
          isFalse);
      expect(Bot.applyKnowledge(<String, dynamic>{}), isFalse);
    });

    test('yerel bilgi tabanı çalışmaya devam eder', () {
      final r = Bot.reply('merhaba', 'tr', null).text;
      expect(r, anyOf(contains('Merhaba'), contains('Selam'), contains('Hey')));
    });

    test('çok kelimeli anahtarlar sıralamadan bağımsız eşleşir', () {
      final r = Bot.reply('hava durumu nasıl', 'tr', null).text;
      expect(r, contains('Pencereden'));
    });

    test('kısmi eşleşmede konu netleştirilir', () {
      final r = Bot.reply('hava durumundan', 'tr', null).text;
      expect(r, anyOf(contains('hava durumu'), contains('hava durumundan')));
    });

    test('bağlam: önceki mesajla birleştirince cevap bulunur', () {
      final r =
          Bot.reply('başka', 'tr', null, recent: ['bir fıkra anlat']).text;
      expect(r, isNot(contains('tam anlayamadım')));
      expect(r.length, greaterThan(20));
    });

    test('yeni yetenekler: bilmece ve rastgele karar', () {
      final riddle = Bot.reply('bir bilmece sor', 'tr', null).text;
      expect(riddle, isNot(contains('tam anlayamadım')));
      final decide = Bot.reply('karar ver', 'tr', null).text;
      expect(decide, matches(RegExp(r'[1-6]')));
    });
  });
}

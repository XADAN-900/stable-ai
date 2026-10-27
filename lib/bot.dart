import 'dart:math';

class BotReply {
  final String text;
  final String? newName;
  const BotReply(this.text, [this.newName]);
}

class _I {
  final String id;
  final List<String>
      keys; // tek kelime = token eşleşme, boşluklu = ifade eşleşme
  final List<String> r; // cevaplar. {n} {name} {time} {date} {coin} {dice}
  const _I(this.id, this.keys, this.r);
}

class Bot {
  static final Random _rnd = Random();

  /// Depodan gelen çalışma zamanı bilgi girişleri (çevrimdışıyken de durur).
  static Map<String, List<_I>> _extra = {};

  /// Beklenen biçim: {"tr": [{"keys": [...], "answers": [...]}], "en": ...}
  static bool applyKnowledge(Map<String, dynamic> data) {
    final next = <String, List<_I>>{};
    data.forEach((lang, value) {
      if (value is! List) return;
      final items = <_I>[];
      for (final e in value) {
        if (e is! Map<String, dynamic>) continue;
        final keys = e['keys'];
        final answers = e['answers'];
        if (keys is! List || answers is! List) continue;
        final k =
            keys.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
        final a = answers
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList();
        if (k.isEmpty || a.isEmpty) continue;
        items.add(_I('kb_${lang}_${items.length}', k, a));
      }
      if (items.isNotEmpty) next[lang] = items;
    });
    if (next.isEmpty) return false;
    _extra = next;
    return true;
  }

  // ---------- Metin yardımcıları ----------
  static String lowerTr(String s) =>
      s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

  static String fold(String s) {
    const m = {
      'ı': 'i',
      'ş': 's',
      'ğ': 'g',
      'ü': 'u',
      'ö': 'o',
      'ç': 'c',
      'ä': 'a',
      'ß': 'ss',
      'â': 'a',
      'î': 'i',
      'û': 'u',
      'é': 'e',
      'è': 'e',
    };
    final b = StringBuffer();
    for (final ch in lowerTr(s).split('')) {
      b.write(m[ch] ?? ch);
    }
    return b.toString();
  }

  static int _lev(String a, String b) {
    if (a == b) return 0;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = min(min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  static String _cap(String s, String lang) {
    if (s.isEmpty) return s;
    final first = s[0];
    final up = (lang == 'tr' && first == 'i') ? 'İ' : first.toUpperCase();
    return up + s.substring(1);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static const _dTr = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar'
  ];
  static const _mTr = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık'
  ];
  static const _dEn = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  static const _mEn = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  static const _dDe = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag'
  ];
  static const _mDe = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember'
  ];

  static String _date(String lang, DateTime d) {
    switch (lang) {
      case 'tr':
        return '${d.day} ${_mTr[d.month - 1]} ${d.year}, ${_dTr[d.weekday - 1]}';
      case 'de':
        return '${_dDe[d.weekday - 1]}, ${d.day}. ${_mDe[d.month - 1]} ${d.year}';
      default:
        return '${_dEn[d.weekday - 1]}, ${_mEn[d.month - 1]} ${d.day}, ${d.year}';
    }
  }

  static String _fill(String t, String lang, String? name) {
    final now = DateTime.now();
    final coin = lang == 'tr'
        ? (_rnd.nextBool() ? 'Yazı' : 'Tura')
        : lang == 'de'
            ? (_rnd.nextBool() ? 'Kopf' : 'Zahl')
            : (_rnd.nextBool() ? 'Heads' : 'Tails');
    return t
        .replaceAll('{n}', name == null ? '' : ' $name')
        .replaceAll('{name}', name ?? '')
        .replaceAll('{time}', '${_two(now.hour)}:${_two(now.minute)}')
        .replaceAll('{date}', _date(lang, now))
        .replaceAll('{coin}', coin)
        .replaceAllMapped('{dice}', (_) => '${_rnd.nextInt(6) + 1}');
  }

  static String _pick(List<String> l) => l[_rnd.nextInt(l.length)];

  // ---------- Ana giriş ----------
  static BotReply reply(String input, String lang, String? name,
      {List<String> recent = const []}) {
    final f = fold(input);
    final words = f.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    final toks = words.isEmpty ? <String>[] : words.split(' ');

    // 1) "Adım ne?"
    if (RegExp(
            r'(adim|ismim) (ne|nedir)|what is my name|what s my name|whats my name|wie heisse ich|wie ist mein name')
        .hasMatch(words)) {
      final tmpl = name != null ? _askNameKnown[lang]! : _askNameUnknown[lang]!;
      return BotReply(_fill(tmpl, lang, name));
    }

    // 2) "Adım X"
    final lowered = lowerTr(input);
    final nm = RegExp(
      r'(?:^|\s)(?:adım|adim|ismim)\s+(?!ne\b|nedir\b)([\p{L}]+)|my name is\s+([\p{L}]+)|call me\s+([\p{L}]+)|ich hei(?:ß|ss)e\s+([\p{L}]+)|mein name ist\s+([\p{L}]+)',
      unicode: true,
    ).firstMatch(lowered);
    if (nm != null) {
      String? g;
      for (var i = 1; i <= 5; i++) {
        if (nm.group(i) != null) {
          g = nm.group(i);
          break;
        }
      }
      if (g != null && g.length >= 2) {
        final newName = _cap(g, lang);
        return BotReply(_fill(_pick(_nameSet[lang]!), lang, newName), newName);
      }
    }

    // 3) Hesap makinesi
    final math = _tryMath(f);
    if (math != null) return BotReply(math);
    final mathErr = _mathError(f);
    if (mathErr) return BotReply(_divZero[lang]!);

    // 4) Niyet eşleme (yerel bilgi tabanı + depodan güncellenenler)
    final kb = <_I>[...?(_kb[lang] ?? _kb['en']), ...?(_extra[lang])];
    _I? best;
    var bestScore = 0.0;
    for (final i in kb) {
      final s = _score(toks, words, i.keys);
      if (s > bestScore) {
        bestScore = s;
        best = i;
      }
    }
    if (best != null && bestScore >= 1.5) {
      return BotReply(_fill(_pick(best.r), lang, name));
    }

    // 4a) Tek başına bulunamadıysa son kullanıcı mesajıyla birleştirip tekrar
    //     dene ("başka", "daha detaylı" gibi devam soruları böyle cevaplanır).
    if (bestScore < 1.5 && recent.isNotEmpty) {
      final ctx = '$words ${fold(recent.last)}'.trim();
      final cToks = ctx.isEmpty ? <String>[] : ctx.split(' ');
      if (cToks.length > toks.length) {
        _I? cBest;
        var cScore = 0.0;
        for (final i in kb) {
          final s = _score(cToks, ctx, i.keys);
          if (s > cScore) {
            cScore = s;
            cBest = i;
          }
        }
        if (cBest != null && cScore >= 1.5) {
          return BotReply(_fill(_pick(cBest.r), lang, name));
        }
      }
    }

    // 4b) Kısmi eşleşme varsa hangi konuyu kastettiğini netleştir.
    if (best != null && bestScore > 0) {
      final topic = _topic(toks, words, best.keys);
      if (topic.isNotEmpty) {
        return BotReply(
            _fill(_clarify[lang]!.replaceAll('{topic}', topic), lang, name));
      }
    }
    return BotReply(_fill(_pick(_fallback[lang]!), lang, name));
  }

  /// Kısmi eşleşmede en çok eşleşen anahtarın okunabilir hâli.
  static String _topic(List<String> toks, String joined, List<String> keys) {
    final padded = ' $joined ';
    var bestK = '';
    var best = 0.0;
    for (final k0 in keys) {
      final k = fold(k0).trim();
      if (k.isEmpty) continue;
      var sc = 0.0;
      if (k.contains(' ')) {
        final parts = k.split(' ').where((w) => w.isNotEmpty).toList();
        if (parts.isEmpty) continue;
        final hit = parts.where((w) => padded.contains(' $w ')).length;
        sc = hit / parts.length;
      } else {
        for (final t in toks) {
          if (t == k || (k.length >= 4 && t.contains(k))) {
            sc = 1;
            break;
          }
        }
      }
      if (sc > best) {
        best = sc;
        bestK = k0;
      }
    }
    return bestK;
  }

  static double _score(List<String> toks, String joined, List<String> keys) {
    var s = 0.0;
    final padded = ' $joined ';
    for (final k0 in keys) {
      final k = fold(k0).trim();
      if (k.isEmpty) continue;
      if (k.contains(' ')) {
        final parts = k.split(' ').where((w) => w.isNotEmpty).toList();
        if (parts.isEmpty) continue;
        if (padded.contains(' $k ')) {
          s += 3.5; // tam ifade
          continue;
        }
        final hit = parts.where((w) => padded.contains(' $w ')).length;
        if (hit == parts.length) {
          s += 2.2; // tüm kelimeler var, sıralama farklı
        } else if (hit >= (parts.length + 1) ~/ 2) {
          s += 1.6; // kelimelerin çoğunluğu
        } else if (hit > 0) {
          s += 0.6; // kısmi ipucu (eşik altı, netleştirme için)
        }
        continue;
      }
      var done = false;
      for (final t in toks) {
        if (t == k) {
          s += 2;
          done = true;
          break;
        }
        if (k.length >= 4 &&
            t.length >= 4 &&
            (t.startsWith(k) || k.startsWith(t))) {
          s += 1.5;
          done = true;
          break;
        }
        if (k.length >= 5 &&
            t.length >= 5 &&
            (t.length - k.length).abs() <= 1 &&
            _lev(t, k) <= 1) {
          s += 1.5;
          done = true;
          break;
        }
        if (k.length >= 5 && t.length > k.length && t.contains(k)) {
          s += 1.2; // ekli hâl (ör. "hesapla" -> "hesap")
          done = true;
          break;
        }
      }
      if (!done) {
        for (final t in toks) {
          if (k.length >= 5 && t.length >= 5 && t.contains(k)) {
            s += 0.5; // zayıf ipucu
            break;
          }
        }
      }
    }
    return s;
  }

  // ---------- Hesap makinesi ----------
  static const _opWords = {
    'arti': '+',
    'plus': '+',
    'eksi': '-',
    'minus': '-',
    'carpi': '*',
    'times': '*',
    'mal': '*',
    'multiplied': '*',
    'bolu': '/',
    'divided': '/',
    'geteilt': '/',
  };

  static String? _prepMath(String f) {
    var s = f.split(RegExp(r'\s+')).map((w) => _opWords[w] ?? w).join(' ');
    s = s.replaceAllMapped(
        RegExp(r'(\d)\s*x\s*(\d)'), (m) => '${m[1]}*${m[2]}');
    s = s.replaceAll('×', '*').replaceAll('÷', '/');
    if (RegExp(r'[a-z]+').allMatches(s).length > 3) return null;
    s = s
        .replaceAll(RegExp(r'[^0-9+\-*/^().,\s]'), '')
        .replaceAll(',', '.')
        .trim();
    if (!RegExp(r'\d\s*[+\-*/^]\s*[\d(]|\)\s*[+\-*/^]|[+\-*/^]\s*\(')
        .hasMatch(s)) {
      return null;
    }
    return s;
  }

  static String? _tryMath(String f) {
    final s = _prepMath(f);
    if (s == null) return null;
    final v = _MathParser(s).parse();
    if (v == null || v.isNaN || v.isInfinite) return null;
    return '${s.replaceAll(RegExp(r'\s+'), '')} = ${_fmt(v)}';
  }

  static bool _mathError(String f) {
    final s = _prepMath(f);
    if (s == null) return false;
    final v = _MathParser(s).parse();
    return v != null && (v.isNaN || v.isInfinite);
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    var t = v.toStringAsFixed(6);
    t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return t;
  }

  // ---------- Sabit metinler ----------
  static const Map<String, String> _divZero = {
    'tr': 'Sıfıra bölemem 🙂',
    'en': "I can't divide by zero 🙂",
    'de': 'Durch null kann ich nicht teilen 🙂',
  };

  static const Map<String, String> _askNameKnown = {
    'tr': 'Adın {name}.',
    'en': 'Your name is {name}.',
    'de': 'Du heißt {name}.',
  };
  static const Map<String, String> _askNameUnknown = {
    'tr': "Henüz adını bilmiyorum. \"Adım Ali\" gibi söyleyebilirsin.",
    'en': 'I don\'t know your name yet. Tell me like "My name is Sam".',
    'de':
        'Ich kenne deinen Namen noch nicht. Sag zum Beispiel "Ich heiße Max".',
  };
  static const Map<String, List<String>> _nameSet = {
    'tr': ['Memnun oldum {name}! Adını hatırlayacağım.', 'Hoş geldin {name}!'],
    'en': [
      'Nice to meet you, {name}! I\'ll remember your name.',
      'Welcome, {name}!'
    ],
    'de': [
      'Freut mich, {name}! Ich merke mir deinen Namen.',
      'Willkommen, {name}!'
    ],
  };

  static const Map<String, List<String>> _fallback = {
    'tr': [
      'Bunu tam anlayamadım. Başka türlü sorabilir misin? "Yardım" yazarak neler yapabildiğimi görebilirsin.',
      'Hmm, bu konuda bilgim yok. Ama hesap yapabilirim, saat/tarih söyleyebilirim, fıkra anlatabilirim.',
      'Tam çözemedim{n}. Farklı kelimelerle tekrar dener misin?',
    ],
    'en': [
      "I didn't quite get that. Could you rephrase? Type \"help\" to see what I can do.",
      "Hmm, I don't know about that. But I can calculate, tell time/date, or tell a joke.",
      "Couldn't figure that out{n}. Try different words?",
    ],
    'de': [
      'Das habe ich nicht ganz verstanden. Kannst du es anders formulieren? Schreib "Hilfe" für meine Fähigkeiten.',
      'Hmm, dazu weiß ich nichts. Aber ich kann rechnen, Uhrzeit/Datum sagen oder einen Witz erzählen.',
      'Das habe ich nicht verstanden{n}. Versuch es mit anderen Worten?',
    ],
  };

  // ---------- Bilgi tabanı ----------
  /// Kısmi eşleşmede kullanılır: konuyu kullanıcıya geri sorar.
  static const Map<String, String> _clarify = {
    'tr':
        'Sanırım "{topic}" ile ilgili bir şey soruyorsun ama tam emin olamadım. Biraz daha açar mısın? Bu arada hesap yapabilir, saat/tarih söyleyebilir, fıkra ve bilmeci anlatabilir, yazı tura atabilirim.',
    'en':
        'I think you are asking about "{topic}", but I am not sure. Could you expand on it? Meanwhile I can calculate, tell the time/date, tell jokes and riddles, or flip a coin.',
    'de':
        'Ich glaube, du fragst nach "{topic}", aber ich bin mir nicht sicher. Kannst du es genauer sagen? Ich kann rechnen, Uhrzeit/Datum sagen, Witze und Rätsel erzählen oder eine Münze werfen.',
  };

  static const Map<String, List<_I>> _kb = {
    'tr': [
      _I('greet', [
        'merhaba',
        'selam',
        'selamlar',
        'slm',
        'sa',
        'mrb',
        'gunaydin',
        'iyi aksamlar',
        'iyi gunler',
        'hey'
      ], [
        'Merhaba{n}! Sana nasıl yardımcı olabilirim?',
        'Selam{n}! Nasılsın?',
        'Hey{n}! Hoş geldin 🙂',
      ]),
      _I('how', [
        'nasilsin',
        'naber',
        'ne haber',
        'nasil gidiyor',
        'iyi misin',
        'ne yapiyorsun'
      ], [
        'İyiyim, teşekkürler{n}! Sen nasılsın?',
        'Gayet iyi, internetsiz de olsam keyfim yerinde 😄',
      ]),
      _I('botname', [
        'adin ne',
        'ismin ne',
        'kimsin',
        'sen kimsin',
        'adin nedir',
        'ismin nedir'
      ], [
        'Ben Stable AI. Çevrimiçiysen gerçek bir yapay zekâyla, bağlantın yoksa cihazındaki yerel motorumla konuşurum.',
      ]),
      _I('thanks', [
        'tesekkur',
        'sagol',
        'saol',
        'eyvallah',
        'tesekkurler'
      ], [
        'Rica ederim{n}!',
        'Ne demek, her zaman 🙂',
      ]),
      _I('bye', [
        'gorusuruz',
        'hosca kal',
        'bye',
        'bb',
        'gule gule',
        'bay bay',
        'iyi geceler',
        'cikiyorum'
      ], [
        'Görüşürüz{n}! Kendine iyi bak 👋',
        'Hoşça kal{n}!',
      ]),
      _I('joke', [
        'fikra',
        'saka',
        'espri',
        'guldur',
        'komik',
        'eglendir'
      ], [
        'Temel neden kitap okumaz? Çünkü Dursun ona hep özet geçer!',
        'Doktor hastaya demiş ki: "Sigarayı bırakmalısın." Hasta: "Peki doktor bey, ya sigara beni bırakmazsa?"',
        'Bilgisayar neden üşümez? Çünkü Windows\'u hep açıktır!',
        'Programcı markete gitmiş. Eşi: "1 ekmek al, yumurta varsa 6 tane al." Adam 6 ekmekle dönmüş: "Yumurta vardı."',
      ]),
      _I('help', [
        'yardim',
        'ne yapabilirsin',
        'neler yapabilirsin',
        'komutlar',
        'ozellikler',
        'help',
        'menu'
      ], [
        'Şunları yapabilirim:\n• Gerçek yapay zekâ ile sohbet (çevrimiçi)\n• Hesap: "12*7+5", "15 artı 3"\n• Saat ve tarih\n• Fıkra, ilginç bilgi\n• Yazı tura, zar\n• Adını hatırlamak: "Adım Ali"',
      ]),
      _I('time', [
        'saat kac',
        'saati soyle',
        'saat',
        'kac saat'
      ], [
        'Saat şu an {time}.',
      ]),
      _I('date', [
        'bugun gunlerden ne',
        'tarih',
        'bugunun tarihi',
        'hangi gun',
        'bugun ayin kaci',
        'gun'
      ], [
        'Bugün {date}.',
      ]),
      _I('creator', [
        'kim yapti',
        'kim yazdi',
        'yapimci',
        'yaratici',
        'gelistirici',
        'seni kim'
      ], [
        'Beni açık kaynaklı bir proje olarak geliştirdiler. Kodumu istediğin gibi değiştirebilirsin!',
      ]),
      _I('offline', [
        'internet',
        'cevrimdisi',
        'offline',
        'baglanti',
        'wifi'
      ], [
        'Bağlantın olmasa da çalışırım: gerçek model cevap veremezse her şey cihazındaki yerel motordan gelir 🔒',
      ]),
      _I('weather', [
        'hava durumu',
        'hava nasil',
        'yagmur yagacak mi'
      ], [
        'Çevrimdışı olduğum için hava durumuna bakamam. Pencereden bakmak en güvenilir yöntem 😄',
      ]),
      _I('age', [
        'kac yasindasin',
        'yasin kac',
        'yasin'
      ], [
        'Yaşım yok, ben bir yazılımım — ama her açılışta tazeyim!',
      ]),
      _I('love', [
        'seni seviyorum',
        'askim',
        'canim'
      ], [
        'Çok tatlısın{n}! Ben de seni severim, bir bot olarak elimden geldiği kadar 💜',
      ]),
      _I('praise', [
        'harikasin',
        'aferin',
        'super',
        'mukemmel',
        'bravo',
        'cok iyi'
      ], [
        'Teşekkürler{n}, çok naziksin! 😊',
      ]),
      _I('sad', [
        'uzgunum',
        'moralim bozuk',
        'canim sikkin',
        'mutsuzum',
        'keyfim yok'
      ], [
        'Üzüldüm{n}. İstersen biraz sohbet edelim, belki iyi gelir. Ya da bir fıkra?',
      ]),
      _I('fact', [
        'ilginc bilgi',
        'bilgi ver',
        'bana bilgi',
        'bir bilgi soyle'
      ], [
        'Ahtapotların üç kalbi vardır.',
        'Bal, doğru saklanırsa asla bozulmaz.',
        'Muz botanik olarak bir meyvedir, hatta "beri" (yumuşak meyve) sınıfındadır; çilek ise değildir.',
        'Işık Güneş\'ten Dünya\'ya yaklaşık 8 dakikada ulaşır.',
      ]),
      _I('coin', ['yazi tura', 'yazitura', 'para at'], ['Attım: {coin}!']),
      _I('dice', ['zar at', 'zar', 'zar sal'], ['Zar: {dice} 🎲']),
      _I('riddle', [
        'bilmece',
        'bilmeceler',
        'bilmece sor',
        'zor soru'
      ], [
        'Bir şey var: sırtı ev, gövdesi baca. Ne dir? — Ocak.',
        'Hangisi önce gelir, tavşan mı yumurta mı? — tavşan, çünkü ben uydurdum 🙂',
        'İpi olan, düdüğü olmayan, kutusu olan ama kapağı olmayan nedir? — Kibrit.',
        'Denize düşenin neyi ıslanır? — Gölgesi bile değil, kendisi! Peki ya ilk ne düşer? — Toz.',
      ]),
      _I('decide', [
        'karar ver',
        'hangisini seceyim',
        'ne yapayim',
        'sayi tut',
        'rastgele sayi',
        'tahmin et'
      ], [
        'Rastgele seçim: {dice}. Bununla başla, gerisi gelir.',
        'Ata ferman: {dice} — tek sayı gider, çift sayı bekle 🙂',
        'Gözleri kapat ve {dice} say; o kadar sürede aklına ilk gelen seçenek belirir.',
      ]),
      _I('opensource', [
        'acik kaynak',
        'lisans',
        'kaynak kod'
      ], [
        'Açık kaynak (MIT lisansı). Kodu GitHub\'dan alıp istediğin gibi geliştirebilirsin.',
      ]),
    ],
    'en': [
      _I('greet', [
        'hello',
        'hi',
        'hey',
        'hiya',
        'good morning',
        'good evening',
        'greetings',
        'yo'
      ], [
        'Hello{n}! How can I help you?',
        'Hi{n}! How are you?',
        'Hey{n}! Welcome 🙂',
      ]),
      _I('how', [
        'how are you',
        'whats up',
        'what s up',
        'how is it going',
        'how are things',
        'sup'
      ], [
        "I'm doing great, thanks{n}! And you?",
        'All good here, even without internet 😄',
      ]),
      _I('botname', [
        'your name',
        'who are you',
        'what are you called',
        'whats your name',
        'what s your name'
      ], [
        "I'm Stable AI. Online I talk to a real language model, offline I keep going with the engine on your device.",
      ]),
      _I('thanks', [
        'thanks',
        'thank you',
        'thx',
        'cheers'
      ], [
        "You're welcome{n}!",
        'Anytime 🙂',
      ]),
      _I('bye', [
        'bye',
        'goodbye',
        'see you',
        'good night',
        'cya',
        'later'
      ], [
        'See you{n}! Take care 👋',
        'Goodbye{n}!',
      ]),
      _I('joke', [
        'joke',
        'funny',
        'make me laugh',
        'humor',
        'entertain'
      ], [
        'Why do programmers prefer dark mode? Because light attracts bugs!',
        "I told my computer I needed a break. It said: \"No problem, I'll go to sleep.\"",
        "There are 10 kinds of people: those who understand binary and those who don't.",
        'Why was the math book sad? It had too many problems.',
      ]),
      _I('help', [
        'help',
        'what can you do',
        'commands',
        'features',
        'menu',
        'abilities'
      ], [
        'I can:\n• Chat with a real AI model (online)\n• Calculate: "12*7+5", "15 plus 3"\n• Tell time and date\n• Jokes and fun facts\n• Flip a coin, roll a die\n• Remember your name: "My name is Sam"',
      ]),
      _I('time', [
        'what time',
        'current time',
        'time now',
        'time',
        'clock'
      ], [
        "It's {time} right now.",
      ]),
      _I('date', [
        'todays date',
        'what day',
        'date',
        'today',
        'which day'
      ], [
        'Today is {date}.',
      ]),
      _I('creator', [
        'who made you',
        'who created you',
        'who built you',
        'developer',
        'creator',
        'author'
      ], [
        "I'm an open-source project. You can change my code however you like!",
      ]),
      _I('offline', [
        'internet',
        'offline',
        'online',
        'connection',
        'wifi'
      ], [
        "I still work without a connection: if the real model can't be reached, every reply comes from the engine on your device 🔒",
      ]),
      _I('weather', [
        'weather',
        'forecast',
        'rain',
        'temperature outside'
      ], [
        "I'm offline so I can't check the weather. Looking out the window is the most reliable method 😄",
      ]),
      _I('age', [
        'how old are you',
        'your age'
      ], [
        "I have no age, I'm software — but I'm fresh on every launch!",
      ]),
      _I('love', [
        'i love you',
        'love you'
      ], [
        "That's sweet{n}! I like you too, as much as a bot can 💜",
      ]),
      _I('praise', [
        'awesome',
        'great',
        'amazing',
        'well done',
        'brilliant',
        'excellent',
        'good bot'
      ], [
        'Thank you{n}, you are kind! 😊',
      ]),
      _I('sad', [
        'i am sad',
        'im sad',
        'feeling down',
        'unhappy',
        'depressed',
        'bad mood'
      ], [
        "I'm sorry to hear that{n}. We can chat for a bit if you like — or I can tell a joke?",
      ]),
      _I('fact', [
        'fun fact',
        'tell me a fact',
        'interesting fact',
        'random fact',
        'fact'
      ], [
        'Octopuses have three hearts.',
        'Honey never spoils if stored properly.',
        'Light takes about 8 minutes to travel from the Sun to Earth.',
        'Bananas are berries, but strawberries are not.',
      ]),
      _I(
          'coin',
          ['flip a coin', 'coin flip', 'toss a coin', 'heads or tails', 'coin'],
          ['I flipped: {coin}!']),
      _I('dice', ['roll a die', 'roll dice', 'roll a dice', 'dice', 'die'],
          ['Rolled: {dice} 🎲']),
      _I('riddle', [
        'riddle',
        'tell me a riddle',
        'puzzle',
        'brain teaser'
      ], [
        'What has a back but no body? — A coin.',
        'What gets wetter the more it dries? — A towel.',
        'What has keys but no locks? — A keyboard.',
        'I speak without a mouth and hear without ears. What am I? — An echo.',
      ]),
      _I('decide', [
        'make a decision',
        'which one should i pick',
        'what should i do',
        'pick a number',
        'random number',
        'guess a number'
      ], [
        'My random pick: {dice}. Start there and adjust as you go.',
        'Toss-up: {dice} — odd says go, even says wait.',
        'Close your eyes and count to {dice}; by then the option you want will surface.',
      ]),
      _I('opensource', [
        'open source',
        'license',
        'source code'
      ], [
        'Open source (MIT license). Grab the code from GitHub and make it your own.',
      ]),
    ],
    'de': [
      _I('greet', [
        'hallo',
        'hi',
        'hey',
        'moin',
        'servus',
        'guten morgen',
        'guten tag',
        'guten abend',
        'grus gott'
      ], [
        'Hallo{n}! Wie kann ich dir helfen?',
        'Hi{n}! Wie geht\'s?',
        'Hey{n}! Willkommen 🙂',
      ]),
      _I('how', [
        'wie geht es dir',
        'wie gehts',
        'wie geht s',
        'was geht',
        'alles gut'
      ], [
        'Mir geht\'s super, danke{n}! Und dir?',
        'Alles gut, auch ohne Internet 😄',
      ]),
      _I('botname', [
        'wie heisst du',
        'wer bist du',
        'dein name'
      ], [
        'Ich bin Stable AI. Online chatte ich mit einem echten Sprachmodell, offline läuft die Engine auf deinem Gerät weiter.',
      ]),
      _I('thanks', [
        'danke',
        'dankeschon',
        'vielen dank',
        'merci'
      ], [
        'Gern geschehen{n}!',
        'Jederzeit 🙂',
      ]),
      _I('bye', [
        'tschuss',
        'tschau',
        'auf wiedersehen',
        'bis spater',
        'gute nacht',
        'bis bald'
      ], [
        'Bis bald{n}! Pass auf dich auf 👋',
        'Tschüss{n}!',
      ]),
      _I('joke', [
        'witz',
        'lustig',
        'bring mich zum lachen',
        'spass',
        'unterhalte mich'
      ], [
        'Warum können Geister so schlecht lügen? Weil man durch sie hindurchsieht!',
        'Was sagt ein Null zum anderen Null? Ohne dich wäre ich nichts!',
        'Warum nehmen Programmierer immer eine Leiter mit? Damit sie auf höhere Ebenen kommen!',
        'Kommt ein Pferd in die Bar. Fragt der Barkeeper: "Warum so ein langes Gesicht?"',
      ]),
      _I('help', [
        'hilfe',
        'was kannst du',
        'befehle',
        'funktionen',
        'menu',
        'help'
      ], [
        'Ich kann:\n• Mit einem echten KI-Modell chatten (online)\n• Rechnen: "12*7+5", "15 plus 3"\n• Uhrzeit und Datum\n• Witze und Wissenswertes\n• Münze werfen, würfeln\n• Deinen Namen merken: "Ich heiße Max"',
      ]),
      _I('time', [
        'wie spat',
        'uhrzeit',
        'wieviel uhr',
        'wie viel uhr',
        'uhr'
      ], [
        'Es ist jetzt {time} Uhr.',
      ]),
      _I('date', [
        'welcher tag',
        'datum',
        'heute',
        'welches datum',
        'welchen tag haben wir'
      ], [
        'Heute ist {date}.',
      ]),
      _I('creator', [
        'wer hat dich gemacht',
        'wer hat dich erstellt',
        'entwickler',
        'ersteller',
        'autor'
      ], [
        'Ich bin ein Open-Source-Projekt. Du kannst meinen Code beliebig ändern!',
      ]),
      _I('offline', [
        'internet',
        'offline',
        'verbindung',
        'wlan',
        'wifi'
      ], [
        'Auch ohne Verbindung funktioniere ich: Ist das echte Modell nicht erreichbar, kommen alle Antworten von der Engine auf deinem Gerät 🔒',
      ]),
      _I('weather', [
        'wetter',
        'vorhersage',
        'regnet es'
      ], [
        'Ich bin offline und kann das Wetter nicht abrufen. Ein Blick aus dem Fenster hilft am besten 😄',
      ]),
      _I('age', [
        'wie alt bist du',
        'dein alter'
      ], [
        'Ich habe kein Alter, ich bin Software — aber bei jedem Start frisch!',
      ]),
      _I('love', [
        'ich liebe dich',
        'hab dich lieb'
      ], [
        'Wie süß{n}! Ich mag dich auch, so gut ein Bot das kann 💜',
      ]),
      _I('praise', [
        'toll',
        'super',
        'klasse',
        'wunderbar',
        'bravo',
        'prima',
        'gut gemacht'
      ], [
        'Danke{n}, das ist nett von dir! 😊',
      ]),
      _I('sad', [
        'ich bin traurig',
        'traurig',
        'schlecht drauf',
        'niedergeschlagen',
        'schlechte laune'
      ], [
        'Das tut mir leid{n}. Wir können ein bisschen plaudern — oder soll ich einen Witz erzählen?',
      ]),
      _I('fact', [
        'wissenswertes',
        'fun fact',
        'interessante tatsache',
        'erzahl mir etwas',
        'tatsache'
      ], [
        'Kraken haben drei Herzen.',
        'Honig verdirbt bei richtiger Lagerung nie.',
        'Licht braucht etwa 8 Minuten von der Sonne zur Erde.',
        'Bananen sind botanisch Beeren, Erdbeeren nicht.',
      ]),
      _I(
          'coin',
          ['munzwurf', 'munze werfen', 'kopf oder zahl', 'wirf eine munze'],
          ['Geworfen: {coin}!']),
      _I('dice', ['wurfeln', 'wurfel', 'wirf einen wurfel'],
          ['Gewürfelt: {dice} 🎲']),
      _I('riddle', [
        'raetsel',
        'rutsche ein raetsel',
        'knobelaufgabe',
        'denksport'
      ], [
        'Was hat eine Rückseite, aber keinen Körper? — Eine Münze.',
        'Was wird je feuchter, je trockener es wird? — Ein Handtuch.',
        'Was hat Tasten, aber kein Schloss? — Eine Tastatur.',
        'Ich habe einen Mund und höre ohne Ohren. Wer bin ich? — Ein Echo.',
      ]),
      _I('decide', [
        'entscheide',
        'was soll ich waehlen',
        'was soll ich tun',
        'sag eine zahl',
        'zufallszahl',
        'rate eine zahl'
      ], [
        'Zufallsentscheid: {dice}. Fang damit an.',
        'Münzwurf im Kopf: {dice} — ungerade heißt los, gerade heißt warten.',
        'Schliess die Augen und zaehle bis {dice}; bis dahin meldet sich die richtige Option.',
      ]),
      _I('opensource', [
        'open source',
        'lizenz',
        'quellcode'
      ], [
        'Open Source (MIT-Lizenz). Hol dir den Code von GitHub und passe ihn an.',
      ]),
    ],
  };
}

// ---------- Basit ifade ayrıştırıcı ----------
class _MathParser {
  final String s;
  int i = 0;
  _MathParser(this.s);

  double? parse() {
    try {
      final v = _expr();
      _ws();
      if (i != s.length) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  void _ws() {
    while (i < s.length && s[i] == ' ') {
      i++;
    }
  }

  double _expr() {
    var v = _term();
    while (true) {
      _ws();
      if (i < s.length && (s[i] == '+' || s[i] == '-')) {
        final o = s[i++];
        final r = _term();
        v = o == '+' ? v + r : v - r;
      } else {
        break;
      }
    }
    return v;
  }

  double _term() {
    var v = _pow();
    while (true) {
      _ws();
      if (i < s.length && (s[i] == '*' || s[i] == '/')) {
        final o = s[i++];
        final r = _pow();
        v = o == '*' ? v * r : v / r;
      } else {
        break;
      }
    }
    return v;
  }

  double _pow() {
    final b = _unary();
    _ws();
    if (i < s.length && s[i] == '^') {
      i++;
      final e = _pow();
      return pow(b, e).toDouble();
    }
    return b;
  }

  double _unary() {
    _ws();
    if (i < s.length && s[i] == '-') {
      i++;
      return -_unary();
    }
    if (i < s.length && s[i] == '+') {
      i++;
      return _unary();
    }
    return _atom();
  }

  double _atom() {
    _ws();
    if (i < s.length && s[i] == '(') {
      i++;
      final v = _expr();
      _ws();
      if (i >= s.length || s[i] != ')') throw const FormatException();
      i++;
      return v;
    }
    final st = i;
    while (i < s.length &&
        (s.codeUnitAt(i) >= 48 && s.codeUnitAt(i) <= 57 || s[i] == '.')) {
      i++;
    }
    if (st == i) throw const FormatException();
    return double.parse(s.substring(st, i));
  }
}

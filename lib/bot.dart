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

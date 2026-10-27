import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai.dart';
import 'bot.dart';
import 'installer.dart';
import 'knowledge.dart';
import 'net.dart';
import 'strings.dart';
import 'update.dart';
import 'update_flow.dart';

// ---------------------------------------------------------------- State
class Msg {
  final bool user;
  final String text;
  final int ts;
  Msg(this.user, this.text, this.ts);
  Map<String, dynamic> toJson() => {'u': user, 't': text, 's': ts};
  factory Msg.fromJson(Map<String, dynamic> j) =>
      Msg(j['u'] as bool, j['t'] as String, j['s'] as int);
}

class AppState extends ChangeNotifier {
  SharedPreferences? _p;
  String lang = 'tr';
  int themeMode = 0; // 0 sistem, 1 açık, 2 koyu
  double fontScale = 1.0;
  bool saveHistory = true;
  bool useAi = true; // gerçek LLM (çevrimiçi) kullanılsın mı
  bool aiOffline = false; // son LLM çağrısı başarısız oldu mu
  String repo = ''; // GitHub deposu (owner/repo): güncelleme kaynağı
  String? userName;
  List<Msg> messages = [];

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final sys = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    lang = _p!.getString('lang') ?? (L10n.langs.containsKey(sys) ? sys : 'en');
    themeMode = _p!.getInt('theme') ?? 0;
    fontScale = _p!.getDouble('font') ?? 1.0;
    saveHistory = _p!.getBool('saveHistory') ?? true;
    useAi = _p!.getBool('useAi') ?? true;
    repo = _p!.getString('repo') ?? '';
    userName = _p!.getString('userName');
    final raw = _p!.getString('history');
    if (raw != null && saveHistory) {
      try {
        final l = jsonDecode(raw) as List;
        messages =
            l.map((e) => Msg.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    notifyListeners();
  }

  void setLang(String v) {
    lang = v;
    _p?.setString('lang', v);
    notifyListeners();
  }

  void setTheme(int v) {
    themeMode = v;
    _p?.setInt('theme', v);
    notifyListeners();
  }

  void setFont(double v) {
    fontScale = v;
    _p?.setDouble('font', v);
    notifyListeners();
  }

  void setSaveHistory(bool v) {
    saveHistory = v;
    _p?.setBool('saveHistory', v);
    _persist();
    notifyListeners();
  }

  void setUseAi(bool v) {
    useAi = v;
    aiOffline = false;
    _p?.setBool('useAi', v);
    notifyListeners();
  }

  void setAiOffline(bool v) {
    if (aiOffline == v) return;
    aiOffline = v;
    notifyListeners();
  }

  void setRepo(String v) {
    final r = v.trim();
    if (r == repo) return;
    repo = r;
    _p?.setString('repo', r);
  }

  void setUserName(String? v) {
    userName = (v == null || v.trim().isEmpty) ? null : v.trim();
    if (userName == null) {
      _p?.remove('userName');
    } else {
      _p?.setString('userName', userName!);
    }
    notifyListeners();
  }

  void addMessage(Msg m) {
    messages.add(m);
    if (messages.length > 300) messages.removeRange(0, messages.length - 300);
    _persist();
    notifyListeners();
  }

  void clearMessages() {
    messages = [];
    _persist();
    notifyListeners();
  }

  void _persist() {
    if (saveHistory) {
      _p?.setString(
          'history', jsonEncode(messages.map((m) => m.toJson()).toList()));
    } else {
      _p?.remove('history');
    }
  }
}

// ---------------------------------------------------------------- App
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final st = AppState();
  await st.load();
  // İnternetsizken bile son güncellenmiş bilgi tabanını aç.
  await Knowledge.loadCached();
  runApp(App(st));
  // İnternet varsa bilgi tabanını depodan tazele ve bağlantıyı yokla.
  unawaited(Knowledge.sync(AppUpdater.repoFor(st.repo)));
  unawaited(Net.warmUp());
}

ThemeData _theme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7), brightness: b),
    );

/// Uygulama boyunca kullanılan yumuşak geçiş: belirme + sağdan kayma + ölçek.
Route<T> fadeSlide<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.06, 0), end: Offset.zero)
              .animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class App extends StatelessWidget {
  final AppState st;
  const App(this.st, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Stable AI',
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: const [
          ThemeMode.system,
          ThemeMode.light,
          ThemeMode.dark
        ][st.themeMode],
        builder: (ctx, child) {
          final mq = MediaQuery.of(ctx);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(st.fontScale)),
            child: child!,
          );
        },
        home: HomePage(st),
      ),
    );
  }
}

// ---------------------------------------------------------------- Home
class HomePage extends StatefulWidget {
  final AppState st;
  const HomePage(this.st, {super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  /// Açılışta öğelerin sırayla belirmesi için tek kontrolcü.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  AppState get st => widget.st;

  @override
  void initState() {
    super.initState();
    // İnternet varsa açılışta sessizce yeni sürümü sor (bir kez).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_offerUpdate()));
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  /// Yeni sürüm varsa kullanıcıya bir kez sorar.
  Future<void> _offerUpdate() async {
    if (!await Net.isOnline()) return;
    final repo = AppUpdater.repoFor(st.repo);
    if (!AppUpdater.validRepo(repo)) return;
    UpdateInfo? upd;
    try {
      final cur = await Installer.currentVersion();
      upd = await AppUpdater.check(repo, cur);
    } catch (_) {
      return;
    }
    if (upd == null || !mounted) return;
    final p = await SharedPreferences.getInstance();
    if (p.getString('offered') == upd.version) return;
    await p.setString('offered', upd.version);
    if (!mounted) return;
    await offerUpdate(context, st.lang, upd);
  }

  /// Gecikmeli açılış animasyonu: aşağıdan yukarı belirme.
  Widget _rise(int i, Widget child) {
    final a = CurvedAnimation(
      parent: _enter,
      curve: Interval((i * 0.075).clamp(0.0, 0.65), 1.0,
          curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position:
            Tween(begin: const Offset(0, 0.22), end: Offset.zero).animate(a),
        child: child,
      ),
    );
  }

  Widget _btn(BuildContext c, IconData icon, String label, VoidCallback onTap,
      {bool primary = false}) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(label, style: const TextStyle(fontSize: 17)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: primary
            ? FilledButton.icon(
                onPressed: onTap, icon: Icon(icon), label: child)
            : FilledButton.tonalIcon(
                onPressed: onTap, icon: Icon(icon), label: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String t(String k) => L10n.t(st.lang, k);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.primaryContainer, cs.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _rise(
                      0,
                      _Pulse(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: cs.primary.withValues(alpha: 0.35),
                                  blurRadius: 45,
                                  spreadRadius: 6),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 52,
                            backgroundColor: cs.primary,
                            child: Icon(Icons.auto_awesome_rounded,
                                size: 56, color: cs.onPrimary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _rise(
                      1,
                      Text(t('appName'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 4),
                    _rise(
                        2,
                        Text(t('subtitle'),
                            style: Theme.of(context).textTheme.bodyLarge)),
                    const SizedBox(height: 12),
                    _rise(
                      3,
                      Chip(
                        avatar: Icon(
                          st.useAi
                              ? Icons.auto_awesome_rounded
                              : Icons.wifi_off_rounded,
                          size: 18,
                        ),
                        label: Text(t('offlineBadge')),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _rise(
                      4,
                      _btn(context, Icons.chat_bubble_rounded, t('startChat'),
                          () {
                        Navigator.push(context, fadeSlide(ChatPage(st)));
                      }, primary: true),
                    ),
                    _rise(
                      5,
                      _btn(context, Icons.settings_rounded, t('settings'), () {
                        Navigator.push(context, fadeSlide(SettingsPage(st)));
                      }),
                    ),
                    _rise(
                      6,
                      _btn(context, Icons.info_outline_rounded, t('about'), () {
                        Navigator.push(context, fadeSlide(AboutPage(st)));
                      }),
                    ),
                    _rise(
                        7,
                        _btn(context, Icons.exit_to_app_rounded, t('exit'),
                            () => SystemNavigator.pop())),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Yavaşça nefes alan vurgu.
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
    return ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 1.05).animate(a),
        child: widget.child);
  }
}

/// "Yazıyor..." göstergesinin zıplayan noktaları.
class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots(this.color);

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  static final Animatable<double> _hop = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.0, end: -8.0)
          .chain(CurveTween(curve: Curves.easeOutQuad)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween(begin: -8.0, end: 0.0)
          .chain(CurveTween(curve: Curves.easeInQuad)),
      weight: 50,
    ),
  ]);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _dot(int i) {
    final a = CurvedAnimation(
      parent: _c,
      curve: Interval(i * 0.2, i * 0.2 + 0.5, curve: Curves.linear),
    );
    return AnimatedBuilder(
      animation: a,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _hop.evaluate(a)),
        child: child,
      ),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _dot(i)),
      ],
    );
  }
}

// ---------------------------------------------------------------- Chat
class ChatPage extends StatefulWidget {
  final AppState st;
  const ChatPage(this.st, {super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _ctrl = TextEditingController();
  final _sc = ScrollController();
  final _rnd = Random();
  bool _busy = false;

  AppState get st => widget.st;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (st.messages.isEmpty) {
        st.addMessage(Msg(false, L10n.t(st.lang, 'welcome'),
            DateTime.now().millisecondsSinceEpoch));
      }
      _scroll(jump: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _sc.dispose();
    super.dispose();
  }

  void _scroll({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sc.hasClients) return;
      final max = _sc.position.maxScrollExtent;
      if (jump) {
        _sc.jumpTo(max);
      } else {
        _sc.animateTo(max,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    _ctrl.clear();
    st.addMessage(Msg(true, text, DateTime.now().millisecondsSinceEpoch));
    setState(() => _busy = true);
    _scroll();

    String reply;
    String? newName;
    String? aiReply;

    // 1) İnternet var mı? Yoksa beklemeden yerel motor.
    // 2) İnternet varsa gerçek LLM (ücretsiz, anahtarsız); cevap gelmezse
    //    cihazdaki son güncellenmiş motor devreye girer.
    if (st.useAi && await Net.isOnline()) {
      final history = <Map<String, String>>[
        for (final m in st.messages)
          {'role': m.user ? 'user' : 'assistant', 'content': m.text},
      ];
      aiReply = await Ai.chat(lang: st.lang, history: history);
    }
    st.setAiOffline(st.useAi && aiReply == null);

    // 3) Çevrimdışı / hata: cihazda çalışan kural tabanlı motor (bağlamla).
    if (aiReply != null) {
      reply = aiReply;
    } else {
      await Future.delayed(Duration(milliseconds: 350 + _rnd.nextInt(550)));
      if (!mounted) return;
      final userTexts = [
        for (final m in st.messages)
          if (m.user) m.text
      ];
      final recent = userTexts.length > 1
          ? userTexts.sublist(0, userTexts.length - 1)
          : <String>[];
      final r = Bot.reply(text, st.lang, st.userName, recent: recent);
      reply = r.text;
      newName = r.newName;
    }

    if (!mounted) return;
    if (newName != null) st.setUserName(newName);
    st.addMessage(Msg(false, reply, DateTime.now().millisecondsSinceEpoch));
    setState(() => _busy = false);
    _scroll();
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L10n.t(st.lang, 'clearTitle')),
        content: Text(L10n.t(st.lang, 'clearConfirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(L10n.t(st.lang, 'cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(L10n.t(st.lang, 'yes'))),
        ],
      ),
    );
    if (ok == true) {
      st.clearMessages();
      st.addMessage(Msg(false, L10n.t(st.lang, 'welcome'),
          DateTime.now().millisecondsSinceEpoch));
    }
  }

  String _hhmm(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// Mesaj balonlarının belirme + yukarı kayma animasyonu.
  Widget _enterAnim(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: c),
      ),
      child: child,
    );
  }

  Widget _bubble(BuildContext context, Msg m) {
    final cs = Theme.of(context).colorScheme;
    final me = m.user;
    return _enterAnim(
      Align(
        alignment: me ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: me ? cs.primary : cs.secondaryContainer,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(me ? 18 : 4),
              bottomRight: Radius.circular(me ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                m.text,
                style: TextStyle(
                    color: me ? cs.onPrimary : cs.onSecondaryContainer,
                    fontSize: 16),
              ),
              const SizedBox(height: 2),
              Text(
                _hhmm(m.ts),
                style: TextStyle(
                  fontSize: 10,
                  color: (me ? cs.onPrimary : cs.onSecondaryContainer)
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final msgs = st.messages;
        return Scaffold(
          appBar: AppBar(
            title: Text(L10n.t(st.lang, 'chat')),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      st.useAi && !st.aiOffline
                          ? Icons.auto_awesome_rounded
                          : Icons.wifi_off_rounded,
                      size: 16,
                    ),
                    label: Text(
                      st.useAi && !st.aiOffline
                          ? L10n.t(st.lang, 'aiChipOn')
                          : L10n.t(st.lang, 'aiChipOff'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: L10n.t(st.lang, 'clearChat'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _confirmClear,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _sc,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: msgs.length + (_busy ? 1 : 0),
                  itemBuilder: (c, i) {
                    if (i == msgs.length) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: _TypingDots(cs.onSecondaryContainer),
                        ),
                      );
                    }
                    return _bubble(c, msgs[i]);
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _send,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: L10n.t(st.lang, 'inputHint'),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        onPressed: _busy ? null : () => _send(_ctrl.text),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Settings
class SettingsPage extends StatefulWidget {
  final AppState st;
  const SettingsPage(this.st, {super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _name;
  late final TextEditingController _repo;
  AppState get st => widget.st;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: st.userName ?? '');
    _repo = TextEditingController(text: st.repo);
  }

  @override
  void dispose() {
    _name.dispose();
    _repo.dispose();
    super.dispose();
  }

  Widget _header(BuildContext c, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(c).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      );

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Sürümü depodan kontrol eder, varsa indirme/kurma akışını başlatır.
  Future<void> _checkUpdate() async {
    String t(String k) => L10n.t(st.lang, k);
    st.setRepo(_repo.text);
    final repo = AppUpdater.repoFor(st.repo);
    if (!AppUpdater.validRepo(repo)) {
      _snack(t('updateRepoErr'));
      return;
    }
    _snack(t('checking'));
    UpdateInfo? found;
    try {
      final current = await Installer.currentVersion();
      found = await AppUpdater.check(repo, current);
    } catch (_) {
      found = null;
    }
    if (!mounted) return;
    final upd = found;
    if (upd == null) {
      _snack(t('upToDate'));
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('updateFound')),
        content: Text('${t('updateTo')} ${upd.version}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('installBtn'))),
        ],
      ),
    );
    if (go == true && mounted) {
      await runUpdateFlow(context, st.lang, upd);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) {
        String t(String k) => L10n.t(st.lang, k);
        return Scaffold(
          appBar: AppBar(title: Text(t('settings'))),
          body: ListView(
            children: [
              _header(context, t('language')),
              for (final e in L10n.langs.entries)
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: Text(e.value),
                  trailing: st.lang == e.key
                      ? const Icon(Icons.check_circle_rounded)
                      : null,
                  onTap: () => st.setLang(e.key),
                ),
              _header(context, t('appearance')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                        value: 0,
                        label: Text(t('themeSystem')),
                        icon: const Icon(Icons.brightness_auto_rounded)),
                    ButtonSegment(
                        value: 1,
                        label: Text(t('themeLight')),
                        icon: const Icon(Icons.light_mode_rounded)),
                    ButtonSegment(
                        value: 2,
                        label: Text(t('themeDark')),
                        icon: const Icon(Icons.dark_mode_rounded)),
                  ],
                  selected: {st.themeMode},
                  onSelectionChanged: (s) => st.setTheme(s.first),
                ),
              ),
              ListTile(
                title: Text(t('fontSize')),
                subtitle: Slider(
                  value: st.fontScale,
                  min: 0.8,
                  max: 1.5,
                  divisions: 7,
                  label: '${(st.fontScale * 100).round()}%',
                  onChanged: st.setFont,
                ),
              ),
              _header(context, t('aiSection')),
              SwitchListTile(
                secondary: const Icon(Icons.auto_awesome_rounded),
                title: Text(t('aiTitle')),
                subtitle: Text(t('aiSub')),
                value: st.useAi,
                onChanged: st.setUseAi,
              ),
              _header(context, t('updateSection')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _repo,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: t('updateRepo'),
                    helperText: t('updateRepoHint'),
                    prefixIcon: const Icon(Icons.cloud_sync_rounded),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => st.setRepo(v),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.system_update_rounded),
                title: Text(t('checkUpdate')),
                subtitle: Text(t('checkUpdateSub')),
                onTap: _checkUpdate,
              ),
              _header(context, t('general')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: t('yourName'),
                    helperText: t('yourNameHint'),
                    prefixIcon: const Icon(Icons.person_rounded),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => st.setUserName(v),
                ),
              ),
              _header(context, t('data')),
              SwitchListTile(
                title: Text(t('saveHistory')),
                subtitle: Text(t('saveHistorySub')),
                value: st.saveHistory,
                onChanged: st.setSaveHistory,
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(t('clearChat')),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text(t('clearTitle')),
                      content: Text(t('clearConfirm')),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: Text(t('cancel'))),
                        FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: Text(t('yes'))),
                      ],
                    ),
                  );
                  if (ok == true) {
                    st.clearMessages();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(t('cleared'))));
                    }
                  }
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- About
class AboutPage extends StatelessWidget {
  final AppState st;
  const AboutPage(this.st, {super.key});

  @override
  Widget build(BuildContext context) {
    String t(String k) => L10n.t(st.lang, k);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t('about'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: cs.primary,
              child: Icon(Icons.auto_awesome_rounded,
                  size: 46, color: cs.onPrimary),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(t('appName'),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Center(child: Text('${t('version')} 1.0.0')),
          const SizedBox(height: 24),
          Text(t('aboutBody'),
              style: const TextStyle(fontSize: 16, height: 1.4)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: Text(t('licenses')),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: t('appName'),
              applicationVersion: '1.0.0',
            ),
          ),
        ],
      ),
    );
  }
}

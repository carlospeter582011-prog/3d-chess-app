// App root: wires the scene, the game controller, settings and all screens together.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chess/types.dart';
import 'chess/uci_engine.dart';
import 'game/game_controller.dart';
import 'game/settings.dart';
import 'game/storage.dart';
import 'net/lan.dart';
import 'platform/ads_service.dart';
import 'scene/board_model.dart';
import 'scene/scene_renderer.dart';
import 'scene/scene_view.dart';
import 'ui/dialogs.dart';
import 'ui/game_banner.dart';
import 'ui/hud.dart';
import 'ui/lan_lobby.dart';
import 'ui/loading.dart';
import 'ui/menu.dart';
import 'ui/theme.dart';

/// Everything the app needs from the outside world (replaced by fakes in tests).
class AppDeps {
  AppDeps({
    required this.model,
    required this.renderer,
    required this.engine,
    required this.store,
    required this.sfx,
    this.ads,
    this.lan = const LanServices(),
    this.autoQuality = Quality.high,
    this.showIntro = false,
    this.introMinimum = const Duration(milliseconds: 1500),
    this.introAdTimeout = const Duration(seconds: 5),
  });

  /// Preset chosen for this device at start-up; used when the setting is "Auto". Fixed for the whole session.
  final Quality autoQuality;

  /// Show the intro (logo and board loading) before the menu. Off in widget tests.
  final bool showIntro;
  final Duration introMinimum;

  /// Maximum time a launch ad has to load, independent of when the menu is ready.
  final Duration introAdTimeout;
  final BoardModel model;
  final SceneRenderer renderer;
  final BotEngine engine;
  final KeyValueStore store;
  final Sfx sfx;
  final AdsService? ads;

  /// Two-phone play (replaced by a fake in widget tests).
  final LanServices lan;
}

class ChessApp extends StatelessWidget {
  const ChessApp({super.key, required this.deps});
  final AppDeps deps;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '3D Chess',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: AppRoot(deps: deps),
      );
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.deps});
  final AppDeps deps;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  late final GameController game;
  late Settings settings;
  List<SavedGame> slots = const [];
  bool ready = false;
  int done = 0, total = 13;
  String? error;
  int attempt = 0;
  bool showResult = false;
  bool _resultHandled = false;
  bool _wasActive = false;
  bool? _lobbyHost; // null: closed, true: hosting, false: joining
  final math.Random _rnd = math.Random();
  late final AdsService _ads = d.ads ?? AdsService();
  late bool _introMinimumElapsed = !d.showIntro;
  bool _launchAdShowing = false;
  Timer? _introTimer;

  bool get _introDone => _introMinimumElapsed && !_launchAdShowing;

  AppDeps get d => widget.deps;

  GraphicsPreset get _preset =>
      GraphicsPreset.of(settings.quality == Quality.auto ? d.autoQuality : settings.quality);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    settings = Settings.decode(d.store.get(settingsKey));
    slots = GameController.loadSlots(d.store);
    game = GameController(board: d.model, engine: d.engine, store: d.store, sfx: d.sfx);
    game.applySettings(settings);
    game.addListener(_onGame);
    if (d.showIntro) {
      _runIntro();
    } else {
      unawaited(_ads.initialize());
    }
  }

  void _runIntro() {
    _introTimer = Timer(d.introMinimum, () => setState(() => _introMinimumElapsed = true));
    unawaited(_ads.requestLaunchAd(
      timeout: d.introAdTimeout,
      canShow: () =>
          mounted &&
          error == null &&
          !(ready && _introMinimumElapsed) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      onVisibilityChanged: (showing) => setState(() => _launchAdShowing = showing),
    ));
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    game.removeListener(_onGame);
    _ads.dispose();
    game.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      d.model.requestRender();
    }
  }

  void _onGame() {
    final s = game.snapshot;
    // result card when a game ends; attract-mode rotation only while the menu is up
    final over = s.status != GameStatus.playing && s.active;
    // the card waits until the board is idle, so the checkmate animation (king thrown off) plays first
    if (over && !s.busy && !_resultHandled) {
      _resultHandled = true;
      showResult = true;
      _ads.onGameFinished();
    }
    if (!over) {
      showResult = false;
      _resultHandled = false;
    }
    if (s.active != _wasActive) {
      _wasActive = s.active;
      d.model.setAutoRotate(!s.active);
    }
    if (!s.active) slots = GameController.loadSlots(d.store); // the menu shows the saved games
    if (mounted) setState(() {});
  }

  void _onSceneEvent(SceneEvent e) {
    switch (e) {
      case SceneProgress(:final done, :final total):
        setState(() {
          this.done = done;
          this.total = total;
        });
      case SceneLoaded():
        game.applySettings(settings);
        game.syncBoard();
        d.model.setAutoRotate(!game.snapshot.active);
        setState(() {
          ready = true;
          error = null;
        });
      case SceneError(:final message):
        setState(() => error = message);
    }
  }

  void _updateSettings(Settings s) {
    final old = settings;
    setState(() => settings = s);
    d.store.set(settingsKey, s.encode());
    game.applySettings(s);
    // let the player hear / feel what they just chose
    if (s.soundPack != old.soundPack || (s.haptics && !old.haptics)) {
      unawaited(d.sfx.setPack(s.soundPack.name).then((_) => d.sfx.move()));
    }
  }

  void _start(Settings s) {
    final human = switch (s.humanColor) {
      HumanColor.white => Side.w,
      HumanColor.black => Side.b,
      HumanColor.random => _rnd.nextBool() ? Side.w : Side.b,
    };
    game.start(GameConfig(mode: s.mode, humanColor: human, elo: s.elo, timeSec: s.timeMin * 60, incSec: s.incSec));
  }

  void _startLan(LanSetup s) {
    setState(() => _lobbyHost = null);
    game.startLan(s.link, s.mySide, isHost: s.isHost, timeSec: s.timeSec, incSec: s.incSec, myName: s.myName, oppName: s.oppName, reconnect: s.reconnect);
  }

  void _resumeSlot(SavedGame sv) {
    game.start(sv.config, moves: sv.moves, whiteMs: sv.whiteMs, blackMs: sv.blackMs, slotId: sv.id);
  }

  void _deleteSlot(String id) {
    GameController.deleteSlot(d.store, id);
    setState(() => slots = GameController.loadSlots(d.store));
  }

  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(settings: settings, onChanged: _updateSettings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = game.snapshot;
    final active = snap.active;
    return Scaffold(
      backgroundColor: C.bg,
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth / c.maxHeight >= 1.25;
        final padding = MediaQuery.paddingOf(context);
        final bannerWidth = (c.maxWidth - padding.horizontal).floor();
        return Column(children: [
          if (ready &&
              _introDone &&
              active &&
              snap.status == GameStatus.playing &&
              MediaQuery.orientationOf(context) == Orientation.portrait &&
              bannerWidth > 0)
            GameBanner(
              key: ValueKey(bannerWidth),
              width: bannerWidth,
              ads: _ads,
            ),
          Expanded(child: _gameContent(context, wide)),
        ]);
      }),
    );
  }

  Widget _gameContent(BuildContext context, bool wide) {
    final snap = game.snapshot;
    final active = snap.active;
    // Landscape: the button row is a bar under the board, so it never covers it.
    final barH = (active && wide && ready) ? 58.0 + MediaQuery.paddingOf(context).bottom : 0.0;
    return Stack(children: [
      Positioned(
        left: 0,
        top: 0,
        bottom: barH,
        right: 0,
        child: SceneView(
          key: ValueKey('scene-$attempt'),
          model: d.model,
          renderer: d.renderer,
          shadows: _preset.shadows,
          renderScaleCap: _preset.renderScaleCap,
          onTap: game.tap,
          onEvent: _onSceneEvent,
        ),
      ),
      if (ready && _introDone && !active)
        Positioned.fill(
          child: MenuScreen(
            settings: settings,
            onSettings: _updateSettings,
            slots: slots,
            hasActive: snap.history.isNotEmpty && snap.status == GameStatus.playing,
            onStart: _start,
            onContinue: game.resume,
            onResumeSlot: _resumeSlot,
            onDeleteSlot: _deleteSlot,
            onOpenSettings: _openSettings,
            onHost: () => setState(() => _lobbyHost = true),
            onJoin: () => setState(() => _lobbyHost = false),
          ),
        ),
      if (ready && !active && _lobbyHost != null)
        Positioned.fill(
          child: LanLobby(
            key: ValueKey('lobby-$_lobbyHost'),
            host: _lobbyHost!,
            services: d.lan,
            onStart: _startLan,
            timeSec: settings.timeMin * 60,
            incSec: settings.incSec,
            playerName: settings.playerName,
            onCancel: () => setState(() => _lobbyHost = null),
          ),
        ),
      if (ready && active)
        Positioned.fill(
          child: Hud(game: game, snapshot: snap, board: d.model, onMenu: game.leave, onSettings: _openSettings, wide: wide),
        ),
      if (ready && active && snap.promotion != null)
        Positioned.fill(
          child: PromotionDialog(side: snap.turn, onChoose: game.choosePromotion, onCancel: game.cancelPromotion),
        ),
      if (ready && active && snap.drawOfferIn)
        Positioned.fill(child: DrawOfferDialog(onAnswer: game.answerDraw)),
      if (ready && active && snap.takebackIn)
        Positioned.fill(child: TakebackOfferDialog(name: snap.opponentName, onAnswer: game.answerTakeback)),
      if (ready && active && showResult)
        Positioned.fill(
          child: ResultDialog(
            snapshot: snap,
            onClose: () => setState(() => showResult = false),
            onMenu: () {
              setState(() => showResult = false);
              game.leave();
            },
            onRematch: () {
              setState(() => showResult = false);
              if (snap.config.mode == GameMode.lan) {
                game.requestRematch();
              } else {
                game.start(snap.config);
              }
            },
          ),
        ),
      if (!ready || !_introDone)
        Positioned.fill(
          child: LoadingScreen(
            message: ready ? 'Starting…' : null,
            done: done,
            total: total,
            error: error,
            onRetry: () => setState(() {
              error = null;
              done = 0;
              attempt++;
            }),
          ),
        ),
    ]);
  }
}

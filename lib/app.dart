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
import 'scene/board_model.dart';
import 'scene/scene_renderer.dart';
import 'scene/scene_view.dart';
import 'platform/ads_service.dart';
import 'ui/dialogs.dart';
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
    this.lan = const LanServices(),
    this.autoQuality = Quality.high,
    this.showIntro = false,
    this.introMinimum = const Duration(milliseconds: 1500),
    this.introAdTimeout = const Duration(seconds: 5),
  });

  /// Preset chosen for this device at start-up; used when the setting is "Auto". Fixed for the whole session.
  final Quality autoQuality;

  /// Show the intro (logo + launch ad wait) before the menu. Off in widget tests.
  final bool showIntro;
  final Duration introMinimum;

  /// Longest the intro waits for the App Open ad; after that the app starts without it.
  final Duration introAdTimeout;
  final BoardModel model;
  final SceneRenderer renderer;
  final BotEngine engine;
  final KeyValueStore store;
  final Sfx sfx;

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
  SavedGame? saved;
  bool ready = false;
  int done = 0, total = 13;
  String? error;
  int attempt = 0;
  bool showResult = false;
  bool _resultHandled = false;
  bool _wasActive = false;
  bool? _lobbyHost; // null: closed, true: hosting, false: joining
  final math.Random _rnd = math.Random();
  late final AdsService _ads = AdsService(
    // an App Open ad must never cover a game in progress
    canShowAppOpen: () =>
        _introDone && !(game.snapshot.history.isNotEmpty && game.snapshot.status == GameStatus.playing),
  );
  late bool _introDone = !d.showIntro;

  AppDeps get d => widget.deps;

  GraphicsPreset get _preset =>
      GraphicsPreset.of(settings.quality == Quality.auto ? d.autoQuality : settings.quality);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    settings = Settings.decode(d.store.get(settingsKey));
    saved = GameController.loadSaved(d.store);
    game = GameController(board: d.model, engine: d.engine, store: d.store, sfx: d.sfx);
    game.applySettings(settings);
    game.addListener(_onGame);
    if (d.showIntro) {
      unawaited(_runIntro());
    } else {
      unawaited(_ads.initialize());
    }
  }

  /// Intro: logo screen while the 3D scene loads and the launch ad gets a limited chance to load and be shown. The
  /// menu stays hidden (and untouchable) until this is over, so no ad can ever appear once the player is using the app.
  Future<void> _runIntro() async {
    await Future.wait<void>([
      Future<void>.delayed(d.introMinimum),
      _ads.showColdStartAd(timeout: d.introAdTimeout),
    ]);
    if (mounted) setState(() => _introDone = true);
  }

  @override
  void dispose() {
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
      _ads.onResume();
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
    setState(() => settings = s);
    d.store.set(settingsKey, s.encode());
    game.applySettings(s);
  }

  void _start(Settings s) {
    final human = switch (s.humanColor) {
      HumanColor.white => Side.w,
      HumanColor.black => Side.b,
      HumanColor.random => _rnd.nextBool() ? Side.w : Side.b,
    };
    GameController.clearSaved(d.store);
    saved = null;
    game.start(GameConfig(mode: s.mode, humanColor: human, elo: s.elo));
  }

  void _startLan(RemoteLink link, Side mySide, bool isHost) {
    GameController.clearSaved(d.store);
    saved = null;
    setState(() => _lobbyHost = null);
    game.startLan(link, mySide, isHost: isHost);
  }

  void _resumeSaved() {
    final sv = saved;
    if (sv == null) return;
    game.start(sv.config, moves: sv.moves);
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
        // Any landscape screen (phones included) gets the side panel, so the HUD never covers the board.
        final wide = c.maxWidth / c.maxHeight >= 1.25;
        final panelWidth = (c.maxWidth * 0.36).clamp(250.0, 340.0);
        final panel = (active && wide && ready) ? panelWidth : 0.0;
        return Stack(children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            right: panel,
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
          if (ready && !active)
            Positioned.fill(
              child: MenuScreen(
                settings: settings,
                onSettings: _updateSettings,
                saved: saved,
                hasActive: snap.history.isNotEmpty && snap.status == GameStatus.playing,
                onStart: _start,
                onContinue: game.resume,
                onResumeSaved: _resumeSaved,
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
                onCancel: () => setState(() => _lobbyHost = null),
              ),
            ),
          if (ready && active)
            wide
                ? Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: panelWidth,
                    child: Hud(game: game, snapshot: snap, board: d.model, onMenu: game.leave, onSettings: _openSettings, wide: true, showMoves: settings.showMoves, showCaptured: settings.showCaptured),
                  )
                : Positioned.fill(
                    child: Hud(game: game, snapshot: snap, board: d.model, onMenu: game.leave, onSettings: _openSettings, showMoves: settings.showMoves, showCaptured: settings.showCaptured),
                  ),
          if (ready && active && snap.promotion != null)
            Positioned.fill(
              child: PromotionDialog(side: snap.turn, onChoose: game.choosePromotion, onCancel: game.cancelPromotion),
            ),
          if (ready && active && snap.drawOfferIn)
            Positioned.fill(child: DrawOfferDialog(onAnswer: game.answerDraw)),
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
      }),
    );
  }
}

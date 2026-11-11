// Game controller: a port of Game.ts. Owns the rules engine, drives the 3D board and the bot, and publishes an
// immutable [GameSnapshot] to the UI through [ChangeNotifier].

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../chess/rules.dart';
import '../chess/types.dart';
import '../chess/uci_engine.dart';
import '../net/lan.dart';
import '../scene/board_scene.dart';
import 'settings.dart';
import 'storage.dart';

const String saveKey = 'chess3d-save-v1';
const String settingsKey = 'chess3d-settings-v1';

class Promotion {
  final String from, to;
  const Promotion(this.from, this.to);
}

class GameSnapshot {
  final int version;
  final bool active;
  final GameConfig config;
  final String fen;
  final Side turn;
  final List<String> history; // SAN
  final GameStatus status;
  final String reason;
  final Side? winner;
  final bool check;
  final bool thinking;
  final bool busy;
  final String? selected;
  final Promotion? promotion;

  /// Pieces each side has lost.
  final Map<Side, List<PT>> captured;
  final bool canUndo;
  final bool engineError;

  /// Two-phone games: the connection to the other phone was lost.
  final bool linkLost;

  /// Two-phone games: the other player offered a draw / we offered one and wait for the answer.
  final bool drawOfferIn, drawOfferOut;

  /// Two-phone games: we asked for a rematch and wait for the other player.
  final bool rematchWaiting;

  /// Chess clock: milliseconds left for each side (only meaningful when `config.timed`).
  final int whiteMs, blackMs;

  const GameSnapshot({
    required this.version,
    required this.active,
    required this.config,
    required this.fen,
    required this.turn,
    required this.history,
    required this.status,
    required this.reason,
    required this.winner,
    required this.check,
    required this.thinking,
    required this.busy,
    required this.selected,
    required this.promotion,
    required this.captured,
    required this.canUndo,
    required this.engineError,
    this.linkLost = false,
    this.drawOfferIn = false,
    this.drawOfferOut = false,
    this.rematchWaiting = false,
    this.whiteMs = 0,
    this.blackMs = 0,
  });
}

class SavedGame {
  final GameConfig config;
  final List<String> moves; // UCI
  final int? whiteMs, blackMs; // clock, when the game was timed
  const SavedGame(this.config, this.moves, {this.whiteMs, this.blackMs});
}

class GameController extends ChangeNotifier {
  GameController({
    required this.board,
    required this.engine,
    required this.store,
    required this.sfx,
    math.Random? random,
    this.thinkMinimum = const Duration(milliseconds: 450),
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        _random = random ?? math.Random() {
    _refresh();
  }

  final BoardScene board;
  final BotEngine engine;
  final KeyValueStore store;
  final Sfx sfx;
  final math.Random _random;
  final DateTime Function() _now;

  /// A bot move is never played faster than this, so it does not feel instant.
  final Duration thinkMinimum;

  Chess chess = Chess();
  GameConfig config = const GameConfig();
  late GameSnapshot _snap;
  int _version = 0;
  bool _active = false;
  String? _selected;
  Promotion? _promotion;
  bool _thinking = false;
  bool _busy = false;
  int _epoch = 0;
  Side? _resigned; // side that resigned
  bool _agreedDraw = false;
  Side? _flagged; // side whose clock ran out
  bool _engineError = false;
  bool autoFlip = false;
  bool _disposed = false;

  // two-phone games
  RemoteLink? _link;
  StreamSubscription<Map<String, dynamic>>? _linkSub;
  bool _isHost = false;
  bool _linkLost = false;
  bool _drawIn = false, _drawOut = false;
  bool _rematchMine = false, _rematchTheirs = false;
  bool get _lan => config.mode == GameMode.lan;

  // chess clock
  Timer? _clockTimer;
  int _wMs = 0, _bMs = 0;
  DateTime? _clockAt;
  int _shown = -1;
  bool get _timed => config.timed;

  GameSnapshot get snapshot => _snap;
  bool get isBusy => _busy;

  // ------------------------------------------------------------------ snapshot plumbing
  void _refresh() {
    if (_disposed) return;
    final hist = chess.history;
    final captured = <Side, List<PT>>{Side.w: [], Side.b: []};
    for (final m in hist) {
      final c = m.captured;
      if (c != null) captured[m.side.other]!.add(c);
    }
    final st = computeStatus();
    _snap = GameSnapshot(
      version: ++_version,
      active: _active,
      config: config,
      fen: chess.fen(),
      turn: chess.turn,
      history: [for (final m in hist) m.san],
      status: st.status,
      reason: st.reason,
      winner: st.winner,
      check: chess.isCheck,
      thinking: _thinking,
      busy: _busy,
      selected: _selected,
      promotion: _promotion,
      captured: captured,
      canUndo: hist.isNotEmpty && !_busy && st.status != GameStatus.resigned && !_lan,
      engineError: _engineError,
      linkLost: _linkLost,
      drawOfferIn: _drawIn,
      drawOfferOut: _drawOut,
      rematchWaiting: _rematchMine && !_rematchTheirs,
      whiteMs: _wMs,
      blackMs: _bMs,
    );
    _shown = _displaySecond();
    notifyListeners();
  }

  ({GameStatus status, String reason, Side? winner}) computeStatus() {
    final c = chess;
    final r = _resigned;
    if (r != null) return (status: GameStatus.resigned, reason: '${r.label} resigned', winner: r.other);
    final f = _flagged;
    if (f != null) return (status: GameStatus.resigned, reason: '${f.label} ran out of time', winner: f.other);
    if (_agreedDraw) return (status: GameStatus.draw, reason: 'Draw agreed', winner: null);
    if (c.isCheckmate) return (status: GameStatus.checkmate, reason: 'Checkmate', winner: c.turn.other);
    if (c.isStalemate) return (status: GameStatus.stalemate, reason: 'Stalemate', winner: null);
    if (c.isInsufficientMaterial) return (status: GameStatus.draw, reason: 'Insufficient material', winner: null);
    if (c.isThreefoldRepetition) return (status: GameStatus.draw, reason: 'Threefold repetition', winner: null);
    if (c.isDrawByFiftyMoves) return (status: GameStatus.draw, reason: 'Fifty-move rule', winner: null);
    return (status: GameStatus.playing, reason: '', winner: null);
  }

  // ------------------------------------------------------------------ settings
  void applySettings(Settings s) {
    autoFlip = s.autoFlip;
    sfx.setMuted(!s.sound);
    board.setLabelsVisible(s.labels);
  }

  // ------------------------------------------------------------------ lifecycle
  List<PlacedPiece> placed() => chess.pieces();

  void syncBoard() {
    board.setPosition(placed());
    _updateMarkers();
  }

  /// Starts a new game, optionally resuming from a list of UCI moves.
  void start(GameConfig cfg, {List<String> moves = const [], int? whiteMs, int? blackMs}) {
    _cancelThinking();
    if (cfg.mode != GameMode.lan) _dropLink();
    _drawIn = _drawOut = _rematchMine = _rematchTheirs = false;
    config = cfg;
    chess = Chess();
    if (moves.isNotEmpty) {
      try {
        chess = Chess.fromUci(moves);
      } on FormatException {
        chess = Chess();
      }
    }
    _resigned = null;
    _flagged = null;
    _agreedDraw = false;
    _selected = null;
    _promotion = null;
    _busy = false;
    _engineError = false;
    _active = true;
    _wMs = whiteMs ?? cfg.timeSec * 1000;
    _bMs = blackMs ?? cfg.timeSec * 1000;
    _clockAt = _now();
    _syncClockTimer();
    engine.resetGame();
    syncBoard();
    final side = cfg.mode == GameMode.local ? chess.turn : cfg.humanColor;
    board.setAutoRotate(false);
    board.resetCamera(animate: true, side: side);
    _refresh();
    _save();
    unawaited(_maybeBotMove());
  }

  /// Back to the menu without losing the game.
  void leave() {
    _cancelThinking();
    if (_lan) {
      // a two-phone game cannot be paused: leaving closes the connection and clears the board
      _dropLink();
      chess = Chess();
      config = const GameConfig();
      _resigned = null;
      _flagged = null;
      _agreedDraw = false;
      _selected = null;
      _promotion = null;
      _busy = false;
      _linkLost = false;
      _drawIn = _drawOut = _rematchMine = _rematchTheirs = false;
      syncBoard();
    }
    _settleClock();
    _active = false;
    _clockAt = null;
    _syncClockTimer();
    _refresh();
  }

  void resume() {
    _active = true;
    _clockAt = _now();
    _syncClockTimer();
    _refresh();
    unawaited(_maybeBotMove());
  }

  // ------------------------------------------------------------------ persistence
  void _save() {
    try {
      if (_lan) return; // two-phone games are not saved
      if (chess.history.isEmpty && !_active) return;
      if (computeStatus().status != GameStatus.playing) {
        store.remove(saveKey);
        return;
      }
      _settleClock();
      store.set(saveKey, jsonEncode({'config': config.toJson(), 'moves': chess.uciHistory, if (_timed) 'clock': {'w': _wMs, 'b': _bMs}}));
    } catch (e) {
      debugPrint('save failed: $e');
    }
  }

  static SavedGame? loadSaved(KeyValueStore store) {
    try {
      final text = store.get(saveKey);
      if (text == null) return null;
      final j = jsonDecode(text);
      if (j is! Map) return null;
      final cfg = GameConfig.fromJson(j['config']);
      final moves = j['moves'];
      if (cfg == null || moves is! List) return null;
      final list = moves.whereType<String>().toList();
      // validate: a corrupted save must never crash the app
      Chess.fromUci(list);
      final clock = j['clock'];
      int? w, b;
      if (cfg.timed && clock is Map && clock['w'] is num && clock['b'] is num) {
        w = (clock['w'] as num).round().clamp(1, 1 << 30);
        b = (clock['b'] as num).round().clamp(1, 1 << 30);
      }
      return SavedGame(cfg, list, whiteMs: w, blackMs: b);
    } catch (_) {
      return null;
    }
  }

  static void clearSaved(KeyValueStore store) => store.remove(saveKey);

  void _cancelThinking() {
    _epoch++;
    if (_thinking) engine.stop();
    _thinking = false;
  }

  // ------------------------------------------------------------------ input
  bool _isHumanTurn() {
    if (config.mode == GameMode.local) return true;
    if (_lan && _linkLost) return false;
    return chess.turn == config.humanColor;
  }

  List<Move> legalFrom(String sq) => chess.legalMoves(from: sq);

  /// A tap on the board. [sq] is the piece or square under the finger, [ground] the floor square under it.
  void tap(String sq, [String? ground]) {
    if (!_active || _busy || _promotion != null) return;
    if (computeStatus().status != GameStatus.playing || !_isHumanTurn()) return;
    // A tall piece can hide the square behind it. If a piece is selected and the tap landed on a piece that
    // is not a legal destination (e.g. the selected piece itself) while the floor under the finger IS one, move there.
    final sel = _selected;
    if (sel != null && ground != null && ground != sq) {
      final legal = legalFrom(sel);
      final hit = chess.get(sq);
      final ownOther = hit != null && hit.side == chess.turn && sq != sel;
      if (!legal.any((m) => m.toName == sq) && legal.any((m) => m.toName == ground) && !ownOther) sq = ground;
    }
    final piece = chess.get(sq);
    if (sel != null) {
      Move? mv;
      for (final m in legalFrom(sel)) {
        if (m.toName == sq) {
          mv = m;
          break;
        }
      }
      if (mv != null) {
        if (mv.isPromotion) {
          _promotion = Promotion(sel, sq);
          _refresh();
          return;
        }
        unawaited(playMove(sel, sq));
        return;
      }
      if (piece != null && piece.side == chess.turn && sq != sel) {
        _select(sq);
        return;
      }
      _deselect();
      return;
    }
    if (piece != null && piece.side == chess.turn) _select(sq);
  }

  void _select(String sq) {
    _selected = sq;
    board.lift(sq);
    _updateMarkers();
    _refresh();
  }

  void _deselect() {
    _selected = null;
    board.unlift();
    _updateMarkers();
    _refresh();
  }

  void choosePromotion(PT p) {
    final pr = _promotion;
    if (pr == null) return;
    if (p == PT.p || p == PT.k) return;
    _promotion = null;
    unawaited(playMove(pr.from, pr.to, p));
  }

  void cancelPromotion() {
    _promotion = null;
    _deselect();
  }

  void _updateMarkers() {
    final hist = chess.history;
    final last = hist.isEmpty ? null : hist.last;
    final sel = _selected;
    final targets = sel == null
        ? <TargetMarker>[]
        : [for (final m in legalFrom(sel)) TargetMarker(m.toName, capture: m.isCapture)];
    String? check;
    if (chess.isCheck) check = chess.kingSquare(chess.turn);
    board.setMarkers(MarkerSet(
      selected: sel,
      targets: targets,
      last: last == null ? null : (last.fromName, last.toName),
      check: check,
    ));
  }

  // ------------------------------------------------------------------ moves
  Future<Move?> playMove(String from, String to, [PT? promotion, bool fromRemote = false]) async {
    _busy = true;
    _selected = null;
    _settleClock();
    final mover = chess.turn;
    final mv = chess.move(from, to, promotion?.ch);
    if (mv == null) {
      _busy = false;
      _updateMarkers();
      _refresh();
      return null;
    }
    if (_timed) {
      if (mover == Side.w) {
        _wMs += config.incSec * 1000;
      } else {
        _bMs += config.incSec * 1000;
      }
      _clockAt = _now();
    }
    if (_lan && !fromRemote) _link?.send({'t': 'move', 'uci': mv.uci});
    _drawIn = _drawOut = false; // a pending draw offer lapses once a move is played
    board.setMarkers(MarkerSet(last: (mv.fromName, mv.toName)));
    _refresh();
    final rank = from[1];
    final capSq = mv.isEp ? '${to[0]}$rank' : (mv.isCapture ? to : null);
    final jobs = <Future<void>>[
      board.movePiece(from, to, capture: capSq, promotion: mv.promotion),
      if (mv.isKingside) board.movePiece('h$rank', 'f$rank'),
      if (mv.isQueenside) board.movePiece('a$rank', 'd$rank'),
    ];
    if (mv.isCapture) {
      sfx.capture();
    } else {
      sfx.move();
    }
    await Future.wait(jobs);
    if (_disposed) return mv;
    _updateMarkers();
    final st = computeStatus();
    if (st.status == GameStatus.checkmate) {
      // jingle + the losing king is thrown off the board; the result card appears afterwards
      sfx.checkmate();
      await board.knockOverKing(chess.turn);
      if (_disposed) return mv;
    } else if (st.status == GameStatus.stalemate) {
      sfx.stalemate();
    } else if (st.status != GameStatus.playing) {
      sfx.end();
    } else if (chess.isCheck) {
      sfx.check();
    }
    _busy = false;
    _refresh();
    _save();
    if (st.status == GameStatus.playing) {
      if (config.mode == GameMode.local && autoFlip) {
        // Rotate exactly 180 degrees around the board; zoom, tilt and target are kept (no camera reset).
        board.flipView();
      }
      unawaited(_maybeBotMove());
    }
    return mv;
  }

  Future<void> _maybeBotMove() async {
    if (!_active || config.mode != GameMode.bot) return;
    if (computeStatus().status != GameStatus.playing) return;
    if (chess.turn == config.humanColor) return;
    final token = ++_epoch;
    _thinking = true;
    _refresh();
    final started = DateTime.now();
    String? uci;
    try {
      uci = await engine.bestMove(chess.fen(), config.elo);
    } catch (e) {
      debugPrint('engine failed, falling back to a random move: $e');
      _engineError = true;
    }
    if (token != _epoch || _disposed) return; // cancelled (undo / new game / leave)
    final legal = chess.legalMoves();
    Move? mv;
    if (uci != null) {
      for (final m in legal) {
        if (m.uci == uci) {
          mv = m;
          break;
        }
      }
    }
    if (mv == null && legal.isNotEmpty) {
      mv = legal[_random.nextInt(legal.length)];
      if (uci != null) _engineError = true; // the engine answered with a move we don't accept
    }
    if (mv == null) {
      _thinking = false;
      _refresh();
      return;
    }
    final wait = thinkMinimum - DateTime.now().difference(started);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (token != _epoch || _disposed) return;
    _thinking = false;
    await playMove(mv.fromName, mv.toName, mv.promotion);
  }

  // ------------------------------------------------------------------ game actions
  void undo() {
    if (_lan || _busy || chess.history.isEmpty || _resigned != null || _flagged != null) return;
    _cancelThinking();
    _agreedDraw = false;
    chess.undo();
    if (config.mode == GameMode.bot && chess.turn != config.humanColor && chess.history.isNotEmpty) chess.undo();
    _selected = null;
    _promotion = null;
    syncBoard();
    _refresh();
    _save();
    if (config.mode == GameMode.local && autoFlip) {
      board.flipView(); // undo hands the move back: turn the view 180 degrees again
    }
    unawaited(_maybeBotMove());
  }

  void resign() {
    if (computeStatus().status != GameStatus.playing) return;
    _cancelThinking();
    _resigned = config.mode == GameMode.local ? chess.turn : config.humanColor;
    if (_lan) _link?.send({'t': 'resign'});
    _selected = null;
    _promotion = null;
    board.unlift();
    _updateMarkers();
    _refresh();
    _save();
    sfx.end();
  }

  /// Draw by agreement on one device. Two-phone games go through [offerDraw] / [answerDraw].
  void agreeDraw() {
    if (_lan) return;
    _applyDraw();
  }

  void _applyDraw() {
    if (computeStatus().status != GameStatus.playing) return;
    _cancelThinking();
    _agreedDraw = true;
    _drawIn = _drawOut = false;
    _selected = null;
    board.unlift();
    _updateMarkers();
    _refresh();
    _save();
    sfx.end();
  }

  // ------------------------------------------------------------------ two-phone games
  /// Starts a two-phone game on an open connection. [mySide] is this phone's colour; the host decides the colours.
  void startLan(RemoteLink link, Side mySide, {required bool isHost, int timeSec = 0, int incSec = 0}) {
    _dropLink();
    _link = link;
    _isHost = isHost;
    _linkLost = false;
    _linkSub = link.messages.listen(_onRemote);
    unawaited(link.done.then((_) {
      if (identical(_link, link)) _onLinkLost();
    }));
    start(GameConfig(mode: GameMode.lan, humanColor: mySide, timeSec: timeSec, incSec: incSec));
  }

  void _dropLink() {
    final l = _link;
    _link = null;
    unawaited(_linkSub?.cancel());
    _linkSub = null;
    if (l != null) unawaited(l.close());
  }

  void _onLinkLost() {
    if (_disposed) return;
    _link = null;
    _linkLost = true;
    _drawIn = _drawOut = false;
    _refresh();
  }

  void _onRemote(Map<String, dynamic> m) {
    if (_disposed || !_lan) return;
    switch (m['t']) {
      case 'move':
        final uci = m['uci'];
        if (uci is String) unawaited(_playRemoteMove(uci));
      case 'resign':
        if (computeStatus().status != GameStatus.playing) return;
        _resigned = config.humanColor.other;
        _finishQuietly();
      case 'draw':
        switch (m['a']) {
          case 'offer':
            if (computeStatus().status == GameStatus.playing) {
              _drawIn = true;
              _refresh();
            }
          case 'accept':
            if (_drawOut) _applyDraw();
          case 'decline':
            _drawOut = false;
            _refresh();
        }
      case 'timeout':
        if (!_timed || computeStatus().status != GameStatus.playing) return;
        _flagged = config.humanColor.other;
        _finishQuietly();
      case 'rematch':
        _rematchTheirs = true;
        _refresh();
        _maybeRematch();
      case 'start':
        final you = m['you'];
        if (!_isHost && (you == 'w' || you == 'b')) {
          final t = m['time'], i = m['inc'];
          start(GameConfig(
            mode: GameMode.lan,
            humanColor: sideFromChar(you as String),
            timeSec: t is num ? t.round().clamp(0, 3 * 3600) : 0,
            incSec: i is num ? i.round().clamp(0, 60) : 0,
          ));
        }
    }
  }

  /// The other player's move. Only a legal move for the side to move is ever played.
  Future<void> _playRemoteMove(String uci) async {
    for (var i = 0; i < 100 && _busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_disposed || !_lan || _linkLost) return;
    if (computeStatus().status != GameStatus.playing || chess.turn == config.humanColor) return;
    for (final m in chess.legalMoves()) {
      if (m.uci == uci) {
        await playMove(m.fromName, m.toName, m.promotion, true);
        return;
      }
    }
    debugPrint('ignored an illegal remote move: $uci');
  }

  void _finishQuietly() {
    _cancelThinking();
    _selected = null;
    _promotion = null;
    _drawIn = _drawOut = false;
    board.unlift();
    _updateMarkers();
    _refresh();
    _save();
    sfx.end();
  }

  /// Asks the other player for a draw (two-phone games).
  void offerDraw() {
    if (!_lan || _linkLost || _drawOut || computeStatus().status != GameStatus.playing) return;
    _drawOut = true;
    _link?.send({'t': 'draw', 'a': 'offer'});
    _refresh();
  }

  void answerDraw(bool accept) {
    if (!_lan || !_drawIn) return;
    _drawIn = false;
    _link?.send({'t': 'draw', 'a': accept ? 'accept' : 'decline'});
    if (accept) {
      _applyDraw();
    } else {
      _refresh();
    }
  }

  /// Both players must ask; then the host starts the next game with the colours swapped.
  void requestRematch() {
    if (!_lan || _linkLost || _rematchMine) return;
    _rematchMine = true;
    _link?.send({'t': 'rematch'});
    _refresh();
    _maybeRematch();
  }

  void _maybeRematch() {
    if (!(_rematchMine && _rematchTheirs && _isHost && _link != null)) return;
    final guestNew = config.humanColor; // the host's old colour goes to the guest
    _link!.send({'t': 'start', 'you': guestNew.ch, 'time': config.timeSec, 'inc': config.incSec});
    start(GameConfig(mode: GameMode.lan, humanColor: config.humanColor.other, timeSec: config.timeSec, incSec: config.incSec));
  }

  /// Developer / test hook: jump to an arbitrary position.
  void debugLoadFen(String fen) {
    _cancelThinking();
    chess = Chess(fen);
    _selected = null;
    _promotion = null;
    _busy = false;
    _resigned = null;
    _flagged = null;
    _agreedDraw = false;
    syncBoard();
    _refresh();
  }

  // ------------------------------------------------------------------ chess clock
  int _msOf(Side s) => s == Side.w ? _wMs : _bMs;

  /// The clock only runs once the first move has been played, while a game is on screen.
  bool get _clockRunning =>
      _timed && _active && _flagged == null && !_linkLost && chess.history.isNotEmpty && computeStatus().status == GameStatus.playing;

  int _displaySecond() => (_msOf(chess.turn) + 999) ~/ 1000;

  /// Charges the time since the last call to the side to move.
  void _settleClock() {
    final at = _clockAt;
    final now = _now();
    _clockAt = _timed && _active ? now : null;
    if (at == null || !_clockRunning) return;
    final ms = now.difference(at).inMilliseconds;
    if (ms <= 0) return;
    if (chess.turn == Side.w) {
      _wMs = math.max(0, _wMs - ms);
    } else {
      _bMs = math.max(0, _bMs - ms);
    }
  }

  void _syncClockTimer() {
    final need = _timed && _active && _flagged == null && computeStatus().status == GameStatus.playing;
    if (!need) {
      _clockTimer?.cancel();
      _clockTimer = null;
    } else {
      _clockTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) => debugTickClock());
    }
  }

  /// One clock step (called by the timer; tests call it directly).
  @visibleForTesting
  void debugTickClock() {
    if (_disposed) return;
    _settleClock();
    if (!_clockRunning) {
      if (computeStatus().status != GameStatus.playing) _syncClockTimer();
      return;
    }
    final turn = chess.turn;
    if (_msOf(turn) <= 0) {
      // two phones: each phone only declares its OWN clock empty, so both always agree on the result
      if (_lan && turn != config.humanColor) {
        _refresh();
        return;
      }
      _flag(turn);
      return;
    }
    if (_displaySecond() != _shown) _refresh();
  }

  void _flag(Side s) {
    _cancelThinking();
    _flagged = s;
    if (_lan) _link?.send({'t': 'timeout'});
    _finishQuietly();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _clockTimer = null;
    _disposed = true;
    _dropLink();
    _epoch++;
    engine.dispose();
    super.dispose();
  }
}

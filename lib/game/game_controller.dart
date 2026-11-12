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

const String saveKey = 'chess3d-save-v1'; // old single-slot save, migrated into the slots below
const String slotsKey = 'chess3d-saves-v2';

/// How many unfinished games are kept; when full, the one played longest ago is replaced.
const int saveSlots = 3;
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

  /// Two-phone games: the other player's name, a take-back request in either direction, and a short notice.
  final String opponentName;
  final bool takebackOut, takebackIn, canTakeback;
  final String? notice;

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
    this.opponentName = 'Opponent',
    this.takebackOut = false,
    this.takebackIn = false,
    this.canTakeback = false,
    this.notice,
  });
}

class SavedGame {
  final GameConfig config;
  final List<String> moves; // UCI
  final int? whiteMs, blackMs; // clock, when the game was timed
  final String id;
  final int ts; // when it was last played (ms since epoch)
  const SavedGame(this.config, this.moves, {this.whiteMs, this.blackMs, this.id = '', this.ts = 0});
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
  String _slotId = '';
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
  bool _tbOut = false, _tbIn = false; // take-back request sent / received
  int _tbN = 0; // number of half-moves when the request was made
  String? _notice;
  String _myName = 'You', _oppName = 'Opponent';
  LanReconnect? _reconnect;
  StreamSubscription<RemoteLink>? _reconnectSub;
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
      opponentName: _oppName,
      takebackOut: _tbOut,
      takebackIn: _tbIn,
      canTakeback: _canTakeback,
      notice: _notice,
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
    unawaited(sfx.setPack(s.soundPack.name));
    sfx.setHaptics(s.haptics);
    board.setLabelsVisible(s.labels);
    board.setRoom(s.room.name);
  }

  // ------------------------------------------------------------------ lifecycle
  List<PlacedPiece> placed() => chess.pieces();

  void syncBoard() {
    board.setPosition(placed());
    _updateMarkers();
  }

  /// Starts a new game, optionally resuming from a list of UCI moves.
  void start(GameConfig cfg, {List<String> moves = const [], int? whiteMs, int? blackMs, String? slotId}) {
    _cancelThinking();
    if (cfg.mode != GameMode.lan) _dropLink();
    _drawIn = _drawOut = _rematchMine = _rematchTheirs = false;
    _tbOut = _tbIn = false;
    _notice = null;
    config = cfg;
    chess = Chess();
    if (moves.isNotEmpty) {
      try {
        chess = Chess.fromUci(moves);
      } on FormatException {
        chess = Chess();
      }
    }
    _slotId = slotId ?? _now().microsecondsSinceEpoch.toString();
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
      _tbOut = _tbIn = false;
      _notice = null;
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
      if (computeStatus().status != GameStatus.playing) {
        deleteSlot(store, _slotId); // a finished game is not kept
        return;
      }
      if (chess.history.isEmpty) return; // nothing to keep yet
      _settleClock();
      final slots = _readSlots(store).where((g) => g.id != _slotId).toList();
      slots.add(SavedGame(config, chess.uciHistory, whiteMs: _timed ? _wMs : null, blackMs: _timed ? _bMs : null, id: _slotId, ts: _now().millisecondsSinceEpoch));
      slots.sort((a, b) => b.ts.compareTo(a.ts));
      _writeSlots(store, slots.take(saveSlots).toList());
    } catch (e) {
      debugPrint('save failed: $e');
    }
  }

  static Map<String, Object?> _slotJson(SavedGame g) => {
        'id': g.id,
        'ts': g.ts,
        'config': g.config.toJson(),
        'moves': g.moves,
        if (g.whiteMs != null && g.blackMs != null) 'clock': {'w': g.whiteMs, 'b': g.blackMs},
      };

  static void _writeSlots(KeyValueStore store, List<SavedGame> slots) {
    store.remove(saveKey); // the old single-slot save has been migrated
    if (slots.isEmpty) {
      store.remove(slotsKey);
    } else {
      store.set(slotsKey, jsonEncode([for (final g in slots) _slotJson(g)]));
    }
  }

  static SavedGame? _parseSlot(Object? j, {String fallbackId = '', int fallbackTs = 0}) {
    try {
      if (j is! Map) return null;
      final cfg = GameConfig.fromJson(j['config']);
      final moves = j['moves'];
      if (cfg == null || moves is! List) return null;
      final list = moves.whereType<String>().toList();
      if (list.isEmpty) return null;
      // validate: a corrupted save must never crash the app
      Chess.fromUci(list);
      final clock = j['clock'];
      int? w, b;
      if (cfg.timed && clock is Map && clock['w'] is num && clock['b'] is num) {
        w = (clock['w'] as num).round().clamp(1, 1 << 30);
        b = (clock['b'] as num).round().clamp(1, 1 << 30);
      }
      final id = j['id'] is String && (j['id'] as String).isNotEmpty ? j['id'] as String : fallbackId;
      final ts = j['ts'] is num ? (j['ts'] as num).round() : fallbackTs;
      return SavedGame(cfg, list, whiteMs: w, blackMs: b, id: id, ts: ts);
    } catch (_) {
      return null;
    }
  }

  static List<SavedGame> _readSlots(KeyValueStore store) {
    final out = <SavedGame>[];
    try {
      final text = store.get(slotsKey);
      if (text != null) {
        final j = jsonDecode(text);
        if (j is List) {
          for (final e in j) {
            final g = _parseSlot(e);
            if (g != null && g.id.isNotEmpty) out.add(g);
          }
        }
      } else {
        // the old single save becomes the first slot
        final old = store.get(saveKey);
        if (old != null) {
          final g = _parseSlot(jsonDecode(old), fallbackId: 'migrated', fallbackTs: 1);
          if (g != null) out.add(g);
        }
      }
    } catch (_) {}
    out.sort((a, b) => b.ts.compareTo(a.ts));
    return out.take(saveSlots).toList();
  }

  /// The unfinished games kept on this phone, most recently played first (at most [saveSlots]).
  static List<SavedGame> loadSlots(KeyValueStore store) => _readSlots(store);

  static void deleteSlot(KeyValueStore store, String id) {
    final all = _readSlots(store);
    final rest = all.where((g) => g.id != id).toList();
    if (rest.length != all.length || store.get(saveKey) != null) {
      _writeSlots(store, rest);
      store.remove(saveKey); // the migrated old save is gone for good
    }
  }

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
    if (_lan && (_tbOut || _tbIn)) return; // wait for the answer to the take-back request
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
    _notice = null;
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
    _tbOut = _tbIn = false;
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
    _tbOut = _tbIn = false;
    _selected = null;
    board.unlift();
    _updateMarkers();
    _refresh();
    _save();
    sfx.end();
  }

  // ------------------------------------------------------------------ two-phone games
  /// Starts a two-phone game on an open connection. [mySide] is this phone's colour; the host decides the colours.
  void startLan(
    RemoteLink link,
    Side mySide, {
    required bool isHost,
    int timeSec = 0,
    int incSec = 0,
    String myName = 'You',
    String oppName = 'Opponent',
    LanReconnect? reconnect,
  }) {
    _dropLink();
    _isHost = isHost;
    _myName = myName;
    _oppName = oppName;
    _attach(link);
    _reconnect = reconnect;
    _reconnectSub = reconnect?.links.listen(_adopt);
    start(GameConfig(mode: GameMode.lan, humanColor: mySide, timeSec: timeSec, incSec: incSec));
  }

  void _attach(RemoteLink link) {
    unawaited(_linkSub?.cancel());
    _link = link;
    _linkLost = false;
    _linkSub = link.messages.listen(_onRemote);
    unawaited(link.done.then((_) {
      if (identical(_link, link)) _onLinkLost();
    }));
  }

  /// The connection came back (the guest rejoined): carry on, and compare move lists in case a move was lost on the way.
  void _adopt(RemoteLink link) {
    if (_disposed || !_lan) {
      unawaited(link.close());
      return;
    }
    final old = _link;
    if (old != null && !identical(old, link)) unawaited(old.close());
    _settleClock();
    _attach(link);
    _clockAt = _now();
    link.send({'t': 'sync', 'moves': chess.uciHistory});
    _refresh();
  }

  void _dropLink() {
    final l = _link;
    _link = null;
    unawaited(_linkSub?.cancel());
    _linkSub = null;
    unawaited(_reconnectSub?.cancel());
    _reconnectSub = null;
    final r = _reconnect;
    _reconnect = null;
    if (r != null) unawaited(r.stop());
    if (l != null) unawaited(l.close());
  }

  void _onLinkLost() {
    if (_disposed) return;
    _settleClock();
    _link = null;
    _linkLost = true;
    _drawIn = _drawOut = false;
    _tbOut = _tbIn = false;
    _refresh();
    // while the game is still on, try to get the connection back (the host just keeps listening)
    if (computeStatus().status == GameStatus.playing) unawaited(_reconnect?.start());
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
      case 'sync':
        final theirs = m['moves'];
        if (theirs is! List || computeStatus().status != GameStatus.playing) return;
        final mine = chess.uciHistory;
        final list = theirs.whereType<String>().toList();
        if (list.length > mine.length && [for (var i = 0; i < mine.length; i++) list[i] == mine[i]].every((e) => e)) {
          unawaited(_playRemoteMoves(list.sublist(mine.length)));
        }
      case 'tb':
        _onTakeback(m);
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

  Future<void> _playRemoteMoves(List<String> moves) async {
    for (final u in moves) {
      await _playRemoteMove(u);
    }
  }

  // ---- take-back requests (two-phone games)
  bool get _canTakeback {
    if (!_lan || _linkLost || _tbOut || _tbIn || _drawOut || _drawIn || _busy) return false;
    if (computeStatus().status != GameStatus.playing) return false;
    final n = chess.history.length;
    if (n == 0) return false;
    final lastMover = n.isOdd ? Side.w : Side.b;
    return lastMover == config.humanColor || n >= 2; // takes back my last move (and the reply, if there was one)
  }

  void requestTakeback() {
    if (!_canTakeback) return;
    _tbOut = true;
    _tbN = chess.history.length;
    _notice = null;
    _link?.send({'t': 'tb', 'a': 'req', 'n': _tbN});
    _refresh();
  }

  void answerTakeback(bool accept) {
    if (!_lan || !_tbIn) return;
    _tbIn = false;
    final n = _tbN;
    final ok = accept && computeStatus().status == GameStatus.playing && n == chess.history.length;
    _link?.send({'t': 'tb', 'a': ok ? 'yes' : 'no', 'n': n});
    if (ok) {
      _applyTakeback(config.humanColor.other, n);
    } else {
      _refresh();
    }
  }

  void _onTakeback(Map<String, dynamic> m) {
    final n = m['n'];
    switch (m['a']) {
      case 'req':
        if (n is! int || n < 1 || _tbOut || computeStatus().status != GameStatus.playing || n != chess.history.length) {
          _link?.send({'t': 'tb', 'a': 'no', 'n': n});
          return;
        }
        _tbIn = true;
        _tbN = n;
        _refresh();
      case 'yes':
        if (!_tbOut) return;
        _tbOut = false;
        if (n != _tbN || n != chess.history.length) {
          _refresh();
          return;
        }
        _applyTakeback(config.humanColor, n);
      case 'no':
        if (!_tbOut) return;
        _tbOut = false;
        _notice = 'Take-back declined';
        _refresh();
    }
  }

  /// Both phones undo the same half-moves: the requester's last move (and the opponent's reply, if it has been made).
  void _applyTakeback(Side requester, int n) {
    _cancelThinking();
    _settleClock();
    final lastMover = n.isOdd ? Side.w : Side.b;
    final plies = lastMover == requester ? 1 : 2;
    for (var i = 0; i < plies && chess.history.isNotEmpty; i++) {
      chess.undo();
    }
    _selected = null;
    _promotion = null;
    _notice = null;
    board.unlift();
    syncBoard();
    _refresh();
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
    _tbOut = _tbIn = false;
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

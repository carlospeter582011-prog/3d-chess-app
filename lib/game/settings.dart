// Player settings and game configuration (ported from Game.ts).

import 'dart:convert';

import '../chess/types.dart';

/// bot = against the computer, local = two players on one phone, lan = two phones over Wi-Fi / hotspot.
enum GameMode { bot, local, lan }

enum GameStatus { playing, checkmate, stalemate, draw, resigned }

/// Graphics preset. [auto] resolves ONCE at app start from the device class (see [GraphicsPreset]); it never changes
/// by itself while a game is running.
enum Quality { auto, high, medium, low }

/// What a preset changes in the renderer.
class GraphicsPreset {
  const GraphicsPreset({required this.shadows, required this.renderScaleCap});

  /// Real-time shadows + 4x MSAA.
  final bool shadows;

  /// Upper limit for the render-resolution multiplier (physical pixels per logical pixel).
  final double renderScaleCap;

  static GraphicsPreset of(Quality q) => switch (q) {
        Quality.high || Quality.auto => const GraphicsPreset(shadows: true, renderScaleCap: 2.0),
        Quality.medium => const GraphicsPreset(shadows: true, renderScaleCap: 1.5),
        Quality.low => const GraphicsPreset(shadows: false, renderScaleCap: 1.25),
      };
}

/// What the menu stores for "your colour": a side or a random pick.
enum HumanColor { white, black, random }

class GameConfig {
  final GameMode mode;
  final Side humanColor;
  final int elo;

  /// Chess clock: time per player in seconds (0 = no clock) and the seconds added after each move.
  final int timeSec, incSec;
  const GameConfig({this.mode = GameMode.bot, this.humanColor = Side.w, this.elo = 1200, this.timeSec = 0, this.incSec = 0});

  bool get timed => timeSec > 0;

  Map<String, Object> toJson() => {'mode': mode.name, 'humanColor': humanColor.ch, 'elo': elo, 'time': timeSec, 'inc': incSec};

  static GameConfig? fromJson(Object? j) {
    if (j is! Map) return null;
    final mode = j['mode'] == 'local' ? GameMode.local : (j['mode'] == 'lan' ? GameMode.lan : GameMode.bot);
    final human = j['humanColor'] == 'b' ? Side.b : Side.w;
    final elo = j['elo'] is num ? (j['elo'] as num).round() : 1200;
    final time = j['time'] is num ? (j['time'] as num).round().clamp(0, 3 * 3600) : 0;
    final inc = j['inc'] is num ? (j['inc'] as num).round().clamp(0, 60) : 0;
    return GameConfig(mode: mode, humanColor: human, elo: elo, timeSec: time, incSec: inc);
  }

  @override
  bool operator ==(Object other) =>
      other is GameConfig && other.mode == mode && other.humanColor == humanColor && other.elo == elo && other.timeSec == timeSec && other.incSec == incSec;

  @override
  int get hashCode => Object.hash(mode, humanColor, elo, timeSec, incSec);
}

class Settings {
  final bool sound;
  final bool labels;
  final Quality quality;
  final bool autoFlip;

  /// Move list and captured pieces are hidden unless the player turns them on.
  final bool showMoves;
  final bool showCaptured;
  final int elo;
  final HumanColor humanColor;
  final GameMode mode;

  /// Chess clock for new games: minutes per player (0 = off) and increment in seconds.
  final int timeMin, incSec;

  const Settings({
    this.sound = true,
    this.labels = true,
    this.quality = Quality.auto,
    this.autoFlip = false,
    this.showMoves = false,
    this.showCaptured = false,
    this.elo = 1200,
    this.humanColor = HumanColor.white,
    this.mode = GameMode.bot,
    this.timeMin = 0,
    this.incSec = 0,
  });

  Settings copyWith({
    bool? sound,
    bool? labels,
    Quality? quality,
    bool? autoFlip,
    bool? showMoves,
    bool? showCaptured,
    int? elo,
    HumanColor? humanColor,
    GameMode? mode,
    int? timeMin,
    int? incSec,
  }) =>
      Settings(
        sound: sound ?? this.sound,
        labels: labels ?? this.labels,
        quality: quality ?? this.quality,
        autoFlip: autoFlip ?? this.autoFlip,
        showMoves: showMoves ?? this.showMoves,
        showCaptured: showCaptured ?? this.showCaptured,
        elo: elo ?? this.elo,
        humanColor: humanColor ?? this.humanColor,
        mode: mode ?? this.mode,
        timeMin: timeMin ?? this.timeMin,
        incSec: incSec ?? this.incSec,
      );

  String encode() => jsonEncode({
        'sound': sound,
        'labels': labels,
        'quality': quality.name,
        'autoFlip': autoFlip,
        'showMoves': showMoves,
        'showCaptured': showCaptured,
        'elo': elo,
        'humanColor': humanColor.name,
        'mode': mode.name,
        'timeMin': timeMin,
        'incSec': incSec,
      });

  /// Tolerant decoding: anything missing or malformed falls back to the default.
  static Settings decode(String? text) {
    if (text == null || text.isEmpty) return const Settings();
    try {
      final j = jsonDecode(text);
      if (j is! Map) return const Settings();
      T pick<T extends Enum>(List<T> values, Object? v, T d) {
        for (final e in values) {
          if (e.name == v) return e;
        }
        return d;
      }

      return Settings(
        sound: j['sound'] is bool ? j['sound'] as bool : true,
        labels: j['labels'] is bool ? j['labels'] as bool : true,
        quality: pick(Quality.values, j['quality'], Quality.auto),
        autoFlip: j['autoFlip'] is bool ? j['autoFlip'] as bool : false,
        showMoves: j['showMoves'] is bool ? j['showMoves'] as bool : false,
        showCaptured: j['showCaptured'] is bool ? j['showCaptured'] as bool : false,
        elo: j['elo'] is num ? (j['elo'] as num).round().clamp(400, 3200) : 1200,
        humanColor: pick(HumanColor.values, j['humanColor'], HumanColor.white),
        mode: pick(GameMode.values, j['mode'], GameMode.bot),
        timeMin: j['timeMin'] is num ? (j['timeMin'] as num).round().clamp(0, 180) : 0,
        incSec: j['incSec'] is num ? (j['incSec'] as num).round().clamp(0, 60) : 0,
      );
    } catch (_) {
      return const Settings();
    }
  }

  @override
  bool operator ==(Object other) => other is Settings && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

String eloName(int e) {
  if (e < 600) return 'Beginner';
  if (e < 1000) return 'Novice';
  if (e < 1400) return 'Casual';
  if (e < 1800) return 'Club player';
  if (e < 2200) return 'Advanced';
  if (e < 2600) return 'Expert';
  if (e < 3000) return 'Master';
  return 'Grandmaster+';
}

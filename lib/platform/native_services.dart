// Android services reached through a MethodChannel: persistent key-value storage (SharedPreferences) and sound
// (SoundPool). Both are tiny, so no extra pub packages are needed.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../game/settings.dart' show Quality;
import '../game/storage.dart';
import 'sfx_synth.dart';

const MethodChannel _services = MethodChannel('chess3d/services');

class ChannelStore implements KeyValueStore {
  final Map<String, String> _cache = {};

  @override
  Future<void> load() async {
    try {
      final all = await _services.invokeMapMethod<String, String>('storeGetAll');
      _cache
        ..clear()
        ..addAll(all ?? const {});
    } catch (e) {
      debugPrint('storage load failed: $e');
    }
  }

  @override
  String? get(String key) => _cache[key];

  @override
  void set(String key, String value) {
    _cache[key] = value;
    unawaited(_services.invokeMethod<void>('storeSet', {'key': key, 'value': value}).catchError((Object e) {
      debugPrint('storage write failed: $e');
    }));
  }

  @override
  void remove(String key) {
    _cache.remove(key);
    unawaited(_services.invokeMethod<void>('storeRemove', {'key': key}).catchError((Object e) {
      debugPrint('storage remove failed: $e');
    }));
  }
}

/// Graphics preset for this device, asked once at start-up (low RAM / old Android -> low, < 6 GB -> medium).
Future<Quality> detectDeviceQuality() async {
  try {
    final tier = await _services.invokeMethod<String>('deviceTier');
    return switch (tier) {
      'low' => Quality.low,
      'medium' => Quality.medium,
      _ => Quality.high,
    };
  } catch (_) {
    return Quality.high;
  }
}

/// A recorded sound shipped in assets/sfx/<name>.wav|ogg|mp3, if there is one.
Future<Uint8List?> _bundledSound(String name) async {
  for (final ext in const ['wav', 'ogg', 'mp3']) {
    try {
      final d = await rootBundle.load('assets/sfx/$name.$ext');
      return d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
    } catch (_) {}
  }
  return null;
}

class ChannelSfx implements Sfx {
  bool _muted = false;
  bool _loaded = false;
  bool _haptics = false;
  String _pack = 'wood';
  final Set<String> _recorded = {};
  final Set<String> _packsLoaded = {};
  final Map<String, Future<void>> _loading = {};

  /// Generates the sounds and gives them to the native SoundPool.
  Future<void> init() async {
    try {
      await _loadPack('wood');
      // Recorded jingles for the end of a game (assets/sfx/checkmate.mp3, stalemate.mp3); no synthesized fallback.
      for (final name in const ['checkmate', 'stalemate']) {
        final bytes = await _bundledSound(name);
        if (bytes == null) continue;
        await _services.invokeMethod<void>('sfxLoad', {'name': name, 'wav': bytes});
        _recorded.add(name);
      }
      _loaded = true;
    } catch (e) {
      debugPrint('sound init failed: $e');
    }
  }

  Future<void> _loadPack(String pack) {
    if (_packsLoaded.contains(pack)) return Future<void>.value();
    return _loading[pack] ??= () async {
      try {
        for (final name in soundNames) {
          // a recorded file in assets/sfx replaces the synthesised sound of the original (wood) set
          final bytes = (pack == 'wood' ? await _bundledSound(name) : null) ?? toWav(synthesize(name, pack: pack));
          await _services.invokeMethod<void>('sfxLoad', {'name': '$pack:$name', 'wav': bytes});
        }
        _packsLoaded.add(pack);
      } catch (e) {
        debugPrint('sound pack $pack failed: $e');
      } finally {
        _loading.remove(pack);
      }
    }();
  }

  @override
  Future<void> setPack(String pack) async {
    if (!soundPacks.contains(pack)) return;
    _pack = pack;
    await _loadPack(pack);
  }

  @override
  void setHaptics(bool on) => _haptics = on;

  void _play(String name) {
    if (_muted || !_loaded) return;
    final key = _packsLoaded.contains(_pack) ? '$_pack:$name' : 'wood:$name';
    unawaited(_services.invokeMethod<void>('sfxPlay', {'name': key}).catchError((Object _) {}));
  }

  void _playJingle(String name) {
    if (_muted || !_loaded) return;
    unawaited(_services.invokeMethod<void>('sfxPlay', {'name': name}).catchError((Object _) {}));
  }

  void _buzz(Future<void> Function() f) {
    if (_haptics) unawaited(f().catchError((Object _) {}));
  }

  @override
  void setMuted(bool muted) => _muted = muted;
  @override
  void move() {
    _play('move');
    _buzz(HapticFeedback.selectionClick);
  }

  @override
  void capture() {
    _play('capture');
    _buzz(HapticFeedback.mediumImpact);
  }

  @override
  void check() {
    _play('check');
    _buzz(HapticFeedback.heavyImpact);
  }

  @override
  void end() {
    _play('end');
    _buzz(HapticFeedback.heavyImpact);
  }

  @override
  void checkmate() {
    _recorded.contains('checkmate') ? _playJingle('checkmate') : _play('end');
    _buzz(HapticFeedback.heavyImpact);
  }

  @override
  void stalemate() {
    _recorded.contains('stalemate') ? _playJingle('stalemate') : _play('end');
    _buzz(HapticFeedback.heavyImpact);
  }
}

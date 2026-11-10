// Android services reached through a MethodChannel: persistent key-value storage (SharedPreferences) and sound
// (SoundPool). Both are tiny, so no extra pub packages are needed.

import 'dart:async';
import 'dart:typed_data';

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
  final Set<String> _recorded = {};

  /// Generates the sounds and gives them to the native SoundPool.
  Future<void> init() async {
    try {
      for (final name in soundNames) {
        final bytes = await _bundledSound(name) ?? toWav(synthesize(name));
        await _services.invokeMethod<void>('sfxLoad', {'name': name, 'wav': bytes});
      }
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

  void _play(String name) {
    if (_muted || !_loaded) return;
    unawaited(_services.invokeMethod<void>('sfxPlay', {'name': name}).catchError((Object _) {}));
  }

  @override
  void setMuted(bool muted) => _muted = muted;
  @override
  void move() => _play('move');
  @override
  void capture() => _play('capture');
  @override
  void check() => _play('check');
  @override
  void end() => _play('end');
  @override
  void checkmate() => _play(_recorded.contains('checkmate') ? 'checkmate' : 'end');
  @override
  void stalemate() => _play(_recorded.contains('stalemate') ? 'stalemate' : 'end');
}

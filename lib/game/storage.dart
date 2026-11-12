// Tiny key-value store. Reads are synchronous (served from memory after [load]); writes go to disk in the background.

abstract class KeyValueStore {
  /// Loads everything from disk into memory. Call once before use.
  Future<void> load();
  String? get(String key);
  void set(String key, String value);
  void remove(String key);
}

/// In-memory store used by tests.
class MemoryStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<void> load() async {}
  @override
  String? get(String key) => data[key];
  @override
  void set(String key, String value) => data[key] = value;
  @override
  void remove(String key) => data.remove(key);
}

/// The sounds of the game. The real implementation lives in platform/native_services.dart.
abstract class Sfx {
  void setMuted(bool muted);

  /// Which set of sounds to play ('wood', 'glass', 'soft'); completes when it is ready to play.
  Future<void> setPack(String pack);

  /// Short vibration with moves, captures and check.
  void setHaptics(bool on);
  void move();
  void capture();
  void check();
  void end();
  void checkmate();
  void stalemate();
}

class SilentSfx implements Sfx {
  final List<String> played = [];
  String pack = 'wood';
  bool haptics = false;
  @override
  void setMuted(bool muted) {}
  @override
  Future<void> setPack(String p) async => pack = p;
  @override
  void setHaptics(bool on) => haptics = on;
  @override
  void move() => played.add('move');
  @override
  void capture() => played.add('capture');
  @override
  void check() => played.add('check');
  @override
  void end() => played.add('end');
  @override
  void checkmate() => played.add('checkmate');
  @override
  void stalemate() => played.add('stalemate');
}

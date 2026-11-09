import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Android official Google sample ad units. Never use production IDs in tests.
class AdsService {
  static const appOpenTestId = 'ca-app-pub-3940256099942544/9257395921';
  static const interstitialTestId = 'ca-app-pub-3940256099942544/1033173712';

  AppOpenAd? _open;
  InterstitialAd? _interstitial;
  bool _initialized = false;
  bool _showing = false;
  bool _loadingOpen = false;
  bool _loadingInterstitial = false;
  DateTime? _lastShown;
  bool _disposed = false;

  Future<void> initialize() async {
    try {
      await MobileAds.instance.initialize();
      if (_disposed) return;
      _initialized = true;
      _loadOpen();
      _loadInterstitial();
    } catch (_) {
      // Offline chess must always remain playable.
    }
  }

  bool get _canShow => !_disposed && !_showing &&
      (_lastShown == null ||
          DateTime.now().difference(_lastShown!) > const Duration(minutes: 2));

  void _loadOpen() {
    if (!_initialized || _disposed || _loadingOpen || _open != null) return;
    _loadingOpen = true;
    AppOpenAd.load(
      adUnitId: appOpenTestId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingOpen = false;
          if (_disposed) { ad.dispose(); return; }
          _open = ad;
        },
        onAdFailedToLoad: (_) { _loadingOpen = false; },
      ),
    );
  }

  void _loadInterstitial() {
    if (!_initialized || _disposed || _loadingInterstitial || _interstitial != null) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: interstitialTestId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          if (_disposed) { ad.dispose(); return; }
          _interstitial = ad;
        },
        onAdFailedToLoad: (_) { _loadingInterstitial = false; },
      ),
    );
  }

  /// Show only on return from background, never while another ad is on screen.
  void onResume() {
    if (!_canShow || _open == null) { _loadOpen(); return; }
    final ad = _open!;
    _open = null;
    _showing = true;
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showing = false;
        _loadOpen();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _showing = false;
        _loadOpen();
      },
    );
    _lastShown = DateTime.now();
    ad.show();
  }

  /// At most one ad per completed game, never during an active match.
  void onGameFinished() {
    if (!_canShow || _interstitial == null) { _loadInterstitial(); return; }
    final ad = _interstitial!;
    _interstitial = null;
    _showing = true;
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showing = false;
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _showing = false;
        _loadInterstitial();
      },
    );
    _lastShown = DateTime.now();
    ad.show();
  }

  void dispose() {
    _disposed = true;
    _open?.dispose();
    _interstitial?.dispose();
    _open = null;
    _interstitial = null;
  }
}

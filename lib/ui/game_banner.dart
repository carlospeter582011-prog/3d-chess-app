import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../platform/ads_service.dart';
import 'theme.dart';

/// The portrait game's top ad slot. It takes up space only while displaying an ad.
class GameBanner extends StatefulWidget {
  const GameBanner({super.key, required this.width, required this.ads});

  final int width;
  final AdsService ads;

  @override
  State<GameBanner> createState() => _GameBannerState();
}

class _GameBannerState extends State<GameBanner> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await widget.ads.initialize();
      if (!mounted) return;
      final size =
          await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
            widget.width,
          );
      if (!mounted || size == null) return;

      final banner = BannerAd(
        adUnitId: AdsService.bannerTestId,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted || _banner != ad) return;
            setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, _) {
            if (_banner == ad) _clear();
          },
        ),
      );
      _banner = banner;
      await banner.load();
    } catch (_) {
      _clear();
    }
  }

  void _clear() {
    final banner = _banner;
    _banner = null;
    if (_loaded && mounted) {
      setState(() => _loaded = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (banner != null) unawaited(banner.dispose());
      });
    } else if (banner != null) {
      unawaited(banner.dispose());
    }
  }

  @override
  void dispose() {
    final banner = _banner;
    _banner = null;
    if (banner != null) unawaited(banner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    if (!_loaded || banner == null) return const SizedBox.shrink();
    return ColoredBox(
      color: C.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Center(
            child: SizedBox(
              width: banner.size.width.toDouble(),
              height: banner.size.height.toDouble(),
              child: AdWidget(ad: banner),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';

/// Uber-night JSON style for [gmaps.GoogleMap] (GCP Maps JavaScript / native).
const String kZivoUberNightMapStyle = r'''
[
  {"elementType":"geometry","stylers":[{"color":"#0b0b0b"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b0b0b"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#1c1c1c"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#111814"},{"visibility":"on"}]},
  {"featureType":"poi.park","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#0b0b0b"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#242424"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#0b0b0b"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#1f1f1f"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0a1620"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4a6a7a"}]}
]
''';

gmaps.LatLng _g(LatLng p) => gmaps.LatLng(p.latitude, p.longitude);

LatLng _fromG(gmaps.LatLng p) => LatLng(p.latitude, p.longitude);

/// Full-bleed Google Map backdrop (tracking). Parent handles tap-to-expand.
class ZivoLiveMapFill extends StatelessWidget {
  const ZivoLiveMapFill({
    super.key,
    required this.center,
    this.showHelpers = true,
  });

  final LatLng center;
  final bool showHelpers;

  @override
  Widget build(BuildContext context) {
    return _GoogleMapSurface(
      center: center,
      interactive: false,
      showHelpers: showHelpers,
      compact: false,
      pin: center,
    );
  }
}

/// Compact peek → tap expands to immersive Google Map (GCP Maps SDK).
class ZivoLiveMapPeek extends StatelessWidget {
  const ZivoLiveMapPeek({
    super.key,
    required this.center,
    this.height = 180,
    this.label,
    this.onPicked,
    this.showHelpers = true,
  });

  final LatLng center;
  final double height;
  final String? label;
  final ValueChanged<LatLng>? onPicked;
  final bool showHelpers;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openZivoLiveMap(
          context,
          center: center,
          label: label,
          onPicked: onPicked,
          showHelpers: showHelpers,
        ),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: _GoogleMapSurface(
                  center: center,
                  interactive: false,
                  showHelpers: showHelpers,
                  compact: true,
                  pin: center,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                    stops: const [0, 0.4, 1],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: _GlassChip(
                  icon: Icons.map_rounded,
                  label: 'Google Maps',
                  accent: palette.accent,
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: _GlassChip(
                  icon: Icons.open_in_full_rounded,
                  label: 'Expand',
                  accent: palette.accent,
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Row(
                  children: [
                    Icon(Icons.place_rounded, color: palette.accent, size: 18),
                    const Gap(6),
                    Expanded(
                      child: Text(
                        label?.trim().isNotEmpty == true
                            ? label!
                            : '${center.latitude.toStringAsFixed(4)}, ${center.longitude.toStringAsFixed(4)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      'Tap for full map',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<LatLng?> openZivoLiveMap(
  BuildContext context, {
  required LatLng center,
  String? label,
  ValueChanged<LatLng>? onPicked,
  bool showHelpers = true,
}) {
  return Navigator.of(context).push<LatLng>(
    PageRouteBuilder<LatLng>(
      opaque: true,
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, anim, secondary) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: _ZivoLiveMapFullscreen(
            initial: center,
            label: label,
            onPicked: onPicked,
            showHelpers: showHelpers,
          ),
        );
      },
    ),
  );
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({
    required this.icon,
    required this.label,
    required this.accent,
  });
  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const Gap(5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ZivoLiveMapFullscreen extends StatefulWidget {
  const _ZivoLiveMapFullscreen({
    required this.initial,
    this.label,
    this.onPicked,
    this.showHelpers = true,
  });

  final LatLng initial;
  final String? label;
  final ValueChanged<LatLng>? onPicked;
  final bool showHelpers;

  @override
  State<_ZivoLiveMapFullscreen> createState() => _ZivoLiveMapFullscreenState();
}

class _ZivoLiveMapFullscreenState extends State<_ZivoLiveMapFullscreen> {
  late LatLng _pin;
  String? _label;
  bool _sheetExpanded = true;
  gmaps.GoogleMapController? _controller;

  @override
  void initState() {
    super.initState();
    _pin = widget.initial;
    _label = widget.label;
  }

  void _dropPin(gmaps.LatLng point) {
    final next = _fromG(point);
    setState(() {
      _pin = next;
      _label = null;
    });
    widget.onPicked?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _GoogleMapSurface(
            center: _pin,
            interactive: true,
            showHelpers: widget.showHelpers,
            pin: _pin,
            onTap: _dropPin,
            onCreated: (c) => _controller = c,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _RoundIconBtn(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.pop(context, _pin),
                    ),
                    const Gap(10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.near_me_rounded,
                                color: palette.accent, size: 18),
                            const Gap(8),
                            Expanded(
                              child: Text(
                                _label?.trim().isNotEmpty == true
                                    ? _label!
                                    : 'Google Maps · tap to drop pin',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Gap(10),
                    _RoundIconBtn(
                      icon: Icons.my_location_rounded,
                      onTap: () {
                        _controller?.animateCamera(
                          gmaps.CameraUpdate.newLatLngZoom(_g(_pin), 15.5),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onVerticalDragUpdate: (d) {
                if (d.primaryDelta != null && d.primaryDelta! > 8) {
                  setState(() => _sheetExpanded = false);
                } else if (d.primaryDelta != null && d.primaryDelta! < -8) {
                  setState(() => _sheetExpanded = true);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  _sheetExpanded ? 16 : 10,
                ),
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    if (_sheetExpanded) ...[
                      const Gap(12),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.place_rounded,
                              color: palette.accent,
                            ),
                          ),
                          const Gap(12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pin this spot',
                                  style: AppTextStyles.headingSmall.copyWith(
                                    color: palette.textPrimary,
                                  ),
                                ),
                                const Gap(2),
                                Text(
                                  '${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: palette.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Gap(14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  setState(() => _sheetExpanded = false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: palette.textPrimary,
                                side: BorderSide(color: palette.border),
                                minimumSize: const Size.fromHeight(50),
                              ),
                              child: const Text('See whole map'),
                            ),
                          ),
                          const Gap(10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                widget.onPicked?.call(_pin);
                                Navigator.pop(context, _pin);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: palette.accent,
                                foregroundColor: palette.onAccent,
                                minimumSize: const Size.fromHeight(50),
                              ),
                              child: const Text('Use this pin'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const Gap(8),
                      InkWell(
                        onTap: () => setState(() => _sheetExpanded = true),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.keyboard_arrow_up_rounded,
                                color: palette.textMuted),
                            const Gap(4),
                            Text(
                              'Show pin controls',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: palette.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  const _RoundIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _HelperDot {
  const _HelperDot({required this.lat, required this.lon, this.name});
  final double lat;
  final double lon;
  final String? name;
}

class _GoogleMapSurface extends StatefulWidget {
  const _GoogleMapSurface({
    required this.center,
    this.interactive = true,
    this.showHelpers = true,
    this.compact = false,
    this.onTap,
    this.pin,
    this.onCreated,
  });

  final LatLng center;
  final bool interactive;
  final bool showHelpers;
  final bool compact;
  final ValueChanged<gmaps.LatLng>? onTap;
  final LatLng? pin;
  final ValueChanged<gmaps.GoogleMapController>? onCreated;

  @override
  State<_GoogleMapSurface> createState() => _GoogleMapSurfaceState();
}

class _GoogleMapSurfaceState extends State<_GoogleMapSurface> {
  List<_HelperDot> _helpers = const [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (widget.showHelpers) {
      _loadHelpers();
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => _loadHelpers());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadHelpers() async {
    if (!mounted) return;
    try {
      final repo = context.read<TaskRepository>();
      final res = await repo.listLiveHelpers(
        lat: widget.center.latitude,
        lon: widget.center.longitude,
      );
      final raw = (res['helpers'] as List?) ?? const [];
      final dots = <_HelperDot>[];
      for (final h in raw) {
        if (h is! Map) continue;
        final lat = (h['lat'] as num?)?.toDouble();
        final lon = (h['lon'] as num?)?.toDouble() ??
            (h['lng'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        dots.add(
          _HelperDot(lat: lat, lon: lon, name: h['full_name']?.toString()),
        );
      }
      if (!mounted) return;
      setState(() => _helpers = dots.take(24).toList());
    } catch (_) {}
  }

  Set<gmaps.Marker> _markers() {
    final pin = widget.pin ?? widget.center;
    return {
      gmaps.Marker(
        markerId: const gmaps.MarkerId('destination'),
        position: _g(pin),
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
          gmaps.BitmapDescriptor.hueAzure,
        ),
        infoWindow: const gmaps.InfoWindow(title: 'Task pin'),
      ),
      for (var i = 0; i < _helpers.length; i++)
        gmaps.Marker(
          markerId: gmaps.MarkerId('helper_$i'),
          position: gmaps.LatLng(_helpers[i].lat, _helpers[i].lon),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueBlue,
          ),
          infoWindow: gmaps.InfoWindow(
            title: _helpers[i].name ?? 'Helper nearby',
          ),
        ),
    };
  }

  Set<gmaps.Circle> _circles(Color accent) {
    final pin = widget.pin ?? widget.center;
    return {
      gmaps.Circle(
        circleId: const gmaps.CircleId('reach'),
        center: _g(pin),
        radius: 180,
        fillColor: accent.withValues(alpha: 0.12),
        strokeColor: accent.withValues(alpha: 0.55),
        strokeWidth: 2,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    final pin = widget.pin ?? widget.center;
    final zoom = widget.compact ? 13.4 : 15.2;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(
        target: _g(widget.center),
        zoom: zoom,
      ),
      style: dark ? kZivoUberNightMapStyle : null,
      markers: _markers(),
      circles: _circles(palette.accent),
      myLocationButtonEnabled: false,
      myLocationEnabled: false,
      zoomControlsEnabled: !kIsWeb && widget.interactive,
      mapToolbarEnabled: false,
      compassEnabled: false,
      rotateGesturesEnabled: false,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      tiltGesturesEnabled: false,
      liteModeEnabled: false,
      onMapCreated: (c) {
        widget.onCreated?.call(c);
        c.moveCamera(gmaps.CameraUpdate.newLatLng(_g(pin)));
      },
      onTap: widget.interactive && widget.onTap != null
          ? (p) => widget.onTap!(p)
          : null,
    );
  }
}

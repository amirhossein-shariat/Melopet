import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'glass.dart';

/// Map tiles. OpenStreetMap works without an API key; to use Neshan's own
/// tiles later, swap this template (Neshan needs a map key from platform.neshan.org).
const kTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const kUserAgent = 'ir.melopet.melopet';
const kTehran = LatLng(35.6997, 51.3380);

/// Reads a PocketBase geoPoint field ({lon, lat}); null when unset (0,0).
LatLng? geoOf(RecordModel? r, String field) {
  final v = r?.data[field];
  if (v is Map) {
    final lat = (v['lat'] as num?)?.toDouble() ?? 0;
    final lon = (v['lon'] as num?)?.toDouble() ?? 0;
    if (lat != 0 || lon != 0) return LatLng(lat, lon);
  }
  return null;
}

Map<String, double> geoJson(LatLng p) => {'lat': p.latitude, 'lon': p.longitude};

/// Opens the point in the Neshan app (falls back to the Neshan website).
Future<void> openInNeshan(LatLng p) async {
  final url = Uri.parse('https://neshan.org/maps/@${p.latitude},${p.longitude},16.0z,0.0p');
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

/// Lets Android show every installed map app (Neshan, Balad, Google Maps...).
Future<void> openInMaps(LatLng p, {String label = ''}) async {
  final q = Uri.encodeComponent(label.isEmpty ? '${p.latitude},${p.longitude}' : label);
  final geo = Uri.parse('geo:${p.latitude},${p.longitude}?q=${p.latitude},${p.longitude}($q)');
  if (!await launchUrl(geo, mode: LaunchMode.externalApplication)) {
    await openInNeshan(p);
  }
}

class _Pin extends StatelessWidget {
  const _Pin();
  @override
  Widget build(BuildContext context) => const Icon(
    Icons.location_on_rounded,
    size: 46,
    color: MP.pinkDeep,
    shadows: [Shadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
  );
}

/// Small static map with a pin + navigation buttons.
class MapPreview extends StatelessWidget {
  final LatLng point;
  final double height;
  final String label;
  final bool showActions;
  const MapPreview({super.key, required this.point, this.height = 170, this.label = '', this.showActions = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: height,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 15.5,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                onTap: (_, _) => openInNeshan(point),
              ),
              children: [
                TileLayer(urlTemplate: kTileUrl, userAgentPackageName: kUserAgent),
                MarkerLayer(
                  markers: [Marker(point: point, width: 46, height: 46, alignment: Alignment.topCenter, child: const _Pin())],
                ),
              ],
            ),
          ),
        ),
        if (showActions) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => openInNeshan(point),
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text('مسیریابی با نشان'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                child: Tooltip(
                  message: 'باز کردن در سایر نقشه‌ها (بلد، گوگل‌مپ...)',
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => openInMaps(point, label: label),
                    child: const Icon(Icons.map_rounded),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Full-screen picker: drag the map under a fixed centre pin, or jump to GPS.
class LocationPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const LocationPickerScreen({super.key, this.initial});

  static Future<LatLng?> pick(BuildContext context, {LatLng? initial}) =>
      Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => LocationPickerScreen(initial: initial)));

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  late LatLng _center = widget.initial ?? kTehran;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) WidgetsBinding.instance.addPostFrameCallback((_) => _myLocation(silent: true));
  }

  Future<void> _myLocation({bool silent = false}) async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!silent && mounted) toast(context, 'لوکیشن (GPS) گوشی خاموش است', error: true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (!silent && mounted) toast(context, 'دسترسی به موقعیت مکانی داده نشد', error: true);
        return;
      }
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 15)));
      final ll = LatLng(p.latitude, p.longitude);
      _map.move(ll, 17);
      setState(() => _center = ll);
    } catch (_) {
      if (!silent && mounted) toast(context, 'موقعیت فعلی پیدا نشد', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('انتخاب موقعیت روی نقشه'),
        flexibleSpace: Container(color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: .75)),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: widget.initial == null ? 12 : 17,
              onPositionChanged: (camera, _) => _center = camera.center,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(urlTemplate: kTileUrl, userAgentPackageName: kUserAgent),
              const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
            ],
          ),
          // fixed centre pin
          const IgnorePointer(
            child: Center(
              child: Padding(padding: EdgeInsets.only(bottom: 46), child: _Pin()),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 120,
            child: FloatingActionButton(
              heroTag: 'gps',
              onPressed: _locating ? null : _myLocation,
              child: _locating
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Glass(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      'نقشه را جابه‌جا کنید تا پین دقیقا روی درِ مجموعه قرار بگیرد',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GradientButton(label: 'تایید این موقعیت', icon: Icons.check_rounded, onPressed: () => Navigator.pop(context, _center)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Form tile: shows the chosen point (or a call to action) and opens the picker.
class LocationField extends StatelessWidget {
  final LatLng? value;
  final ValueChanged<LatLng> onChanged;
  final String title;
  const LocationField({super.key, required this.value, required this.onChanged, this.title = 'موقعیت روی نقشه'});

  @override
  Widget build(BuildContext context) {
    Future<void> pick() async {
      final p = await LocationPickerScreen.pick(context, initial: value);
      if (p != null) onChanged(p);
    }

    return Glass(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: value == null ? pick : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const GlassIcon(Icons.pin_drop_rounded, size: 44, color: MP.danger),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      value == null ? 'برای انتخاب لوکیشن روی نقشه لمس کنید (پیک مستقیم به همین نقطه می‌آید)' : 'موقعیت ثبت شد ✓',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (value != null) TextButton(onPressed: pick, child: const Text('تغییر')),
            ],
          ),
          if (value != null) ...[const SizedBox(height: 10), MapPreview(point: value!, height: 140, showActions: false)],
        ],
      ),
    );
  }
}

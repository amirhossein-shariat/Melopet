import 'api.dart';

/// What the lab offers for getting the sample picked up (like the shipping step of an online shop):
///  - standard: free, collected in the lab's next courier round (every [windowHours] hours)
///  - urgent:   a dedicated courier now, for a quoted fee that is added to the order total
class DeliveryOptionsData {
  final int windowHours;
  final bool urgentAvailable;

  /// why urgent can't be priced: location | lab_location | provider
  final String? urgentReason;
  final num urgentFee;

  /// estimate (built-in distance estimate) or the courier service's own price
  final String source;
  final num distanceKm;
  final String quote;
  final DateTime fetchedAt;

  DeliveryOptionsData({
    required this.windowHours,
    required this.urgentAvailable,
    this.urgentReason,
    this.urgentFee = 0,
    this.source = '',
    this.distanceKm = 0,
    this.quote = '',
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  bool get isEstimate => source == 'estimate';

  /// The signed quote is only valid for a short time; refresh before it expires.
  bool get stale => DateTime.now().difference(fetchedAt) > const Duration(minutes: 10);

  factory DeliveryOptionsData.fromJson(Map<String, dynamic> j) {
    final std = Map<String, dynamic>.from(j['standard'] as Map? ?? {});
    final u = Map<String, dynamic>.from(j['urgent'] as Map? ?? {});
    return DeliveryOptionsData(
      windowHours: (std['window_hours'] as num?)?.toInt() ?? 4,
      urgentAvailable: u['available'] == true,
      urgentReason: u['reason'] as String?,
      urgentFee: (u['fee'] as num?) ?? 0,
      source: '${u['source'] ?? ''}',
      distanceKm: (u['distance_km'] as num?) ?? 0,
      quote: '${u['quote'] ?? ''}',
    );
  }

  static Future<DeliveryOptionsData> fetch({String? clinicId, double? lat, double? lon}) async {
    final res = await Api.pb.send<Map<String, dynamic>>(
      '/api/melopet/delivery/quote',
      method: 'POST',
      body: {'clinic': ?clinicId, 'lat': ?lat, 'lon': ?lon},
    );
    return DeliveryOptionsData.fromJson(res);
  }
}

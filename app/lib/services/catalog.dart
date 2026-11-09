import 'api.dart';

/// A test of the lab's price list (one price for everyone; 0 = by agreement).
class CatalogItem {
  final String id;
  final String name;
  final String code;
  final String category;
  final String sampleType;
  final num hours;
  final num price;
  final String description;

  CatalogItem.fromJson(Map<String, dynamic> j)
    : id = '${j['id']}',
      name = '${j['name'] ?? ''}',
      code = '${j['code'] ?? ''}',
      category = '${j['category'] ?? 'other'}',
      sampleType = '${j['sample_type'] ?? ''}',
      hours = (j['turnaround_hours'] as num?) ?? 0,
      price = (j['price'] as num?) ?? 0,
      description = '${j['description'] ?? ''}';
}

class Catalog {
  static Future<List<CatalogItem>> load() async {
    final res = await Api.pb.send<List<dynamic>>('/api/melopet/catalog');
    return res.map((e) => CatalogItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
}

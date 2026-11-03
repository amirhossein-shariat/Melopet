import 'api.dart';

/// A test as a clinic sees it: with ITS own price (tier never exposed).
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
  static Future<List<CatalogItem>> load({String? clinicId}) async {
    final res = await Api.pb.send<List<dynamic>>('/api/melopet/catalog', query: {'clinic': ?clinicId});
    return res.map((e) => CatalogItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
}

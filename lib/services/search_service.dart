import 'dart:convert';
import 'package:gps_mock/utils/constants.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PlaceSuggestion {
  final String name;
  final String description;
  final LatLng location;
  final bool isIndonesia;

  const PlaceSuggestion({
    required this.name,
    required this.description,
    required this.location,
    this.isIndonesia = false,
  });
}

/// Dual-Engine Place Search backed by OpenStreetMap Nominatim + Photon API.
/// Optimized for full Indonesia address coverage & location prioritization.
class SearchService {
  final http.Client _client = http.Client();

  /// Searches for places matching [query], prioritizing Indonesian results
  /// and biasing towards [near] when given.
  Future<List<PlaceSuggestion>> search(String query, {LatLng? near}) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    // Perform Nominatim and Photon searches in parallel for maximum speed & recall
    final results = await Future.wait([
      _searchNominatim(trimmed, near: near),
      _searchPhoton(trimmed, near: near),
    ]);

    final combined = <PlaceSuggestion>[];
    for (final list in results) {
      combined.addAll(list);
    }

    if (combined.isEmpty) return const [];

    // Deduplicate & sort results (Indonesia locations first)
    return _deduplicateAndRank(combined);
  }

  /// Searches OpenStreetMap Nominatim API (Primary engine for Indonesia POIs & addresses)
  Future<List<PlaceSuggestion>> _searchNominatim(
    String query, {
    LatLng? near,
  }) async {
    try {
      final params = <String, String>{
        'q': query,
        'format': 'jsonv2',
        'addressdetails': '1',
        'accept-language': 'id,en',
        'limit': '10',
      };

      if (near != null) {
        // Add viewbox around the requested location (~50km radius)
        final delta = 0.5;
        params['viewbox'] =
            '${near.longitude - delta},${near.latitude + delta},${near.longitude + delta},${near.latitude - delta}';
        params['bounded'] = '0'; // Soft bias
      }

      final uri = Uri.parse(AppConstants.nominatimBaseUrl)
          .replace(queryParameters: params);
      final response = await _client
          .get(uri, headers: {'User-Agent': AppConstants.userAgent})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return const [];
      return parseNominatimResponse(response.body);
    } catch (_) {
      return const [];
    }
  }

  /// Searches Photon API (Komoot OpenStreetMap engine)
  Future<List<PlaceSuggestion>> _searchPhoton(
    String query, {
    LatLng? near,
  }) async {
    try {
      final params = <String, String>{
        'q': query,
        'limit': '10',
        'lang': 'id',
      };
      if (near != null) {
        params['lat'] = near.latitude.toStringAsFixed(4);
        params['lon'] = near.longitude.toStringAsFixed(4);
      }

      final uri =
          Uri.parse(AppConstants.photonBaseUrl).replace(queryParameters: params);
      final response = await _client
          .get(uri, headers: {'User-Agent': AppConstants.userAgent})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return const [];
      return parsePhotonResponse(response.body);
    } catch (_) {
      return const [];
    }
  }

  /// Parses OpenStreetMap Nominatim JSON response.
  static List<PlaceSuggestion> parseNominatimResponse(String body) {
    final list = jsonDecode(body) as List?;
    if (list == null) return const [];

    final results = <PlaceSuggestion>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final lat = double.tryParse(item['lat']?.toString() ?? '');
      final lon = double.tryParse(item['lon']?.toString() ?? '');
      if (lat == null || lon == null) continue;

      final address = (item['address'] as Map<String, dynamic>?) ?? {};
      final String rawName = (item['name'] ?? '').toString();
      final String displayName = (item['display_name'] ?? '').toString();

      final String name = rawName.isNotEmpty
          ? rawName
          : (address['road'] ?? address['suburb'] ?? address['village'] ?? address['town'] ?? displayName.split(',').first).toString();

      final String country = (address['country'] ?? '').toString();
      final String countryCode = (address['country_code'] ?? '').toString().toLowerCase();

      final parts = [
        address['road'],
        address['suburb'] ?? address['village'] ?? address['neighbourhood'],
        address['town'] ?? address['city'] ?? address['county'],
        address['state'],
        country,
      ]
          .whereType<String>()
          .where((p) => p.isNotEmpty && p != name)
          .toSet()
          .toList();

      final String description = parts.isNotEmpty ? parts.join(', ') : displayName;
      final bool inIndo = countryCode == 'id' || country.contains('Indonesia') || _isInIndonesiaBounds(lat, lon);

      results.add(
        PlaceSuggestion(
          name: name,
          description: description,
          location: LatLng(lat, lon),
          isIndonesia: inIndo,
        ),
      );
    }
    return results;
  }

  /// Parses Photon GeoJSON FeatureCollection response.
  static List<PlaceSuggestion> parsePhotonResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final features = (json['features'] as List?) ?? const [];
    final results = <PlaceSuggestion>[];

    for (final feature in features) {
      final props = (feature['properties'] as Map<String, dynamic>?) ?? {};
      final coords = feature['geometry']?['coordinates'] as List?;
      if (coords == null || coords.length < 2) continue;

      final lat = (coords[1] as num).toDouble();
      final lon = (coords[0] as num).toDouble();
      final name = (props['name'] ?? props['street'] ?? '') as String;
      if (name.isEmpty) continue;

      final country = (props['country'] ?? '').toString();
      final countryCode = (props['countrycode'] ?? '').toString().toLowerCase();

      final parts = [
        props['street'],
        props['district'],
        props['city'],
        props['state'],
        country,
      ]
          .whereType<String>()
          .where((part) => part.isNotEmpty && part != name)
          .toSet()
          .toList();

      final bool inIndo = countryCode == 'id' || country.contains('Indonesia') || _isInIndonesiaBounds(lat, lon);

      results.add(
        PlaceSuggestion(
          name: name,
          description: parts.take(4).join(', '),
          location: LatLng(lat, lon),
          isIndonesia: inIndo,
        ),
      );
    }
    return results;
  }

  /// Checks if coordinates fall within Indonesia geographical bounding box
  static bool _isInIndonesiaBounds(double lat, double lon) {
    return lat >= -11.0 && lat <= 6.0 && lon >= 95.0 && lon <= 141.0;
  }

  /// Removes duplicates and ranks Indonesian locations first
  static List<PlaceSuggestion> _deduplicateAndRank(List<PlaceSuggestion> items) {
    final unique = <PlaceSuggestion>[];
    final seenKeys = <String>{};

    for (final item in items) {
      final key = '${item.name.toLowerCase()}_${item.location.latitude.toStringAsFixed(3)}_${item.location.longitude.toStringAsFixed(3)}';
      if (seenKeys.contains(key)) continue;
      seenKeys.add(key);
      unique.add(item);
    }

    // Sort: Indonesia locations first, then preserved relevance
    unique.sort((a, b) {
      if (a.isIndonesia && !b.isIndonesia) return -1;
      if (!a.isIndonesia && b.isIndonesia) return 1;
      return 0;
    });

    return unique.take(12).toList();
  }
}

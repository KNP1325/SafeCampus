import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

class CampusSafetyLocation {
  const CampusSafetyLocation({
    required this.name,
    required this.type,
    required this.description,
    required this.position,
  });

  final String name;
  final String type;
  final String description;
  final LatLng position;

  static CampusSafetyLocation? fromData(Map<String, dynamic> data) {
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    if (latitude is! num ||
        longitude is! num ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }

    final name = data['name'];
    final type = data['type'];
    final description = data['description'];
    return CampusSafetyLocation(
      name: name is String && name.trim().isNotEmpty
          ? name.trim()
          : 'Safety location',
      type: type is String ? type.replaceAll('_', ' ') : '',
      description: description is String ? description : '',
      position: LatLng(latitude.toDouble(), longitude.toDouble()),
    );
  }
}

class CampusSafeMapScreen extends StatefulWidget {
  const CampusSafeMapScreen({super.key});

  static const campus = LatLng(-32.9013039, 27.664223);

  static Uri get satelliteMapUri => Uri.https('www.google.com', '/maps/@', {
    'api': '1',
    'map_action': 'map',
    'center': '${campus.latitude},${campus.longitude}',
    'zoom': '17',
    'basemap': 'satellite',
  });

  @override
  State<CampusSafeMapScreen> createState() => _CampusSafeMapScreenState();
}

class _CampusSafeMapScreenState extends State<CampusSafeMapScreen> {
  final _mapController = MapController();
  late final _locationsStream = FirebaseFirestore.instance
      .collection('campus_map_markers')
      .snapshots();
  bool _reportedTileError = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(Uri uri, String failureMessage) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (error) {
      debugPrint('Could not open map link: $error');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failureMessage)));
  }

  void _openLocation(CampusSafetyLocation location) {
    _openUrl(
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '${location.position.latitude},${location.position.longitude}',
      }),
      'Could not open Google Maps.',
    );
  }

  void _showLocation(CampusSafetyLocation location) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                location.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (location.type.isNotEmpty) Text(location.type),
              if (location.description.isNotEmpty) Text(location.description),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _openLocation(location),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in Google Maps'),
                style: FilledButton.styleFrom(
                  backgroundColor: SafeCampusColors.forest,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTileError(Object error) {
    if (_reportedTileError) return;
    _reportedTileError = true;
    debugPrint('Campus map tile could not load: $error');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Some map images could not load. Check your internet connection.',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipOval(
              child: Image.asset(
                'assets/images/safecampus_logo.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Campus Safe Map'),
          ],
        ),
        backgroundColor: SafeCampusColors.forest,
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [SafeCampusColors.forest, SafeCampusColors.green],
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _locationsStream,
        builder: (context, snapshot) {
          final documents = snapshot.data?.docs ?? [];
          final locations = documents
              .map((document) => CampusSafetyLocation.fromData(document.data()))
              .whereType<CampusSafetyLocation>()
              .toList();
          final invalidCount = documents.length - locations.length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: OutlinedButton.icon(
                  onPressed: () => _openUrl(
                    CampusSafeMapScreen.satelliteMapUri,
                    'Could not open Google Maps satellite view.',
                  ),
                  icon: const Icon(Icons.satellite_alt_outlined),
                  label: const Text('Open satellite view in Google Maps'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SafeCampusColors.forest,
                    side: const BorderSide(color: SafeCampusColors.gold),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: CampusSafeMapScreen.campus,
                    initialZoom: 16,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.safecampus_app',
                      errorTileCallback: (_, error, _) => _onTileError(error),
                    ),
                    MarkerLayer(
                      markers: [
                        for (final location in locations)
                          Marker(
                            point: location.position,
                            width: 48,
                            height: 48,
                            child: IconButton(
                              tooltip: location.name,
                              onPressed: () => _showLocation(location),
                              icon: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 38,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SimpleAttributionWidget(
                      source: const Text('OpenStreetMap contributors'),
                      onTap: () => _openUrl(
                        Uri.https('www.openstreetmap.org', '/copyright'),
                        'Could not open map attribution.',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Text(
                        'WSU Potsdam Campus · Safety locations',
                        style: TextStyle(
                          color: SafeCampusColors.forest,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (snapshot.hasError)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Could not load safety locations. Check your connection and try again.',
                        ),
                      )
                    else if (!snapshot.hasData)
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (locations.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No valid campus safety locations yet.'),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: locations.length,
                          itemBuilder: (context, index) {
                            final location = locations[index];
                            final details = [
                              location.type,
                              location.description,
                            ].where((value) => value.isNotEmpty).join(' · ');
                            return ListTile(
                              leading: const Icon(
                                Icons.location_on_outlined,
                                color: SafeCampusColors.green,
                              ),
                              title: Text(location.name),
                              subtitle: details.isEmpty ? null : Text(details),
                              trailing: const Icon(
                                Icons.open_in_new,
                                color: SafeCampusColors.gold,
                              ),
                              onTap: () => _openLocation(location),
                            );
                          },
                        ),
                      ),
                    if (invalidCount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          '$invalidCount location(s) have invalid coordinates. Contact the administrator.',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

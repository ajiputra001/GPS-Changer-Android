import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:geocoding/geocoding.dart';
import 'package:gps_mock/models/map_style.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/services/search_service.dart';
import 'package:gps_mock/ui/map_style_sheet.dart';
import 'package:gps_mock/ui/onboarding_dialog.dart';
import 'package:gps_mock/ui/permissions_sheet.dart';
import 'package:gps_mock/ui/route_panel.dart';
import 'package:gps_mock/ui/save_favorite_dialog.dart';
import 'package:gps_mock/ui/widgets/m3_segmented_control.dart';
import 'package:gps_mock/services/update_service.dart';
import 'package:gps_mock/ui/update_dialog.dart';
import 'package:gps_mock/utils/constants.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// The Map tab: full-screen map with the search bar on top and the mocking
/// control panel docked to the bottom.
class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => MapViewState();
}

class MapViewState extends State<MapView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimatedMapController _mapController = AnimatedMapController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    curve: Curves.easeInOut,
  );
  final SearchService _searchService = SearchService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _idleDebounce;
  int _handledCameraToken = 0;
  bool _mapReady = false;
  String _lastSearchQuery = '';
  bool _followRoute = true;
  LatLng? _lastFollowedPosition;
  double _rotation = 0;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  double _sheetExtent = .34;
  final NetworkTileProvider _tileProvider = NetworkTileProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<AppState>().isMockLocationApp == false) {
        showDialog(context: context, builder: (_) => const OnboardingDialog());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleDebounce?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AppState>().refreshMockLocationCheck();
    }
  }

  /// Public entry points so the root shell can drive the map from other tabs.
  void selectAndFly(LatLng target, String address) {
    final appState = context.read<AppState>();
    appState.updateLocation(target, address: address);
    _flyTo(target, 16);
  }

  void openDirections() {
    context.read<AppState>().setRouteMode(true);
  }

  // ----------------------------------------------------------- map camera

  void _flyTo(LatLng target, double zoom) {
    if (!_mapReady) return;
    _mapController.animateTo(dest: target, zoom: zoom);
  }

  void _handleCameraRequest(AppState appState) {
    // Only touch the controller after the map has actually rendered — using
    // it earlier throws "MapController used before FlutterMap built".
    if (!_mapReady) return;
    final request = appState.cameraRequest;
    if (request == null || request.token == _handledCameraToken) return;
    _handledCameraToken = request.token;
    final bounds = request.bounds;
    final target = request.target;
    if (bounds != null) {
      _mapController.animatedFitCamera(
        cameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(64),
        ),
      );
    } else if (target != null) {
      _mapController.animateTo(dest: target, zoom: request.zoom);
    }
  }

  void _handleFollowRoute(AppState appState) {
    if (!_mapReady || !appState.isNavigating || !_followRoute) return;
    final position = LatLng(
      appState.mockStatus.latitude,
      appState.mockStatus.longitude,
    );
    if (position == _lastFollowedPosition) return;
    _lastFollowedPosition = position;
    _mapController.animateTo(dest: position);
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (camera.rotation != _rotation) {
      setState(() => _rotation = camera.rotation);
    }
    if (!hasGesture) return;
    _idleDebounce?.cancel();
    _idleDebounce = Timer(const Duration(milliseconds: 500), () {
      _onCameraIdle(camera.center);
    });
  }

  Future<void> _onCameraIdle(LatLng center) async {
    if (!mounted) return;
    if (context.read<AppState>().isNavigating) return;

    String? address;
    try {
      final placemarks = await placemarkFromCoordinates(
        center.latitude,
        center.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        address = [
          p.street,
          p.locality,
        ].where((part) => part != null && part.isNotEmpty).join(', ');
        if (address.isEmpty) address = null;
      }
    } catch (_) {
      // Geocoding unavailable — fall back to coordinates.
    }

    if (mounted) {
      context.read<AppState>().updateLocation(center, address: address);
    }
  }

  void _resetNorth() {
    if (!_mapReady) return;
    _mapController.animatedRotateTo(0);
  }

  // ---------------------------------------------------------- map layers

  List<Polyline> _buildPolylines(AppState appState) {
    final points = appState.routePolylinePoints;
    if (points == null || (!appState.routeMode && !appState.isNavigating)) {
      return const [];
    }
    return [
      Polyline(
        points: points,
        strokeWidth: 5,
        color: Theme.of(context).colorScheme.primary,
      ),
    ];
  }

  List<Marker> _buildFavoriteMarkers(AppState appState, double zoom) {
    // Show saved locations on the map: small dots when zoomed out, labeled
    // pins when close in.
    if (appState.routeMode || appState.isNavigating) return const [];
    final labeled = zoom >= 12;
    return [
      for (final fav in appState.favorites)
        Marker(
          point: LatLng(fav.latitude, fav.longitude),
          width: labeled ? 120 : 16,
          height: labeled ? 52 : 16,
          alignment: labeled ? Alignment.topCenter : Alignment.center,
          child: labeled
              ? _LabeledFavoriteMarker(name: fav.name)
              : _FavoriteDot(color: Theme.of(context).colorScheme.tertiary),
        ),
    ];
  }

  List<Marker> _buildRouteMarkers(AppState appState) {
    final markers = <Marker>[];
    if (appState.routeMode || appState.isNavigating) {
      final origin = appState.routeOrigin;
      if (origin != null) {
        markers.add(_pinMarker(origin, Colors.green, "Route start"));
      }
      for (final stop in appState.routeStops) {
        markers.add(_pinMarker(stop.location, Colors.orange, "Stop"));
      }
      final destination = appState.routeDestination;
      if (destination != null) {
        markers.add(_pinMarker(destination, Colors.red, "Route destination"));
      }
    }
    if (appState.isNavigating) {
      final status = appState.mockStatus;
      markers.add(
        Marker(
          point: LatLng(status.latitude, status.longitude),
          width: 36,
          height: 36,
          child: Semantics(
            label: "Simulated position",
            child: Transform.rotate(
              angle: status.bearing * math.pi / 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 6),
                  ],
                ),
                child: const Icon(
                  Icons.navigation,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Marker _pinMarker(LatLng point, Color color, String label) {
    return Marker(
      point: point,
      width: 36,
      height: 36,
      alignment: Alignment.topCenter,
      child: Semantics(
        label: label,
        child: Icon(
          Icons.location_pin,
          size: 36,
          color: color,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 6)],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = MapStyle.resolve(appState.mapStyle, darkTheme: isDark);
    _handleCameraRequest(appState);
    _handleFollowRoute(appState);

    final zoom = _mapReady
        ? _mapController.mapController.camera.zoom
        : appState.mapStartZoom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        toolbarHeight: 68,
        title: _buildSearchBar(context),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController.mapController,
            options: MapOptions(
              initialCenter: appState.mapStartLocation,
              initialZoom: appState.mapStartZoom,
              minZoom: 2,
              maxZoom: style.maxZoom.toDouble(),
              onPositionChanged: _onPositionChanged,
              onMapReady: () {
                setState(() => _mapReady = true);
                _onCameraIdle(_mapController.mapController.camera.center);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: style.urlTemplate,
                subdomains: style.subdomains,
                maxNativeZoom: style.maxZoom,
                userAgentPackageName: AppConstants.tileUserAgentPackage,
                tileProvider: _tileProvider,
              ),
              PolylineLayer(polylines: _buildPolylines(appState)),
              MarkerLayer(markers: _buildFavoriteMarkers(appState, zoom)),
              MarkerLayer(markers: _buildRouteMarkers(appState)),
              _buildAttribution(style),
            ],
          ),
          if (!appState.isNavigating) _buildCenterPin(context),
          _buildTopOverlays(context, appState),
          _buildRightControls(context, appState),
          _buildBottomPanel(context, appState),
        ],
      ),
    );
  }

  Widget _buildAttribution(MapStyle style) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        // Sit just above the docked control panel.
        padding: const EdgeInsets.only(left: 6, bottom: 2),
        child: Container(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(
            style.attribution,
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterPin(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 46),
          child: Semantics(
            label: "Selected mock location pin",
            child: Icon(
              Icons.location_pin,
              size: 50,
              color: Theme.of(context).colorScheme.primary,
              shadows: const [Shadow(color: Colors.black38, blurRadius: 8)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopOverlays(BuildContext context, AppState appState) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 76,
      left: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWatermarkOverlay(context),
          const SizedBox(height: 8),
          if (appState.isMockLocationApp == false) ...[
            _buildSetupBanner(context),
            const SizedBox(height: 8),
          ],
          if (appState.isMocking)
            Align(
              alignment: Alignment.centerLeft,
              child: _buildMockingBadge(context, appState),
            ),
        ],
      ),
    );
  }

  Widget _buildWatermarkOverlay(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1E293B) : Colors.white).withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/images/logo.png',
              width: 18,
              height: 18,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.gps_fixed, size: 12),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Ajiputra-project GPS",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                "Dev: Ajiputra-tech • Builder: Agung maulana",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMockingBadge(BuildContext context, AppState appState) {
    final navigating = appState.isNavigating;
    return Semantics(
      liveRegion: true,
      label: navigating ? "Route simulation active" : "Location mocking active",
      child: Material(
        color: Colors.green.shade700,
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                navigating ? Icons.route : Icons.gps_fixed,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                navigating ? "SIMULATING ROUTE" : "MOCKING",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetupBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showDialog(
          context: context,
          builder: (_) => const OnboardingDialog(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Not set as mock location app — tap to fix",
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onErrorContainer,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- right rail

  Widget _buildRightControls(BuildContext context, AppState appState) {
    return Positioned(
      right: 12,
      top: MediaQuery.of(context).padding.top + 84,
      child: Column(
        children: [
          // Compass — appears once the map is rotated; tap to reset north.
          if (_rotation.abs() > 0.5)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MapButton(
                tooltip: "Reset north",
                onPressed: _resetNorth,
                child: Transform.rotate(
                  angle: _rotation * math.pi / 180,
                  child: const Icon(Icons.navigation, color: Colors.red),
                ),
              ),
            ),
          _MapButton(
            tooltip: "Map style",
            onPressed: () => MapStyleSheet.show(context),
            child: const Icon(Icons.layers_outlined),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ search bar

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Row(
        children: [
          Expanded(
            child: TypeAheadField<PlaceSuggestion>(
              controller: _searchController,
              debounceDuration: const Duration(milliseconds: 350),
              builder: (context, controller, focusNode) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: "Search places…",
                    border: InputBorder.none,
                    icon: const Icon(Icons.search),
                    suffixIcon: controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: "Clear search",
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              controller.clear();
                              setState(() {});
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                );
              },
              suggestionsCallback: (pattern) async {
                _lastSearchQuery = pattern.trim();
                if (_lastSearchQuery.length < 3) {
                  return const <PlaceSuggestion>[];
                }
                return _searchService.search(
                  pattern,
                  near: context.read<AppState>().currentLocation,
                );
              },
              loadingBuilder: (context) => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              emptyBuilder: (context) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _lastSearchQuery.length < 3
                      ? "Type at least 3 characters to search"
                      : "No places found",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              errorBuilder: (context, error) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Search failed — check your connection",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              itemBuilder: (context, suggestion) {
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(
                    suggestion.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: suggestion.description.isEmpty
                      ? null
                      : Text(
                          suggestion.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                );
              },
              onSelected: (suggestion) {
                final appState = context.read<AppState>();
                final address = suggestion.description.isEmpty
                    ? suggestion.name
                    : "${suggestion.name}, ${suggestion.description}";
                _searchController.text = suggestion.name;
                FocusScope.of(context).unfocus();
                appState.updateLocation(suggestion.location, address: address);
                _flyTo(suggestion.location, 16);
              },
            ),
          ),
          PopupMenuButton<String>(
            tooltip: "More options",
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'setup':
                  PermissionsSheet.show(context);
                case 'style':
                  MapStyleSheet.show(context);
                case 'settings':
                  context.read<AppState>().openSettings();
                case 'update':
                  _manualCheckUpdate(context);
                case 'about':
                  _showAbout(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'setup',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.checklist),
                  title: Text("Setup & permissions"),
                ),
              ),
              PopupMenuItem(
                value: 'style',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.layers_outlined),
                  title: Text("Map style"),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.developer_mode),
                  title: Text("Developer settings"),
                ),
              ),
              PopupMenuItem(
                value: 'update',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.system_update_rounded),
                  title: Text("Check for update"),
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text("About Ajiputra-project GPS"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _manualCheckUpdate(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Memeriksa pembaruan di GitHub..."),
        duration: Duration(seconds: 2),
      ),
    );
    final info = await UpdateService.checkLatestRelease();
    if (!context.mounted) return;
    if (info != null) {
      UpdateDialog.show(context, updateInfo: info, isForce: false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aplikasi Anda sudah versi terbaru! ✨")),
      );
    }
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: "Ajiputra-project GPS",
      applicationVersion: "1.0.0",
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          'assets/images/logo.png',
          width: 44,
          height: 44,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.location_pin, size: 40),
        ),
      ),
      children: const [
        Text(
          "Ajiputra-project GPS - Android Location Spoofing & Route Simulator.\n\n"
          "Developer: Ajiputra-tech\n"
          "Builder: Agung maulana\n\n"
          "Maps © OpenStreetMap contributors and free providers. "
          "Search by Photon, routing by OSRM.",
        ),
      ],
    );
  }

  // ------------------------------------------------------- bottom panel

  Future<void> _toggleMocking(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final appState = context.read<AppState>();
    final result = await appState.toggleMocking();
    if (!context.mounted) return;

    switch (result) {
      case MockToggleResult.needsSetup:
        showDialog(context: context, builder: (_) => const OnboardingDialog());
      case MockToggleResult.noLocation:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Move the map to pick a location first."),
          ),
        );
      case MockToggleResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appState.lastError ?? "Could not start mocking."),
          ),
        );
      case MockToggleResult.started:
        _announce("Location mocking started");
      case MockToggleResult.stopped:
        _announce("Location mocking stopped");
    }
  }

  void _announce(String message) {
    SemanticsService.sendAnnouncement(
        View.of(context), message, TextDirection.ltr);
  }

  void _copyCoordinates(BuildContext context, LatLng location) {
    final text = "${location.latitude.toStringAsFixed(6)}, "
        "${location.longitude.toStringAsFixed(6)}";
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Copied $text")),
    );
  }

  void _shareLocation(AppState appState) {
    final loc = appState.currentLocation;
    if (loc == null) return;
    SharePlus.instance.share(
      ShareParams(
        text: "${appState.currentAddress}\n"
            "${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}\n"
            "https://www.openstreetmap.org/?mlat=${loc.latitude}&mlon=${loc.longitude}#map=16/${loc.latitude}/${loc.longitude}",
        subject: "Location from GPS Mock",
      ),
    );
  }

  Widget _buildBottomPanel(BuildContext context, AppState appState) {
    final showRoutePanel = appState.routeMode || appState.isNavigating;
    final defaultExtent = showRoutePanel ? .68 : .48;
    const minExtent = .09;
    const maxExtent = .95;
    final isCollapsed = _sheetExtent < (minExtent + .08);

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        if ((_sheetExtent - notification.extent).abs() > .01) {
          setState(() => _sheetExtent = notification.extent);
        }
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: minExtent,
        minChildSize: minExtent,
        maxChildSize: maxExtent,
        snap: true,
        snapSizes: const [minExtent, .48, .68, maxExtent],
        snapAnimationDuration: const Duration(milliseconds: 240),
        builder: (context, scrollController) {
          return Material(
            elevation: 12,
            color: Theme.of(context).colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: CustomScrollView(
              controller: scrollController,
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: InkWell(
                    onTap: () {
                      final target = isCollapsed ? defaultExtent : minExtent;
                      _sheetController.animateTo(
                        target,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: .4),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (isCollapsed)
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_rounded,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    appState.currentAddress.isEmpty
                                        ? "Select location on map"
                                        : appState.currentAddress,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: 36,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _toggleMocking(context),
                                    icon: Icon(
                                      appState.isMocking
                                          ? Icons.stop_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    label: Text(
                                      appState.isMocking ? "STOP" : "START",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: appState.isMocking
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFF10B981),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: "Expand panel",
                                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 24),
                                  onPressed: () {
                                    _sheetController.animateTo(
                                      defaultExtent,
                                      duration: const Duration(milliseconds: 240),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!isCollapsed)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      2,
                      16,
                      32 + MediaQuery.of(context).padding.bottom,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: SafeArea(
                        top: false,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                if (appState.isNavigating)
                                  _buildFollowButton(context),
                                const Spacer(),
                                _MapButton(
                                  tooltip: "Go to my real location",
                                  onPressed: () => _goToMyLocation(context),
                                  child: const Icon(Icons.my_location),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  tooltip: "Collapse panel",
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                                  onPressed: () {
                                    _sheetController.animateTo(
                                      minExtent,
                                      duration: const Duration(milliseconds: 240),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            M3SegmentedControl<bool>(
                              options: const [
                                M3Segment(
                                  value: false,
                                  label: "Fixed",
                                  icon: Icons.location_on,
                                ),
                                M3Segment(
                                  value: true,
                                  label: "Route",
                                  icon: Icons.route,
                                ),
                              ],
                              selected: showRoutePanel,
                              onSelected: appState.isNavigating
                                  ? null
                                  : appState.setRouteMode,
                            ),
                            const SizedBox(height: 12),
                            if (showRoutePanel)
                              const RoutePanel()
                            else
                              _buildFixedControls(context, appState),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFollowButton(BuildContext context) {
    return _MapButton(
      tooltip: _followRoute
          ? "Stop following mock position"
          : "Follow mock position",
      highlighted: _followRoute,
      onPressed: () => setState(() {
        _followRoute = !_followRoute;
        _lastFollowedPosition = null;
      }),
      child: const Icon(Icons.navigation),
    );
  }

  Future<void> _goToMyLocation(BuildContext context) async {
    final moved = await context.read<AppState>().moveToRealLocation();
    if (!moved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't get your location. Check that location is enabled "
            "and permission is granted.",
          ),
        ),
      );
    }
  }

  Widget _buildFixedControls(BuildContext context, AppState appState) {
    final location = appState.currentLocation;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          appState.currentAddress,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        if (location != null)
          InkWell(
            onTap: () => _copyCoordinates(context, location),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF1E293B) : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF00B4D8)),
                  const SizedBox(width: 6),
                  Text(
                    "${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Text("—", style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: IconButton(
                tooltip: "Save as favorite",
                iconSize: 22,
                icon: const Icon(Icons.favorite_border_rounded),
                onPressed: location == null
                    ? null
                    : () => showDialog(
                          context: context,
                          builder: (_) => const SaveFavoriteDialog(),
                        ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: appState.isMocking
                        ? [const Color(0xFFDC2626), const Color(0xFFEF4444)]
                        : [const Color(0xFF059669), const Color(0xFF10B981)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (appState.isMocking
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF10B981))
                          .withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => _toggleMocking(context),
                  icon: Icon(
                    appState.isMocking ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  label: Text(
                    appState.isMocking ? "STOP MOCKING" : "START MOCKING",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: IconButton(
                tooltip: "Share location",
                iconSize: 22,
                icon: const Icon(Icons.share_rounded),
                onPressed: location == null ? null : () => _shareLocation(appState),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Round map control button with a consistent look.
class _MapButton extends StatelessWidget {
  final String tooltip;
  final Widget child;
  final VoidCallback onPressed;
  final bool highlighted;

  const _MapButton({
    required this.tooltip,
    required this.child,
    required this.onPressed,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: highlighted ? colorScheme.primaryContainer : colorScheme.surface,
      elevation: 3,
      shape: const CircleBorder(),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 44, height: 44, child: child),
        ),
      ),
    );
  }
}

class _FavoriteDot extends StatelessWidget {
  final Color color;
  const _FavoriteDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
      ),
    );
  }
}

class _LabeledFavoriteMarker extends StatelessWidget {
  final String name;
  const _LabeledFavoriteMarker({required this.name});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.star,
          size: 22,
          color: colorScheme.tertiary,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
        ),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/geo_service.dart';
import '../services/permission_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'design_components.dart';

const _osmTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _defaultCenter = LatLng(39.9042, 116.4074);
const _defaultZoom = 14.0;

/// Bottom-sheet map picker. Pops with the selected place label (String).
class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet({super.key});

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final _mapCtrl = MapController();
  final _geo = GeoService();
  final _queryCtrl = TextEditingController();

  LatLng _selected = _defaultCenter;
  String? _selectedLabel;
  bool _resolving = false;
  List<Place>? _results;
  String? _searchError;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _locateMe();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _locateMe() async {
    final granted = await PermissionService.ensureLocation();
    if (!granted || !mounted) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      _mapCtrl.move(LatLng(pos.latitude, pos.longitude), _defaultZoom);
    } catch (_) {
      // GPS unavailable — keep the default center.
    }
  }

  Future<void> _search() async {
    final q = _queryCtrl.text.trim();
    if (q.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final places = await _geo.searchPlaces(q);
      if (!mounted) return;
      setState(() {
        _results = places.isEmpty ? null : places;
        _searchError = places.isEmpty ? '未找到相关地点' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = null;
        _searchError = '搜索失败，请重试';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _clearResults() {
    setState(() {
      _results = null;
      _searchError = null;
    });
  }

  void _pickResult(Place p) {
    final point = LatLng(p.lat, p.lng);
    setState(() {
      _selected = point;
      _selectedLabel = p.label;
      _results = null;
      _searchError = null;
    });
    _mapCtrl.move(point, _defaultZoom);
  }

  Future<void> _pickPoint(LatLng point) async {
    setState(() {
      _selected = point;
      _selectedLabel = null;
      _resolving = true;
      _results = null;
      _searchError = null;
    });
    String? label;
    try {
      label = await _geo.reverseGeocode(point.latitude, point.longitude);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _resolving = false;
      _selectedLabel = label ??
          '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
    });
  }

  bool get _showOverlay => _searching || _results != null || _searchError != null;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: _selected,
                    initialZoom: _defaultZoom,
                    onTap: (_, point) => _pickPoint(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _osmTiles,
                      userAgentPackageName: 'com.soundpola.soundpola',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selected,
                          width: 44,
                          height: 44,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.location_on,
                            color: AppColors.accent,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Positioned(
                  right: 8,
                  bottom: 4,
                  child: Text(
                    '© OpenStreetMap',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 10),
                  ),
                ),
                if (_showOverlay) _buildResultsOverlay(),
              ],
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _queryCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜索地点',
                hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
                isDense: true,
                filled: true,
                fillColor: AppColors.surface1,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _search,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surface1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.input),
                side: const BorderSide(color: AppColors.border),
              ),
            ),
            icon: const Icon(Icons.search, color: AppColors.accent, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsOverlay() {
    return Positioned.fill(
      child: Material(
        color: AppColors.surface2,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '搜索结果',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    onPressed: _clearResults,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, color: AppColors.textTertiary, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderSubtle),
            Expanded(child: _buildResultsBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsBody() {
    if (_searching) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_searchError != null) {
      return Center(
        child: Text(
          _searchError!,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        ),
      );
    }
    final results = _results ?? const <Place>[];
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: results.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.borderSubtle),
      itemBuilder: (ctx, i) {
        final p = results[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.place_outlined, color: AppColors.accent),
          title: Text(
            p.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          ),
          onTap: () => _pickResult(p),
        );
      },
    );
  }

  Widget _buildFooter() {
    final confirmed = _selectedLabel != null && !_resolving;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _resolving
                ? '识别中…'
                : (_selectedLabel ?? '点按地图或搜索以选择地点'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: confirmed ? AppColors.textPrimary : AppColors.textTertiary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            text: '确认',
            onPressed: confirmed
                ? () => Navigator.pop(context, _selectedLabel)
                : null,
          ),
        ],
      ),
    );
  }
}

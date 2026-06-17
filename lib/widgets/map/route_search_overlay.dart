import 'package:flutter/material.dart';
import 'package:kh_map_app/models/place.dart';
import 'package:kh_map_app/models/route_search_selection.dart';
import 'package:latlong2/latlong.dart';

class RouteSearchOverlay extends StatefulWidget {
  const RouteSearchOverlay({
    super.key,
    required this.places,
    required this.currentLocation,
    required this.initialDestination,
    required this.onClose,
    required this.onSubmit,
    this.onRequestMapPick,
  });

  final List<Place> places;
  final LatLng currentLocation;
  final RouteSearchSelection initialDestination;
  final VoidCallback onClose;
  final Future<void> Function({
    required RouteSearchSelection origin,
    required RouteSearchSelection destination,
  })
  onSubmit;

  /// Called when the user wants to pick a location from the map.
  /// Receives a [onPicked] callback that should be called with the picked
  /// [RouteSearchSelection] once the user taps the map.
  final void Function(void Function(RouteSearchSelection) onPicked)?
  onRequestMapPick;

  @override
  State<RouteSearchOverlay> createState() => _RouteSearchOverlayState();
}

class _RouteSearchOverlayState extends State<RouteSearchOverlay> {
  late final TextEditingController _originCtrl;
  late final TextEditingController _destinationCtrl;

  late RouteSearchSelection _origin;
  late RouteSearchSelection _destination;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _origin = RouteSearchSelection(
      label: 'Current location',
      location: widget.currentLocation,
      useLiveCurrentLocation: true,
    );
    _destination = widget.initialDestination;
    _originCtrl = TextEditingController(text: _origin.label);
    _destinationCtrl = TextEditingController(text: _destination.label);
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destinationCtrl.dispose();
    super.dispose();
  }

  List<Place> _filterPlaces(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return widget.places.take(8).toList();
    return widget.places
        .where((p) => p.name.toLowerCase().contains(q))
        .take(8)
        .toList();
  }

  void _applySelection(RouteSearchSelection selected, bool isOrigin) {
    setState(() {
      if (isOrigin) {
        _origin = selected;
        _originCtrl.text = selected.label;
      } else {
        _destination = selected;
        _destinationCtrl.text = selected.label;
      }
    });
  }

  Future<void> _pickOrigin() async {
    final selected = await _showPlacePicker(
      title: 'Choose origin',
      includeCurrentLocation: true,
      initialQuery: _originCtrl.text,
    );
    if (selected == null) return;
    _applySelection(selected, true);
  }

  Future<void> _pickDestination() async {
    final selected = await _showPlacePicker(
      title: 'Choose destination',
      includeCurrentLocation: false,
      initialQuery: _destinationCtrl.text,
    );
    if (selected == null) return;
    _applySelection(selected, false);
  }

  void _pickOriginFromMap() {
    widget.onRequestMapPick?.call(
      (selection) => _applySelection(selection, true),
    );
  }

  void _pickDestinationFromMap() {
    widget.onRequestMapPick?.call(
      (selection) => _applySelection(selection, false),
    );
  }

  Future<RouteSearchSelection?> _showPlacePicker({
    required String title,
    required bool includeCurrentLocation,
    required String initialQuery,
  }) {
    return showModalBottomSheet<RouteSearchSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1D2538),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final queryController = TextEditingController(text: initialQuery);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = _filterPlaces(queryController.text);
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    TextField(
                      controller: queryController,
                      onChanged: (_) => setSheetState(() {}),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search places',
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white70,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF2B3448),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (includeCurrentLocation)
                            ListTile(
                              leading: const Icon(
                                Icons.my_location,
                                color: Colors.greenAccent,
                              ),
                              title: const Text(
                                'Current location',
                                style: TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '${widget.currentLocation.latitude.toStringAsFixed(6)}, '
                                '${widget.currentLocation.longitude.toStringAsFixed(6)}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              onTap: () {
                                Navigator.of(context).pop(
                                  RouteSearchSelection(
                                    label: 'Current location',
                                    location: widget.currentLocation,
                                    useLiveCurrentLocation: true,
                                  ),
                                );
                              },
                            ),
                          ...filtered.map((place) {
                            return ListTile(
                              leading: const Icon(
                                Icons.location_on,
                                color: Colors.orangeAccent,
                              ),
                              title: Text(
                                place.name,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                place.category?.name ?? 'Place',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              onTap: () {
                                Navigator.of(context).pop(
                                  RouteSearchSelection(
                                    label: place.name,
                                    location: LatLng(
                                      place.latitude,
                                      place.longitude,
                                    ),
                                  ),
                                );
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(origin: _origin, destination: _destination);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF102038),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Plan route',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.directions),
                    label: const Text('Go'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2D8CFF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _SearchFieldTile(
                controller: _originCtrl,
                icon: Icons.trip_origin,
                iconColor: Colors.greenAccent,
                onTap: _pickOrigin,
                onPickFromMap: widget.onRequestMapPick != null
                    ? _pickOriginFromMap
                    : null,
              ),
              const SizedBox(height: 8),
              _SearchFieldTile(
                controller: _destinationCtrl,
                icon: Icons.location_on,
                iconColor: Colors.orangeAccent,
                onTap: _pickDestination,
                onPickFromMap: widget.onRequestMapPick != null
                    ? _pickDestinationFromMap
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchFieldTile extends StatelessWidget {
  const _SearchFieldTile({
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.onPickFromMap,
  });

  final TextEditingController controller;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final VoidCallback? onPickFromMap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF233149),
          borderRadius: BorderRadius.circular(14),
        ),
        child: TextField(
          controller: controller,
          readOnly: true,
          onTap: onTap,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            prefixIcon: Icon(icon, color: iconColor),
            suffixIcon: onPickFromMap != null
                ? IconButton(
                    onPressed: onPickFromMap,
                    icon: const Icon(
                      Icons.pin_drop_outlined,
                      color: Colors.white54,
                    ),
                    tooltip: 'Pick from map',
                  )
                : const Icon(Icons.expand_more, color: Colors.white54),
          ),
        ),
      ),
    );
  }
}

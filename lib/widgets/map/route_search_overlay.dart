import 'package:flutter/material.dart';
import 'package:kh_map_app/models/place.dart';
import 'package:kh_map_app/models/route_search_selection.dart';
import 'package:kh_map_app/screens/search_screen.dart';
import 'package:latlong2/latlong.dart';

class RouteSearchOverlay extends StatefulWidget {
  const RouteSearchOverlay({
    super.key,
    required this.currentLocation,
    required this.initialDestination,
    required this.onClose,
    required this.onSubmit,
    this.onRequestMapPick,
    this.onSelectionChanged,
  });

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

  /// Fired whenever either field changes so the host can update the live
  /// preview pins on the map (numbered 1 = origin, 2 = destination).
  final void Function({required LatLng origin, required LatLng destination})?
  onSelectionChanged;

  @override
  State<RouteSearchOverlay> createState() => _RouteSearchOverlayState();
}

class _RouteSearchOverlayState extends State<RouteSearchOverlay> {
  late final TextEditingController _originCtrl;
  late final TextEditingController _destinationCtrl;

  late RouteSearchSelection _origin;
  late RouteSearchSelection _destination;

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
    widget.onSelectionChanged?.call(
      origin: _origin.location,
      destination: _destination.location,
    );
    // Re-fetch the plan immediately — no Go button.
    widget.onSubmit(origin: _origin, destination: _destination);
  }

  /// Pushes the full-screen [SearchScreen] and applies the returned [Place]
  /// to the matching field. No-op when the user backs out.
  Future<void> _pickViaSearchScreen({required bool isOrigin}) async {
    final picked = await Navigator.of(
      context,
    ).push<Place>(MaterialPageRoute(builder: (_) => const SearchScreen()));
    if (picked == null || !mounted) return;
    _applySelection(
      RouteSearchSelection(
        label: picked.name,
        location: LatLng(picked.latitude, picked.longitude),
      ),
      isOrigin,
    );
  }

  void _pickFromMap({required bool isOrigin}) {
    widget.onRequestMapPick?.call((selection) async {
      if (!mounted) return;
      final confirmed = await _confirmChangeLocation(isOrigin: isOrigin);
      if (!mounted || !confirmed) return;
      _applySelection(selection, isOrigin);
    });
  }

  /// Confirmation popup shown after the user taps the map in pick mode.
  /// Returning `false` (Cancel or dismiss) leaves the existing field value
  /// untouched.
  Future<bool> _confirmChangeLocation({required bool isOrigin}) async {
    final label = isOrigin ? 'origin' : 'destination';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change $label?'),
        content: Text("Do you want to change your $label's location?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _resetOriginToCurrentLocation() {
    _applySelection(
      RouteSearchSelection(
        label: 'Current location',
        location: widget.currentLocation,
        useLiveCurrentLocation: true,
      ),
      true,
    );
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
                ],
              ),
              const SizedBox(height: 8),
              _SearchFieldTile(
                controller: _originCtrl,
                icon: Icons.trip_origin,
                iconColor: Colors.greenAccent,
                onTap: () => _pickViaSearchScreen(isOrigin: true),
                onPickFromMap: widget.onRequestMapPick != null
                    ? () => _pickFromMap(isOrigin: true)
                    : null,
                onUseCurrentLocation: _origin.useLiveCurrentLocation
                    ? null
                    : _resetOriginToCurrentLocation,
              ),
              const SizedBox(height: 8),
              _SearchFieldTile(
                controller: _destinationCtrl,
                icon: Icons.location_on,
                iconColor: Colors.orangeAccent,
                onTap: () => _pickViaSearchScreen(isOrigin: false),
                onPickFromMap: widget.onRequestMapPick != null
                    ? () => _pickFromMap(isOrigin: false)
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
    this.onUseCurrentLocation,
  });

  final TextEditingController controller;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final VoidCallback? onPickFromMap;

  /// Optional shortcut (only used on the origin field) that snaps the value
  /// back to the user's live location. Hidden when the field already shows
  /// "Current location".
  final VoidCallback? onUseCurrentLocation;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (onUseCurrentLocation != null)
        IconButton(
          onPressed: onUseCurrentLocation,
          icon: const Icon(Icons.my_location, color: Colors.white54),
          tooltip: 'Use current location',
          visualDensity: VisualDensity.compact,
        ),
      if (onPickFromMap != null)
        IconButton(
          onPressed: onPickFromMap,
          icon: const Icon(Icons.pin_drop_outlined, color: Colors.white54),
          tooltip: 'Pick from map',
          visualDensity: VisualDensity.compact,
        ),
    ];

    final Widget suffix = actions.isEmpty
        ? const Icon(Icons.expand_more, color: Colors.white54)
        : Row(mainAxisSize: MainAxisSize.min, children: actions);

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
            suffixIcon: suffix,
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  Set<Marker> _markers = {};
  StreamSubscription<Position>? _positionSubscription;
  bool _locationError = false;
  bool _followUser = true;

  @override
  void initState() {
    super.initState();
    _initLocationTracking();
  }

  Future<void> _initLocationTracking() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      setState(() => _locationError = true);
      return;
    }

    // Get initial position
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.best),
      );
      print(
          '📍 Initial position: lat=${position.latitude}, lng=${position.longitude}');
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentPosition = latLng;
        _markers = {_buildCurrentLocationMarker(latLng)};
      });
    } catch (e) {
      print('📍 Error getting initial position: $e');
      setState(() => _locationError = true);
      return;
    }

    // Listen for continuous position updates
    late LocationSettings locationSettings;
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      );
    }

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((position) {
      print(
          '📍 Updated position: lat=${position.latitude}, lng=${position.longitude}');
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentPosition = latLng;
        _markers = {_buildCurrentLocationMarker(latLng)};
      });
      if (_followUser) {
        _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));
      }
    });
  }

  Marker _buildCurrentLocationMarker(LatLng position) {
    return Marker(
      markerId: const MarkerId('current_location'),
      position: position,
      infoWindow: const InfoWindow(title: 'You are here'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    );
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  void _centerOnUser() {
    if (_currentPosition != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(_currentPosition!),
      );
      setState(() => _followUser = true);
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_locationError) {
      return const Center(
        child: Text('Location permission is required to use the map.'),
      );
    }

    if (_currentPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentPosition!,
            zoom: 17,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          onCameraMoveStarted: () {
            // Stop auto-following when user manually drags the map
            setState(() => _followUser = false);
          },
        ),
        Positioned(
          bottom: 24,
          right: 16,
          child: FloatingActionButton(
            onPressed: _centerOnUser,
            backgroundColor: Colors.white,
            child: Icon(
              _followUser ? Icons.my_location : Icons.location_searching,
              color: _followUser ? Colors.blue : Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}

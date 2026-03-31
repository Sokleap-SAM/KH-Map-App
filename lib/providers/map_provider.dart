import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';

class MapProvider extends ChangeNotifier {
  final LocationService _locationService;

  MapProvider(this._locationService);

  LatLng? _currentPosition;
  bool _locationError = false;
  bool _followUser = true;
  StreamSubscription<LatLng>? _positionSub;

  LatLng? get currentPosition => _currentPosition;
  bool get locationError => _locationError;
  bool get followUser => _followUser;

  Future<void> init() async {
    final initial = await _locationService.getCurrentPosition();
    if (initial == null) {
      _locationError = true;
      notifyListeners();
      return;
    }

    _currentPosition = initial;
    notifyListeners();

    _positionSub = _locationService.positionStream.listen((latLng) {
      _currentPosition = latLng;
      notifyListeners();
    });
  }

  void setFollowUser(bool value) {
    if (_followUser == value) return;
    _followUser = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}

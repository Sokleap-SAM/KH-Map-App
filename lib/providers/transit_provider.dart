import 'dart:async';

import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/transit_service.dart';

class TransitProvider extends ChangeNotifier {
  final TransitService _service = TransitService();

  List<Trip> _trips = [];
  bool _loading = false;
  String? _error;
  Timer? _pollTimer;

  List<Trip> get trips => _trips;
  bool get loading => _loading;
  String? get error => _error;

  // Poll every 3 s while any trip is in-progress, 10 s otherwise.
  static const Duration _fastPoll = Duration(seconds: 3);
  static const Duration _slowPoll = Duration(seconds: 10);
  Duration _currentInterval = _slowPoll;

  /// Fetches active trips once and starts an adaptive poll cycle.
  /// Safe to call from [State.initState] — the first fetch is deferred
  /// via [Future.microtask] so it never fires during the build phase.
  Future<void> init() async {
    await Future.microtask(refresh);
    _schedulePoll();
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer(_currentInterval, () async {
      await refresh();
      _schedulePoll(); // reschedule so the interval can change dynamically
    });
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _trips = await _service.fetchActiveTrips();
      // Switch poll speed based on whether any bus is currently moving.
      final hasInProgress = _trips.any((t) => t.isInProgress);
      final desired = hasInProgress ? _fastPoll : _slowPoll;
      if (desired != _currentInterval) {
        _currentInterval = desired;
        // _schedulePoll is called after refresh() returns, so the next
        // timer will already use the updated interval.
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('TransitProvider: failed to refresh trips: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> startTrip(String id) async {
    try {
      await _service.startTrip(id);
      await refresh();
    } catch (e) {
      debugPrint('TransitProvider: failed to start trip $id: $e');
      rethrow;
    }
  }

  Future<void> advanceTrip(String id) async {
    try {
      await _service.advanceTrip(id);
      await refresh();
    } catch (e) {
      debugPrint('TransitProvider: failed to advance trip $id: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

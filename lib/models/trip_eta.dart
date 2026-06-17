/// Snapshot returned by `GET /transit/trips/:id/eta`. Fetched once on
/// detail-card open; subsequent ETA updates are computed locally from MQTT.
class TripEtaSnapshot {
  final String tripId;
  final int? etaSeconds;
  final int? etaMinutes;
  final int? notDepartingUntilMs;
  final bool isDwelling;
  final String? nextStopName;

  TripEtaSnapshot({
    required this.tripId,
    this.etaSeconds,
    this.etaMinutes,
    this.notDepartingUntilMs,
    this.isDwelling = false,
    this.nextStopName,
  });

  factory TripEtaSnapshot.fromJson(Map<String, dynamic> json) {
    final nextStop = json['nextStop'] as Map<String, dynamic>?;
    return TripEtaSnapshot(
      tripId: json['tripId'] as String,
      etaSeconds: (json['etaSeconds'] as num?)?.toInt(),
      etaMinutes: (json['etaMinutes'] as num?)?.toInt(),
      notDepartingUntilMs: (json['notDepartingUntilMs'] as num?)?.toInt(),
      isDwelling: (json['isDwelling'] as bool?) ?? false,
      nextStopName: nextStop?['name'] as String?,
    );
  }
}

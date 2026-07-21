import 'place.dart';

/// Snapshot returned by `GET /transit/trips/:id/eta`. Fetched once on
/// detail-card open; subsequent ETA updates are computed locally from MQTT.
class TripEtaSnapshot {
  final String tripId;
  final int? etaSeconds;
  final int? etaMinutes;
  final int? notDepartingUntilMs;
  final bool isDwelling;

  /// Khmer next-stop name (place `nameInKhmer`).
  final String? nextStopName;

  /// Latin next-stop name (place `nameInLatin`).
  final String? nextStopNameLatin;

  TripEtaSnapshot({
    required this.tripId,
    this.etaSeconds,
    this.etaMinutes,
    this.notDepartingUntilMs,
    this.isDwelling = false,
    this.nextStopName,
    this.nextStopNameLatin,
  });

  /// Next-stop name for the active language; null when unknown.
  String? localizedNextStopName(String languageCode) {
    if (nextStopName == null && nextStopNameLatin == null) return null;
    return localizedPlaceName(
      nextStopName ?? '',
      nextStopNameLatin,
      languageCode,
    );
  }

  factory TripEtaSnapshot.fromJson(Map<String, dynamic> json) {
    final nextStop = json['nextStop'] as Map<String, dynamic>?;
    return TripEtaSnapshot(
      tripId: json['tripId'] as String,
      etaSeconds: (json['etaSeconds'] as num?)?.toInt(),
      etaMinutes: (json['etaMinutes'] as num?)?.toInt(),
      notDepartingUntilMs: (json['notDepartingUntilMs'] as num?)?.toInt(),
      isDwelling: (json['isDwelling'] as bool?) ?? false,
      nextStopName:
          (nextStop?['nameInKhmer'] ?? nextStop?['nameInLatin']) as String?,
      nextStopNameLatin: nextStop?['nameInLatin'] as String?,
    );
  }
}

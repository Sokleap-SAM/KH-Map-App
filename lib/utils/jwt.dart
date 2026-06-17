import 'dart:convert';

/// Decodes a JWT *payload* (claims section) without verifying the signature.
/// We rely on the backend to enforce role; the client only reads it to pick
/// which shell to render.
Map<String, dynamic>? decodeJwtPayload(String? token) {
  if (token == null || token.isEmpty) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    var payload = parts[1];
    payload = payload.padRight(payload.length + (4 - payload.length % 4) % 4, '=');
    final decoded = utf8.decode(base64Url.decode(payload));
    final json = jsonDecode(decoded);
    if (json is Map<String, dynamic>) return json;
    return null;
  } catch (_) {
    return null;
  }
}

String? roleFromToken(String? token) {
  final claims = decodeJwtPayload(token);
  if (claims == null) return null;
  return claims['role'] as String?;
}

String? userIdFromToken(String? token) {
  final claims = decodeJwtPayload(token);
  if (claims == null) return null;
  return (claims['sub'] ?? claims['_id'] ?? claims['userId']) as String?;
}

/// Best-effort extraction of the driver's assigned bus id from JWT claims.
/// Backend may name it `assignedBus`, `assignedBusId`, `bus`, or `busId`.
/// Returns null if absent (then we must fall back to an HTTP source).
String? assignedBusFromToken(String? token) {
  final claims = decodeJwtPayload(token);
  if (claims == null) return null;
  final raw = claims['assignedBus'] ??
      claims['assignedBusId'] ??
      claims['bus'] ??
      claims['busId'];
  if (raw is Map) return raw['_id'] as String?;
  if (raw is String && raw.isNotEmpty) return raw;
  return null;
}

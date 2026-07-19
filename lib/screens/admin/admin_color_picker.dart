import 'package:flutter/material.dart';

/// Parse a backend route `color` string (`#RRGGBB`, `RRGGBB`, or `#AARRGGBB`)
/// into a [Color]. Returns null when absent/invalid so callers can fall back.
Color? routeColorFromHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h'; // assume opaque
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// `#RRGGBB` for a [Color] (uses the 0–1 component API).
String colorToHex(Color c) {
  int to255(double v) => (v * 255).round().clamp(0, 255);
  String h(int v) => v.toRadixString(16).padLeft(2, '0');
  return '#${h(to255(c.r))}${h(to255(c.g))}${h(to255(c.b))}'.toUpperCase();
}

/// Opens a free RGB/HSV color picker. Returns the chosen `#RRGGBB` string, or
/// null if cancelled.
Future<String?> showRouteColorPicker(
  BuildContext context, {
  String? initialHex,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ColorPickerDialog(
      initial: routeColorFromHex(initialHex) ?? const Color(0xFF2196F3),
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _ColorPickerDialog({required this.initial});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexCtrl = TextEditingController(text: colorToHex(widget.initial));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  /// Push the current color into the hex field (after slider moves), keeping
  /// the caret at the end so it doesn't jump around.
  void _syncHexField() {
    final hex = colorToHex(_color);
    _hexCtrl.value = TextEditingValue(
      text: hex,
      selection: TextSelection.collapsed(offset: hex.length),
    );
  }

  /// Parse a typed hex string; update the picker when it's valid.
  void _onHexTyped(String v) {
    final c = routeColorFromHex(v);
    if (c != null) setState(() => _hsv = HSVColor.fromColor(c));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ជ្រើសរើសពណ៌ (Pick color)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Saturation (x) / Value (y) area.
          LayoutBuilder(
            builder: (context, constraints) {
              const h = 170.0;
              final w = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (d) => _updateSV(d.localPosition, w, h),
                onPanUpdate: (d) => _updateSV(d.localPosition, w, h),
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    children: [
                      // base hue → white horizontally
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white,
                              HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                            ],
                          ),
                        ),
                      ),
                      // transparent → black vertically
                      Container(
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                      Positioned(
                        left: (_hsv.saturation * w - 8).clamp(0.0, w - 16),
                        top: ((1 - _hsv.value) * h - 8).clamp(0.0, h - 16),
                        child: _thumb(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Hue slider.
          LayoutBuilder(
            builder: (context, constraints) {
              const h = 24.0;
              final w = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (d) => _updateHue(d.localPosition.dx, w),
                onPanUpdate: (d) => _updateHue(d.localPosition.dx, w),
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF0000),
                              Color(0xFFFFFF00),
                              Color(0xFF00FF00),
                              Color(0xFF00FFFF),
                              Color(0xFF0000FF),
                              Color(0xFFFF00FF),
                              Color(0xFFFF0000),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: (_hsv.hue / 360 * w - 8).clamp(0.0, w - 16),
                        top: 4,
                        child: _thumb(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hexCtrl,
                  onChanged: _onHexTyped,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                  decoration: const InputDecoration(
                    labelText: 'Hex',
                    hintText: '#RRGGBB',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('បោះបង់'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(colorToHex(_color)),
          child: const Text('យល់ព្រម'),
        ),
      ],
    );
  }

  Widget _thumb() => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2)],
    ),
  );

  void _updateSV(Offset p, double w, double h) {
    setState(() {
      _hsv = _hsv
          .withSaturation((p.dx / w).clamp(0.0, 1.0))
          .withValue((1 - p.dy / h).clamp(0.0, 1.0));
    });
    _syncHexField();
  }

  void _updateHue(double dx, double w) {
    setState(() => _hsv = _hsv.withHue((dx / w * 360).clamp(0.0, 360.0)));
    _syncHexField();
  }
}

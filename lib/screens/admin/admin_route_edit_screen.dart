import 'package:flutter/material.dart';

import '../../models/admin_route.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';
import 'admin_color_picker.dart';

/// Edit a route's metadata (name, code, color, loop/direction, status).
/// Does NOT touch stops or segments. Pops the updated [AdminRoute] on success,
/// or null if cancelled.
class AdminRouteEditScreen extends StatefulWidget {
  final AdminRoute route;
  const AdminRouteEditScreen({super.key, required this.route});

  @override
  State<AdminRouteEditScreen> createState() => _AdminRouteEditScreenState();
}

class _AdminRouteEditScreenState extends State<AdminRouteEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late bool _isLine;
  late String _direction;
  late String _color;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.route;
    _nameCtrl = TextEditingController(text: r.name ?? '');
    _codeCtrl = TextEditingController(text: r.code ?? '');
    _isLine = r.isLine;
    _direction = r.direction ?? 'outbound';
    _color = r.color ?? '#2196F3';
    _status = r.status == 'inactive' ? 'inactive' : 'active';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('សូមបញ្ចូលឈ្មោះផ្លូវ (Route name required)')),
      );
      return;
    }
    final code = _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim();
    final direction = _isLine ? null : _direction;
    setState(() => _saving = true);
    try {
      await AdminService().updateRoute(
        widget.route.id,
        name: name,
        code: code,
        color: _color,
        isLine: _isLine,
        direction: direction,
        status: _status,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('បានរក្សាទុក (Saved)')),
      );
      Navigator.of(context).pop(
        AdminRoute(
          id: widget.route.id,
          name: name,
          code: code,
          isLine: _isLine,
          status: _status,
          stopCount: widget.route.stopCount,
          color: _color,
          direction: direction,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e is AdminApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('បរាជ័យ: $msg')));
    }
  }

  Widget _directionOption({
    required String value,
    required IconData icon,
    required String label,
  }) {
    final selected = _direction == value;
    final fg = selected ? Colors.white : AppColors.primaryColor;
    return Material(
      color: selected ? AppColors.secondaryColor : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _direction = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.secondaryColor : Colors.grey.shade400,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('កែផ្លូវ (Edit route)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'ឈ្មោះផ្លូវ (Name)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeCtrl,
            decoration: const InputDecoration(
              labelText: 'កូដ (Code, optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('សកម្ម (Active)'),
            subtitle: Text(_status == 'active'
                ? 'បង្ហាញ & ដំណើរការ (active)'
                : 'បិទ (inactive)'),
            value: _status == 'active',
            onChanged: (v) => setState(() => _status = v ? 'active' : 'inactive'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('រង្វង់ / Loop (circular)'),
            subtitle: Text(_isLine
                ? 'ចំណតចេញ = ចំណតចុង (departure === terminal)'
                : 'បន្ទាត់មានទិសដៅ (directional line)'),
            value: _isLine,
            onChanged: (v) => setState(() => _isLine = v),
          ),
          if (!_isLine) ...[
            const SizedBox(height: 8),
            const Text('ទិសដៅ (Direction)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _directionOption(
                    value: 'outbound',
                    icon: Icons.arrow_forward,
                    label: 'Outbound',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _directionOption(
                    value: 'inbound',
                    icon: Icons.arrow_back,
                    label: 'Inbound',
                  ),
                ),
              ],
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ពណ៌ផ្លូវ (Route color)'),
            subtitle: Text(_color),
            trailing: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: routeColorFromHex(_color) ?? Colors.blue,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black26),
              ),
            ),
            onTap: () async {
              final picked =
                  await showRouteColorPicker(context, initialHex: _color);
              if (picked != null) setState(() => _color = picked);
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('រក្សាទុក (Save)',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ),
    );
  }
}

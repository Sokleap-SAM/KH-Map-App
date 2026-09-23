import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bus.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';

/// Create or edit a bus.
///
/// `assignedDriverId` is deliberately absent from this form — the assignment
/// endpoint owns it, because it has to write both sides of the relation. Change
/// a bus's driver from the fleet list instead.
class AdminBusEditScreen extends StatefulWidget {
  final Bus? existing;
  const AdminBusEditScreen({super.key, this.existing});

  bool get isEdit => existing != null;

  @override
  State<AdminBusEditScreen> createState() => _AdminBusEditScreenState();
}

class _AdminBusEditScreenState extends State<AdminBusEditScreen> {
  final AdminService _service = AdminService();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _busNumberCtrl = TextEditingController();
  final TextEditingController _plateCtrl = TextEditingController();
  final TextEditingController _capacityCtrl = TextEditingController();

  late String _status;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _busNumberCtrl.text = e?.busNumber ?? '';
    _plateCtrl.text = e?.licensePlate ?? '';
    _capacityCtrl.text = e == null ? '' : '${e.capacity}';
    _status = e?.status ?? BusStatuses.inService;
  }

  @override
  void dispose() {
    _busNumberCtrl.dispose();
    _plateCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = context.read<SettingsProvider>().t;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final capacity = int.parse(_capacityCtrl.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (widget.isEdit) {
        final e = widget.existing!;
        final busNumber = _busNumberCtrl.text.trim();
        final plate = _plateCtrl.text.trim();
        // Send only what changed — re-sending an unchanged busNumber would
        // otherwise collide with this bus's own unique index on some backends.
        await _service.updateBus(
          e.id,
          busNumber: busNumber == e.busNumber ? null : busNumber,
          licensePlate: plate == e.licensePlate ? null : plate,
          capacity: capacity == e.capacity ? null : capacity,
          status: _status == e.status ? null : _status,
        );
      } else {
        await _service.createBus(
          busNumber: _busNumberCtrl.text.trim(),
          licensePlate: _plateCtrl.text.trim(),
          capacity: capacity,
          status: _status,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // busNumber and licensePlate are unique indexes, and a collision comes
        // back as a raw Mongo E11000 rather than a friendly 409.
        _error = AdminService.isDuplicateKey(e)
            ? t.duplicateBusKey
            : (e is AdminApiException ? e.message : e.toString());
      });
    }
  }

  String _statusLabel(AppTexts t, String status) => switch (status) {
        BusStatuses.inService => t.busStatusInService,
        BusStatuses.outOfService => t.busStatusOutOfService,
        BusStatuses.maintenance => t.busStatusMaintenance,
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(widget.isEdit ? t.editBus : t.createBus),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            TextFormField(
              controller: _busNumberCtrl,
              decoration: InputDecoration(
                labelText: t.busNumberField,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? t.busNumberRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plateCtrl,
              decoration: InputDecoration(
                labelText: t.licensePlateField,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? t.licensePlateRequired
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _capacityCtrl,
              decoration: InputDecoration(
                labelText: t.capacityField,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                return (n == null || n <= 0) ? t.capacityInvalid : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(
                labelText: t.statusField,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final s in BusStatuses.all)
                  DropdownMenuItem(
                    value: s,
                    child: Text(_statusLabel(t, s)),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (v) =>
                      setState(() => _status = v ?? BusStatuses.inService),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(widget.isEdit ? t.save : t.create),
            ),
          ],
        ),
      ),
    );
  }
}

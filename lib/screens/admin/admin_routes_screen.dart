import 'package:flutter/material.dart';

import '../../models/admin_route.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';
import 'admin_route_create_screen.dart';
import 'admin_route_detail_screen.dart';

/// Admin route list. Columns per the brief: name, code, isLine, status,
/// stop count. FAB opens the map-driven create flow.
class AdminRoutesScreen extends StatefulWidget {
  const AdminRoutesScreen({super.key});

  @override
  State<AdminRoutesScreen> createState() => _AdminRoutesScreenState();
}

class _AdminRoutesScreenState extends State<AdminRoutesScreen> {
  final AdminService _service = AdminService();
  List<AdminRoute> _routes = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final routes = await _service.fetchAllRoutes();
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AdminApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openCreate() async {
    final newRouteId = await Navigator.of(context).push<String?>(
      MaterialPageRoute(builder: (_) => const AdminRouteCreateScreen()),
    );
    if (newRouteId == null) return;
    await _load();
    // Land on the new route's detail, per the brief.
    if (!mounted) return;
    AdminRoute? match;
    for (final r in _routes) {
      if (r.id == newRouteId) {
        match = r;
        break;
      }
    }
    if (match != null) _openDetail(match);
  }

  Future<void> _openDetail(AdminRoute r) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminRouteDetailScreen(routeId: r.id, summary: r),
      ),
    );
    if (changed == true) _load();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'draft':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('គ្រប់គ្រងផ្លូវ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin_routes_fab',
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: Colors.white,
        onPressed: _openCreate,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('បង្កើតផ្លូវ'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _routes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _routes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('ព្យាយាមម្ដងទៀត')),
            ],
          ),
        ),
      );
    }
    if (_routes.isEmpty) {
      return const Center(child: Text('មិនទាន់មានផ្លូវ'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _routes.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = _routes[i];
          final title = [
            if (r.code != null && r.code!.isNotEmpty) r.code,
            r.name ?? 'Unnamed',
          ].join('  ');
          return ListTile(
            leading: Icon(
              r.isLine ? Icons.linear_scale : Icons.loop,
              color: AppColors.primaryColor,
            ),
            title: Text(title),
            subtitle: Text(
              '${r.isLine ? 'Line' : 'Circular'} · '
              '${r.stopCount != null ? '${r.stopCount} stops' : '— stops'}',
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(r.status),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                r.status,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            onTap: () => _openDetail(r),
          );
        },
      ),
    );
  }
}

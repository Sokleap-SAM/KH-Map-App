import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/favorite_route.dart';
import '../../services/favorite_routes_service.dart';
import '../../utils/constants/colors.dart';
import '../map/route_info_card.dart' show RouteOptionDetails;

/// Result returned from [FavoriteRouteSheet] via [Navigator.pop] for removal.
/// The "Go" action instead pops the loaded [FavoriteRouteLive] object.
const String kFavRouteSheetRemove = 'remove';

/// Detail sheet for one saved transit route. Fetches a freshly-rebuilt option
/// from GET /transit/favorites/:id/live on open and renders it with the same
/// [RouteOptionDetails] widget the live routing flow uses. Pops with
/// [kFavRouteSheetRemove] when the user removes the route.
class FavoriteRouteSheet extends StatefulWidget {
  final FavoriteRoute favorite;

  const FavoriteRouteSheet({super.key, required this.favorite});

  @override
  State<FavoriteRouteSheet> createState() => _FavoriteRouteSheetState();
}

class _FavoriteRouteSheetState extends State<FavoriteRouteSheet> {
  final FavoriteRoutesService _service = FavoriteRoutesService();

  FavoriteRouteLive? _live;
  bool _loading = true;
  String? _error;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _stale = false;
    });
    try {
      final live = await _service.fetchLive(widget.favorite.id);
      if (!mounted) return;
      setState(() {
        _live = live;
        _loading = false;
      });
    } on FavoriteRouteStaleException {
      if (!mounted) return;
      setState(() {
        _stale = true;
        _loading = false;
      });
    } on FavoriteRouteUnavailableException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'មិនអាចទាញយកផ្លូវបានទេ';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.66,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              _dragHandle(),
              _header(),
              _goButton(),
              const Divider(color: Color(0xFF2A2A2A), height: 1),
              _content(),
              const SizedBox(height: 28),
            ],
          ),
        );
      },
    );
  }

  Widget _dragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 10),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _header() {
    final fav = widget.favorite;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.secondaryColor.withAlpha(40),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.directions_bus_rounded,
              color: AppColors.secondaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fav.displayTitle,
                  style: GoogleFonts.notoSansKhmer(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${fav.origin.name}  →  ${fav.destination.name}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKhmer(
                    color: Colors.white54,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'លុបចេញ',
            onPressed: () => Navigator.of(context).pop(kFavRouteSheetRemove),
            icon: const Icon(
              Icons.bookmark_remove_outlined,
              color: AppColors.alertBorderColor,
            ),
          ),
          IconButton(
            tooltip: 'បិទ',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _goButton() {
    final live = _live;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          // Enabled only once the live route loads — we navigate with that exact
          // option so the map shows just this saved route (not re-planned).
          onPressed: live == null ? null : () => Navigator.of(context).pop(live),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.secondaryColor,
            foregroundColor: AppColors.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          icon: const Icon(Icons.navigation_rounded, size: 18),
          label: Text(
            'ចង្អុលផ្លូវ',
            style: GoogleFonts.notoSansKhmer(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.secondaryColor),
        ),
      );
    }
    if (_stale) {
      return _message(
        icon: Icons.update_disabled_rounded,
        title: 'ផ្លូវនេះលែងមានសុពលភាព',
        subtitle: 'ខ្សែរត់ ឬចំណតបានផ្លាស់ប្តូរ។ សូមស្វែងរក និងរក្សាទុកឡើងវិញ។',
      );
    }
    if (_error != null) {
      return _message(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        actionLabel: 'ព្យាយាមម្ដងទៀត',
        onAction: _load,
      );
    }
    final live = _live;
    if (live == null) {
      return _message(
        icon: Icons.error_outline,
        title: 'មិនមានទិន្នន័យផ្លូវ',
      );
    }
    return RouteOptionDetails(option: live.option);
  }

  Widget _message({
    required IconData icon,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: Column(
        children: [
          Icon(icon, size: 44, color: AppColors.secondaryColor),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKhmer(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKhmer(
                color: Colors.white54,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondaryColor,
                foregroundColor: AppColors.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Text(
                actionLabel,
                style: GoogleFonts.notoSansKhmer(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

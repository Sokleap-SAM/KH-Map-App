import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/favorite_route.dart';
import '../../models/route_plan.dart';
import '../../providers/settings_provider.dart';
import '../../services/transit_service.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import '../map/route_info_card.dart' show RouteOptionDetails;

/// Results returned from [FavoriteRouteSheet] via [Navigator.pop].
const String kFavRouteSheetRemove = 'remove';
const String kFavRouteSheetGo = 'go';

/// Detail sheet for one saved transit route. The backend stores only the
/// endpoints, so this previews the journey by re-planning origin → destination
/// through `/transit/plan` and showing the fastest option. "Go" hands the same
/// endpoints to the map's routing flow. Pops with [kFavRouteSheetRemove] when
/// the user removes the route, or [kFavRouteSheetGo] to open it on the map.
class FavoriteRouteSheet extends StatefulWidget {
  final FavoriteRoute favorite;

  const FavoriteRouteSheet({super.key, required this.favorite});

  @override
  State<FavoriteRouteSheet> createState() => _FavoriteRouteSheetState();
}

class _FavoriteRouteSheetState extends State<FavoriteRouteSheet> {
  final TransitService _transit = TransitService();

  RoutePlanResult? _plan;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final fav = widget.favorite;
      final plan = await _transit.fetchRoutePlan(
        originLat: fav.origin.coordinates.latitude,
        originLng: fav.origin.coordinates.longitude,
        destLat: fav.destination.coordinates.latitude,
        destLng: fav.destination.coordinates.longitude,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
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
              _header(t),
              _goButton(t),
              const Divider(color: Color(0xFF2A2A2A), height: 1),
              _content(t),
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

  Widget _header(AppTexts t) {
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
            tooltip: t.remove,
            onPressed: () => Navigator.of(context).pop(kFavRouteSheetRemove),
            icon: const Icon(
              Icons.bookmark_remove_outlined,
              color: AppColors.alertBorderColor,
            ),
          ),
          IconButton(
            tooltip: t.close,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _goButton(AppTexts t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(kFavRouteSheetGo),
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
            t.showDirections,
            style: GoogleFonts.notoSansKhmer(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(AppTexts t) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.secondaryColor),
        ),
      );
    }
    if (_hasError) {
      return _message(
        icon: Icons.cloud_off_rounded,
        title: t.couldNotLoadRoute,
        actionLabel: t.tryAgain,
        onAction: _load,
      );
    }
    final plan = _plan;
    if (plan == null || !plan.found || plan.options.isEmpty) {
      return _message(
        icon: Icons.wrong_location_outlined,
        title: plan?.message ?? t.noRouteForLocation,
      );
    }
    // Preview the fastest option; the full set of alternatives is available
    // after tapping "Go".
    return RouteOptionDetails(option: plan.options.first);
  }

  Widget _message({
    required IconData icon,
    required String title,
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
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondaryColor,
                foregroundColor: AppColors.primaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
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

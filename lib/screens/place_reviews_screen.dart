import 'package:flutter/material.dart';
import 'package:kh_map_app/models/place.dart';
import 'package:kh_map_app/models/place_rating.dart';
import 'package:kh_map_app/providers/settings_provider.dart';
import 'package:kh_map_app/services/place_service.dart';
import 'package:kh_map_app/utils/auth_guard.dart';
import 'package:kh_map_app/widgets/map_screen/write_review_sheet.dart';
import 'package:provider/provider.dart';

/// Full list of reviews for a place: every rating, comment and the photos each
/// reviewer attached. Pushed from the "Rating" row of the place detail sheet.
class PlaceReviewsScreen extends StatefulWidget {
  final Place place;

  const PlaceReviewsScreen({super.key, required this.place});

  @override
  State<PlaceReviewsScreen> createState() => _PlaceReviewsScreenState();
}

class _PlaceReviewsScreenState extends State<PlaceReviewsScreen> {
  static const _bgColor = Color(0xFF1E1E1E);
  static const _surfaceColor = Color(0xFF2D2D2D);
  static const _dividerColor = Color(0xFF333333);

  final PlaceService _service = PlaceService();
  late Future<List<PlaceRating>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchRatings(widget.place.id);
  }

  void _reload() {
    setState(() => _future = _service.fetchRatings(widget.place.id));
  }

  Future<void> _openWriteReview() async {
    // A guest's rating never reaches the backend, so require sign-in first and
    // route them through the login page rather than silently dropping it.
    if (!await ensureLoggedIn(context)) return;
    if (!mounted) return;
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WriteReviewSheet(place: widget.place),
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(context.read<SettingsProvider>().t.reviewPosted),
        ),
      );
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final t = settings.t;
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.reviews,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              widget.place.localizedName(settings.languageCode),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openWriteReview,
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.rate_review_outlined),
        label: Text(t.writeReview),
      ),
      body: FutureBuilder<List<PlaceRating>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            );
          }
          if (snapshot.hasError) {
            return _errorState();
          }
          final reviews = snapshot.data ?? const <PlaceRating>[];
          if (reviews.isEmpty) {
            return _emptyState();
          }
          return RefreshIndicator(
            color: Colors.white,
            backgroundColor: _surfaceColor,
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: reviews.length + 1,
              separatorBuilder: (_, i) => i == 0
                  ? const SizedBox.shrink()
                  : const Divider(color: _dividerColor, height: 1, indent: 16, endIndent: 16),
              itemBuilder: (_, i) {
                if (i == 0) return _summaryHeader(reviews);
                return _ReviewTile(review: reviews[i - 1]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _summaryHeader(List<PlaceRating> reviews) {
    // Compute from the loaded reviews so the header stays correct right after a
    // new review is posted (the passed-in place aggregate would be stale).
    final avg = reviews.isEmpty
        ? 0.0
        : reviews.map((r) => r.score).reduce((a, b) => a + b) / reviews.length;
    final count = reviews.length;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                avg.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              _StarRow(rating: avg, size: 16),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.watch<SettingsProvider>().t.reviewsCount(count),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.watch<SettingsProvider>().t.whatPeopleSaying,
                  style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final t = context.watch<SettingsProvider>().t;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.rate_review_outlined, size: 56, color: Colors.white24),
          const SizedBox(height: 14),
          Text(
            t.noReviewsYet,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.beFirstToReview,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    final t = context.watch<SettingsProvider>().t;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 56, color: Colors.white24),
          const SizedBox(height: 14),
          Text(
            t.couldNotLoadReviews,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white30),
            ),
            label: Text(t.tryAgain),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final PlaceRating review;

  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(initial: review.initial),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userName,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StarRow(rating: review.score, size: 14),
                        const SizedBox(width: 8),
                        Text(
                          review.createdAt == null
                              ? ''
                              : context
                                  .watch<SettingsProvider>()
                                  .t
                                  .timeAgo(review.createdAt!),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review.comment != null) ...[
            const SizedBox(height: 12),
            Text(
              review.comment!,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Colors.white70,
              ),
            ),
          ],
          if (review.photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PhotoStrip(photos: review.photos),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initial;
  const _Avatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFF3B82F6),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  final List<String> photos;
  const _PhotoStrip({required this.photos});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _openViewer(context, i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              photos[i],
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      width: 96,
                      height: 96,
                      color: const Color(0xFF2D2D2D),
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
              errorBuilder: (_, _, _) => Container(
                width: 96,
                height: 96,
                color: const Color(0xFF2D2D2D),
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined,
                    color: Colors.white30),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PhotoViewer(photos: photos, initialIndex: initialIndex),
      ),
    );
  }
}

/// Full-screen, swipeable, pinch-to-zoom viewer for a review's photos.
class _PhotoViewer extends StatelessWidget {
  final List<String> photos;
  final int initialIndex;

  const _PhotoViewer({required this.photos, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: photos.length,
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.network(
              photos[i],
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white30,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  static const _starColor = Color(0xFFFFB400);
  final double rating;
  final double size;

  const _StarRow({required this.rating, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.round();
        return Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: _starColor,
        );
      }),
    );
  }
}

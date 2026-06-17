import 'package:flutter/material.dart';

import '../../models/place.dart';

class PlaceDetailSheet extends StatelessWidget {
  const PlaceDetailSheet({
    super.key,
    required this.place,
    required this.onDirections,
  });

  final Place place;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            place.id.toString(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(place.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Category: ${place.category?.name ?? 'Uncategorized'}'),
          Text('Rating: ${place.averageRating?.toStringAsFixed(1) ?? 'N/A'}'),
          if (place.photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: place.photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    place.photos[i],
                    width: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onDirections();
              },
              icon: const Icon(Icons.directions),
              label: const Text('Directions'),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class LocateMeButton extends StatelessWidget {
  const LocateMeButton({
    super.key,
    required this.isLoading,
    required this.followUser,
    required this.onPressed,
  });

  final bool isLoading;
  final bool followUser;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 6),
                  Text('Loading places...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          FloatingActionButton(
            heroTag: 'locate_me',
            onPressed: onPressed,
            backgroundColor: Colors.white,
            child: Icon(
              followUser ? Icons.my_location : Icons.location_searching,
              color: followUser ? Colors.blue : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

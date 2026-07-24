import 'package:flutter/material.dart';

import '../../utils/theme/app_palette.dart';

/// Pulsing "you are here" indicator used at the active stop in a route
/// stop timeline. Shared by the rider map sheet and the driver trip detail.
class BusPulseIndicator extends StatefulWidget {
  const BusPulseIndicator({super.key});

  @override
  State<BusPulseIndicator> createState() => _BusPulseIndicatorState();
}

class _BusPulseIndicatorState extends State<BusPulseIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // The growing "Radar" ring
            Container(
              width: 12 + (24 * _controller.value),
              height: 12 + (24 * _controller.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(
                  0xFF1976D2,
                ).withValues(alpha: 1 - _controller.value),
              ),
            ),
            // The solid center dot
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1976D2),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The vertical connector between two stops. Solid blue when passed, an
/// animated flowing gradient when the bus is currently on that segment,
/// dim grey for future segments.
class FlowingLineConnector extends StatefulWidget {
  final bool isPassed;
  final bool isLoading;

  const FlowingLineConnector({
    super.key,
    required this.isPassed,
    required this.isLoading,
  });

  @override
  State<FlowingLineConnector> createState() => _FlowingLineConnectorState();
}

class _FlowingLineConnectorState extends State<FlowingLineConnector>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    if (widget.isLoading) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(FlowingLineConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isLoading) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. If the segment is already passed, show a solid blue line
    if (widget.isPassed) {
      return Container(width: 2.5, color: const Color(0xFF1976D2));
    }

    // 2. If the segment is currently loading (the bus is on it)
    if (widget.isLoading) {
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: 2.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(0, -1 + (_controller.value * 6)),
                end: Alignment(0, -2 + (_controller.value * 6)),
                colors: const [
                  Color(0xFF1976D2),
                  Color.fromARGB(255, 46, 59, 77),
                  Color(0xFF1976D2),
                ],
              ),
            ),
          );
        },
      );
    }

    // 3. If it's a future segment, show a dim grey line
    return Container(width: 2, color: context.palette.divider);
  }
}

/// A single stop row in the timeline, matching the rider "ALL STOPS" sheet.
/// [index] is the stop's position; [activeIndex] is the bus's next-stop index.
class StopTimelineTile extends StatelessWidget {
  final int index;
  final int activeIndex;
  final int totalStops;
  final String stopName;

  const StopTimelineTile({
    super.key,
    required this.index,
    required this.activeIndex,
    required this.totalStops,
    required this.stopName,
  });

  @override
  Widget build(BuildContext context) {
    final isTarget = index == activeIndex;
    final isPassed = index < activeIndex;
    final isLast = index == totalStops - 1;
    final isLinePassed = index < (activeIndex - 1);
    final isLineLoading = index == (activeIndex - 1);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Timeline lane
          SizedBox(
            width: 60,
            child: Column(
              children: [
                SizedBox(
                  height: 30,
                  child: Center(
                    child: isTarget
                        ? const BusPulseIndicator()
                        : Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isPassed
                                  ? const Color(0xFF1976D2)
                                  : context.palette.divider,
                            ),
                          ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: FlowingLineConnector(
                        isPassed: isLinePassed,
                        isLoading: isLineLoading,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 2. Station name
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 40),
              child: Text(
                stopName,
                style: TextStyle(
                  color: isTarget
                      ? context.palette.textPrimary
                      : (isPassed
                          ? context.palette.textSecondary
                          : context.palette.textFaintest),
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: isTarget ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

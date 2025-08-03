import 'package:flutter/material.dart';

class AnimatedCircle extends StatelessWidget {
  final Color color;
  final double size;
  final int duration;

  const AnimatedCircle({
    super.key,
    required this.color,
    required this.size,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Duration(milliseconds: duration),
      curve: Curves.easeInOut,
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

import 'package:flutter/material.dart';

class AppMark extends StatelessWidget {
  const AppMark({this.size = 52, super.key});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        'assets/branding/pactick_icon.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}

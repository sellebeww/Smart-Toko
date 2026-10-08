import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Aset asli Figma. Ukuran intrinsik SVG dipertahankan.
class FigmaIcon extends StatelessWidget {
  final String asset;
  const FigmaIcon(this.asset, {super.key});

  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset('assets/figma/$asset.svg');
}

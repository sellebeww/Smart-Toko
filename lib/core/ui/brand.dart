import 'package:flutter/material.dart';

import '../../app/theme.dart';

class SmartTokoLogo extends StatelessWidget {
  final double size;
  const SmartTokoLogo({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: Image.asset(
      'assets/brand/smarttoko-logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'Logo SmartToko',
    ),
  );
}

class BrandHeader extends StatelessWidget {
  final bool compact;
  const BrandHeader({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SmartTokoLogo(size: compact ? 44 : 68),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Smart'),
                  TextSpan(
                    text: 'Toko',
                    style: TextStyle(color: SmartTokoTheme.green),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: compact ? 22 : 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
                color: SmartTokoTheme.forest,
              ),
            ),
            if (!compact)
              Text(
                'Teman tumbuh usahamu',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    ],
  );
}

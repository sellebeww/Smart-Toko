/// Badge kecil status verifikasi, dipakai di Settings (dan bisa dipakai di
/// tempat lain nanti — misalnya header toko).
library;

import 'package:flutter/material.dart';

import '../domain/verification_status.dart';

class VerificationStatusBadge extends StatelessWidget {
  final StoreVerificationStatus status;

  const VerificationStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      StoreVerificationStatus.unverified => (Colors.grey, Icons.help_outline),
      StoreVerificationStatus.pending => (Colors.orange, Icons.hourglass_top),
      StoreVerificationStatus.verified => (Colors.green, Icons.verified),
      StoreVerificationStatus.rejected => (Colors.red, Icons.error_outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

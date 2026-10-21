import 'package:flutter/material.dart';
import 'package:nuans/core/theme/app_theme.dart';

/// A labelled status indicator.
///
/// Colour, icon and text together, never colour alone. A clinician may be
/// reading this at an angle, in a bright operatory, on a printed report, or
/// with a colour vision deficiency; a green dot on its own survives none of
/// those.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.status,
    required this.label,
    this.detail,
    this.dense = false,
    super.key,
  });

  final AppStatus status;
  final String label;

  /// A second line: the measured value, or why the check is failing.
  final String? detail;

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colour = AppTheme.statusColor(status);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 12,
        vertical: dense ? 4 : 8,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        border: Border.all(color: colour),
        borderRadius: BorderRadius.circular(dense ? 6 : 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            AppTheme.statusIcon(status),
            size: dense ? 16 : 20,
            color: colour,
          ),
          const SizedBox(width: 6),
          // Flexible, not Expanded: the chip sizes to its content inside a row
          // but still wraps rather than overflowing when the Turkish label is
          // longer than the English one.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: (dense ? textTheme.labelMedium : textTheme.titleSmall)
                      ?.copyWith(color: colour, fontWeight: FontWeight.w600),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

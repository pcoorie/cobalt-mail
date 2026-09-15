import 'package:flutter/material.dart';
import '../theme/brand_colors.dart';
import '../models/mail_folder.dart';

/// A full-width segmented pill control for switching between a small, fixed
/// set of folders (Inbox/Sent/Trash). Each folder gets an equal-width
/// segment; a filled indicator slides behind the selected one.
class FolderTabBar extends StatelessWidget {
  const FolderTabBar({
    super.key,
    required this.folders,
    required this.selected,
    required this.onSelect,
  });

  final List<MailFolder> folders;
  final MailFolder? selected;
  final ValueChanged<MailFolder> onSelect;

  static const _trackHeight = 40.0;
  static const _indicatorInset = 4.0;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final selectedIndex = selected == null
        ? -1
        : folders.indexWhere((folder) => folder.id == selected!.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentWidth = constraints.maxWidth / folders.length;
        return Container(
          height: _trackHeight,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(_trackHeight / 2),
          ),
          child: Stack(
            children: [
              if (selectedIndex >= 0)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  left: segmentWidth * selectedIndex,
                  width: segmentWidth,
                  top: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(_indicatorInset),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: brandSeed,
                        borderRadius: BorderRadius.circular(
                          (_trackHeight - _indicatorInset * 2) / 2,
                        ),
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (final folder in folders)
                    SizedBox(
                      width: segmentWidth,
                      height: _trackHeight,
                      child: _FolderSegment(
                        folder: folder,
                        selected: folder.id == selected?.id,
                        onTap: () => onSelect(folder),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FolderSegment extends StatelessWidget {
  const _FolderSegment({
    required this.folder,
    required this.selected,
    required this.onTap,
  });

  final MailFolder folder;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = selected ? Colors.white : scheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(FolderTabBar._trackHeight / 2),
        onTap: onTap,
        child: Center(
          child: Badge.count(
            count: folder.unreadCount,
            isLabelVisible: folder.unreadCount > 0,
            // Clearance so the badge doesn't crowd the last letter or the
            // pill's rounded edge — Badge anchors to its child's top-end
            // corner, so padding here shifts the anchor point outward.
            child: Padding(
              padding: const EdgeInsets.only(right: 10, top: 4),
              child: Text(
                folder.name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: textColor,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

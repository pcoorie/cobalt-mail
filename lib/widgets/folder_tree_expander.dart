import 'package:flutter/material.dart';
import '../models/mail_folder.dart';
import '../theme/brand_colors.dart';

class FolderTreeExpander extends StatefulWidget {
  const FolderTreeExpander({
    super.key,
    required this.folders,
    required this.onSelect,
    this.initiallyExpanded = false,
  });

  final List<MailFolder> folders;
  final ValueChanged<MailFolder> onSelect;
  final bool initiallyExpanded;

  @override
  State<FolderTreeExpander> createState() => _FolderTreeExpanderState();
}

class _FolderTreeExpanderState extends State<FolderTreeExpander> {
  static const _animationDuration = Duration(milliseconds: 200);

  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'More folders',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: brandSeed,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    AnimatedRotation(
                      duration: _animationDuration,
                      turns: _expanded ? 0.5 : 0,
                      child: Icon(Icons.expand_more, color: brandSeed, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: _animationDuration,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Container(
                    // Capped and scrollable so a long folder list can't grow
                    // unbounded inside the parent Column — left uncapped,
                    // expanding this list pushes past the available height,
                    // overflows the RenderFlex, and squeezes the message
                    // list below it down to zero height.
                    constraints: const BoxConstraints(maxHeight: 200),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    // ListTile paints its ink splashes/background on the
                    // nearest Material ancestor — without this, they'd be
                    // hidden behind the opaque DecoratedBox above.
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: widget.folders
                            .map((folder) => ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  leading: Icon(
                                    Icons.folder_outlined,
                                    color: scheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                                  title: Text(folder.name),
                                  onTap: () => widget.onSelect(folder),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

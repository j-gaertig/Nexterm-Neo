import 'package:flutter/material.dart';
import '../../widgets/app_ui.dart';
import '../../models/server.dart';
import '../../utils/app_icons.dart';
import '../../utils/tag_color.dart';

/// Opens a bottom sheet that lets the user pick the tags used to filter the
/// server list. Returns the new selection, or `null` when the sheet is
/// dismissed without applying changes.
Future<Set<int>?> showTagFilterSheet(
  BuildContext context, {
  required List<Tag> tags,
  required Set<int> selected,
}) {
  return showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
    ),
    builder: (_) => TagFilterSheet(tags: tags, selected: selected),
  );
}

class TagFilterSheet extends StatefulWidget {
  final List<Tag> tags;
  final Set<int> selected;

  const TagFilterSheet({super.key, required this.tags, required this.selected});

  @override
  State<TagFilterSheet> createState() => _TagFilterSheetState();
}

class _TagFilterSheetState extends State<TagFilterSheet> {
  late final Set<int> _selected = {...widget.selected};

  void _toggle(int tagId) {
    setState(() {
      _selected.contains(tagId)
          ? _selected.remove(tagId)
          : _selected.add(tagId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSheetHandle(margin: const EdgeInsets.only(top: 12, bottom: 4)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Filter by tags',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selected.isEmpty
                              ? 'Show servers with selected tags'
                              : '${_selected.length} of ${widget.tags.length} tags selected',
                          style: tt.bodySmall?.copyWith(color: cs.outline),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    icon: const Icon(AppIcons.close, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                itemCount: widget.tags.length,
                itemBuilder: (_, i) {
                  final tag = widget.tags[i];
                  final tagColor = parseTagColor(
                    tag.color,
                    fallback: cs.primary,
                  );
                  final selected = _selected.contains(tag.id);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: selected
                          ? tagColor.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('tag-filter-option-${tag.id}'),
                        onTap: () => _toggle(tag.id),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: tagColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  tag.name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Checkbox(
                                value: selected,
                                onChanged: (_) => _toggle(tag.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('tag-filter-clear'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () => setState(_selected.clear),
                      icon: const Icon(AppIcons.close, size: 16),
                      label: const Text('Clear filter'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('tag-filter-apply'),
                      onPressed: () =>
                          Navigator.pop(context, Set<int>.of(_selected)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

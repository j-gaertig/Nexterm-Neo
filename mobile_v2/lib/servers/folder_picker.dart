import 'package:flutter/material.dart';

import 'server_models.dart';

/// Folder placement choice: a folder id, or null for top level.
class FolderPick {
  const FolderPick(this.folderId);

  final int? folderId;
}

/// Bottom-sheet folder picker (new-folder parent, move-server target).
/// Organizations are shown disabled — only real folders take servers.
/// Dismiss returns null; an explicit choice returns [FolderPick].
Future<FolderPick?> showFolderPicker(
  BuildContext context,
  List<EntryNode> nodes, {
  String title = 'Move to folder',
  bool includeTopLevel = true,
}) async {
  final folders = _flattenFolders(nodes);
  return showModalBottomSheet<FolderPick>(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount:
                  folders.length + (includeTopLevel ? 1 : 0),
              itemBuilder: (_, i) {
                if (includeTopLevel && i == 0) {
                  return ListTile(
                    leading:
                        const Icon(Icons.home_outlined),
                    title: const Text('Top level',
                        style: TextStyle(
                            fontWeight: FontWeight.w600)),
                    onTap: () => Navigator.pop(
                        ctx, const FolderPick(null)),
                  );
                }
                final folder =
                    folders[includeTopLevel ? i - 1 : i];
                return ListTile(
                  leading: Icon(folder.node.isOrganization
                      ? Icons.business_outlined
                      : Icons.folder_outlined),
                  title: Padding(
                    padding: EdgeInsets.only(
                        left: 16.0 * folder.depth),
                    child: Text(folder.node.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                  ),
                  enabled: !folder.node.isOrganization,
                  onTap: folder.node.isOrganization
                      ? null
                      : () {
                          final id =
                              int.tryParse(folder.node.id);
                          if (id != null) {
                            Navigator.pop(
                                ctx, FolderPick(id));
                          }
                        },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

/// Depth-first real folders (organizations excluded) for placement
/// dropdowns.
List<FolderNode> flattenFolderNodes(List<EntryNode> nodes) {
  final out = <FolderNode>[];
  void walk(List<EntryNode> children) {
    for (final child in children) {
      if (child is FolderNode) {
        if (!child.isOrganization) out.add(child);
        walk(child.children);
      }
    }
  }

  walk(nodes);
  return out;
}

class _FlatFolder {
  const _FlatFolder(this.node, this.depth);

  final FolderNode node;
  final int depth;
}

List<_FlatFolder> _flattenFolders(List<EntryNode> nodes) {
  final out = <_FlatFolder>[];
  void walk(List<EntryNode> children, int depth) {
    for (final child in children) {
      if (child is FolderNode) {
        out.add(_FlatFolder(child, depth));
        walk(child.children, depth + 1);
      }
    }
  }

  walk(nodes, 0);
  return out;
}

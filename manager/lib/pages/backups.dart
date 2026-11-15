import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../core/manager.dart';
import '../main.dart';
import 'ui.dart';

class BackupsPage extends StatelessWidget {
  const BackupsPage({required this.manager, required this.onChanged, super.key});

  final AddonCarManager manager;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final backups = manager.listBackups();
    if (backups.isEmpty) {
      return Center(child: Text('No backups', style: context.mutedStyle));
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return ListPanel(
      itemCount: backups.length,
      itemBuilder: (context, i) {
        final b = backups[i];
        final t = b.created;
        final added = b.files.where((f) => !f.existed).length;
        return RowItem(
          title: Text(b.action[0].toUpperCase() + b.action.substring(1)),
          detail:
              '${t.year}-${two(t.month)}-${two(t.day)}  ${two(t.hour)}:${two(t.minute)}  ·  '
              '${b.files.length} ${b.files.length == 1 ? 'file' : 'files'}${added == 0 ? '' : ', $added created by the change'}',
          trailing: [
            FTooltip(
              tipBuilder: (_, _) => Text([for (final f in b.files) f.existed ? f.path : '${f.path} (new: deleted on restore)'].join('\n')),
              child: const Pill('Files'),
            ),
            FButton(
              variant: .outline,
              size: .sm,
              mainAxisSize: .min,
              prefix: const Icon(FLucideIcons.rotateCcw),
              onPress: () async {
                if (await confirm(
                  context,
                  'Restore "${b.action}"?',
                  'Puts these ${b.files.length} files back as they were before that change. The current versions are backed up first.',
                  ok: 'Restore',
                )) {
                  if (context.mounted) runAction(context, 'Restored', () => manager.restore(b), onChanged);
                }
              },
              child: const Text('Restore'),
            ),
            ActionIcon(FLucideIcons.trash2, 'Delete backup', () async {
              if (await confirm(
                context,
                'Delete this backup?',
                'The backup folder is deleted for good. Game files are not touched.',
                ok: 'Delete',
                destructive: true,
              )) {
                if (context.mounted) runAction(context, 'Backup deleted', () => manager.deleteBackup(b), onChanged);
              }
            }),
          ],
        );
      },
    );
  }
}

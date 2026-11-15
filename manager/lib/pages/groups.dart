import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../core/cargrp.dart';
import '../core/manager.dart';
import '../main.dart';
import 'ui.dart';

/// Puts add-on cars into the traffic groups of cargrp.dat, per episode. Vanilla entries are shown
/// but never changed; each change edits one line and is backed up first.
class GroupsPage extends StatefulWidget {
  const GroupsPage({required this.manager, required this.onChanged, super.key});

  final AddonCarManager manager;
  final VoidCallback onChanged;

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  Episode _episode = Episode.iv;

  @override
  Widget build(BuildContext context) {
    final m = widget.manager;
    final groups = m.readCarGroups(_episode).groups;
    final addons = {for (final c in m.listCars()) c.model: c.displayName ?? c.model};

    void edit(String what, void Function(CarGroups g) change) => runAction(
      context,
      what,
      () {
        final g = m.readCarGroups(_episode);
        change(g);
        m.saveCarGroups(_episode, g, '$what, ${_episode.name}');
      },
      () {
        setState(() {});
        widget.onChanged();
      },
    );

    return Column(
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Segmented<Episode>(
          values: Episode.values,
          label: (e) => e.title,
          selected: _episode,
          onSelect: (e) => setState(() => _episode = e),
        ),
        Expanded(
          child: ListPanel(
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final g = groups[i];
              final inGroup = [
                for (final x in g.models)
                  if (addons.containsKey(x.toLowerCase())) x.toLowerCase(),
              ];
              final available = [
                for (final a in addons.keys)
                  if (!inGroup.contains(a)) a,
              ];
              final over = g.models.length > CarGroups.maxCarsPerGroup;
              final full = g.models.length >= CarGroups.maxCarsPerGroup;
              return RowItem(
                title: Text(g.name),
                detail: g.models.where((x) => !addons.containsKey(x.toLowerCase())).join(', '),
                trailing: [
                  if (!g.usedByGame)
                    const Pill('Ignored by the game', tone: Tone.bad)
                  else if (g.multiplayerOnly)
                    const Pill('Multiplayer only', tone: Tone.bad),
                  Pill(
                    over
                        ? '${g.models.length} listed · first ${CarGroups.maxCarsPerGroup} used'
                        : '${g.models.length} / ${CarGroups.maxCarsPerGroup}',
                    tone: over && !g.multiplayerOnly ? Tone.bad : Tone.neutral,
                  ),
                  if (available.isNotEmpty && !full)
                    SizedBox(
                      width: 170,
                      child: FSelect<String>.rich(
                        key: ValueKey('add $i ${inGroup.join()}'),
                        size: .sm,
                        hint: 'Add car…',
                        format: (s) => addons[s]!,
                        control: .managed(
                          onChange: (v) {
                            if (v != null) edit('Added ${addons[v]} to ${g.name}', (x) => x.add(i, v));
                          },
                        ),
                        children: [for (final a in available) .item(title: Text(addons[a]!), value: a)],
                      ),
                    ),
                ],
                // add-on cars in this group, removable; nothing below when there are none
                below: inGroup.isEmpty
                    ? null
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final model in inGroup)
                            Pill(
                              addons[model]!,
                              tone: Tone.ok,
                              onRemove: () => edit('Removed ${addons[model]} from ${g.name}', (x) => x.remove(i, model)),
                            ),
                        ],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

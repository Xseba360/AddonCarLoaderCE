import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// Shared building blocks so every tab looks the same: flat striped rows, quiet secondary text,
/// small status chips, and icon actions with tooltips.

const okColor = Color(0xFF22C55E);

/// The pause menu's orange, for whatever is selected.
const gtaOrange = Color(0xFFF7A01B);

const appName = 'Add-on Car Manager CE';

/// The program's name, its "CE" in pause-menu orange.
class AppTitle extends StatelessWidget {
  const AppTitle({this.style, super.key});
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: appName.substring(0, appName.length - 2),
      children: const [
        TextSpan(
          text: 'CE',
          style: TextStyle(color: gtaOrange),
        ),
      ],
    ),
    style: style,
  );
}

extension Typo on BuildContext {
  TextStyle get titleStyle => theme.typography.body.md.copyWith(fontWeight: FontWeight.w600, color: theme.colors.foreground);
  TextStyle get mutedStyle => theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground);
  // DIN 1451 for secondary text, like the pause menu's key hints; Switzer (the theme default) for everything else
  TextStyle get smallMuted => theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground, fontFamily: 'DIN1451', fontSize: 13);
}

/// Flat striped rows, like the pause menu's lists; scrolls inside its parent.
class ListPanel extends StatelessWidget {
  const ListPanel({required this.itemCount, required this.itemBuilder, super.key});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => ListView.separated(
    primary: true,
    itemCount: itemCount,
    separatorBuilder: (_, _) => const SizedBox(height: 3),
    itemBuilder: (context, i) => ColoredBox(color: context.theme.colors.card, child: itemBuilder(context, i)),
  );
}

/// One list row: title + detail line, and whatever goes on the right.
class RowItem extends StatelessWidget {
  const RowItem({required this.title, this.detail, this.trailing = const [], this.below, super.key});

  final Widget title;
  final String? detail;
  final List<Widget> trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      crossAxisAlignment: below == null ? .center : .start,
      spacing: 14,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 3,
            children: [
              DefaultTextStyle.merge(style: context.titleStyle, child: title),
              if (detail != null) Text(detail!.toUpperCase(), style: context.smallMuted, overflow: TextOverflow.ellipsis),
              if (below != null) Padding(padding: const EdgeInsets.only(top: 6), child: below),
            ],
          ),
        ),
        // one group, so the count and the picker stay level with each other in a tall row
        if (trailing.isNotEmpty) Row(mainAxisSize: .min, spacing: 14, children: trailing),
      ],
    ),
  );
}

enum Tone { neutral, ok, bad }

/// Small rounded label; [Tone.ok]/[Tone.bad] add a coloured dot. (Not "Chip": material_ui has one.)
class Pill extends StatelessWidget {
  const Pill(this.text, {this.tone = Tone.neutral, this.onRemove, super.key});

  final String text;
  final Tone tone;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.theme.colors;
    final dot = switch (tone) {
      Tone.ok => okColor,
      Tone.bad => c.destructive,
      Tone.neutral => null,
    };
    return Container(
      padding: EdgeInsets.fromLTRB(10, 4, onRemove == null ? 10 : 4, 4),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          if (dot != null)
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          Flexible(
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.theme.typography.body.xs.copyWith(color: c.foreground, fontFamily: 'DIN1451', fontSize: 13),
            ),
          ),
          if (onRemove != null)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(FLucideIcons.x, size: 13, color: c.mutedForeground),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ghost icon button with a hover tooltip.
class ActionIcon extends StatelessWidget {
  const ActionIcon(this.icon, this.tip, this.onPress, {this.destructive = false, super.key});

  final IconData icon;
  final String tip;
  final VoidCallback? onPress;
  final bool destructive;

  @override
  Widget build(BuildContext context) => FTooltip(
    tipBuilder: (_, _) => Text(tip),
    child: FButton.icon(
      variant: .ghost,
      size: .sm,
      onPress: onPress,
      child: Icon(icon, color: destructive ? context.theme.colors.destructive : null),
    ),
  );
}

/// Segmented switcher used for the tabs and the episode picker.
class Segmented<T> extends StatelessWidget {
  const Segmented({required this.values, required this.label, required this.selected, required this.onSelect, super.key});

  final List<T> values;
  final String Function(T) label;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  // scrolls sideways when the window is too narrow for all labels
  Widget build(BuildContext context) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: _bar(context));

  // pause-menu tabs: plain text, the selected one orange and underlined
  Widget _bar(BuildContext context) => Row(
    mainAxisSize: .min,
    spacing: 4,
    children: [
      for (final v in values)
        IntrinsicWidth(
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              FButton(
                variant: .ghost,
                size: .sm,
                mainAxisSize: .min,
                onPress: () => onSelect(v),
                child: Text(label(v), style: TextStyle(color: v == selected ? gtaOrange : context.theme.colors.mutedForeground)),
              ),
              Container(height: 2, color: v == selected ? gtaOrange : null),
            ],
          ),
        ),
    ],
  );
}

/// Centered content column with a comfortable maximum width.
class PageWidth extends StatelessWidget {
  const PageWidth({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1040), child: child),
  );
}

/// Striped label/value rows like the pause menu's Stats table; a bad value shows in red.
class StatsTable extends StatelessWidget {
  const StatsTable(this.rows, {this.onTap, super.key});
  final List<(String label, String value, bool bad)> rows;

  /// Makes the rows clickable; called with the row's index.
  final void Function(int row)? onTap;

  Widget _tappable(int row, Widget child) => onTap == null ? child : FTappable(onPress: () => onTap!(row), child: child);

  @override
  Widget build(BuildContext context) {
    final c = context.theme.colors;
    return Column(
      spacing: 3,
      children: [
        for (final (i, (label, value, bad)) in rows.indexed)
          _tappable(
            i,
            Container(
              color: c.card,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              // both shrink to their text, so the value sits at the right edge
              child: Row(
                mainAxisAlignment: .spaceBetween,
                spacing: 16,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.typography.body.md.copyWith(color: c.mutedForeground),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.typography.body.md.copyWith(color: bad ? c.destructive : c.foreground),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

/// 标签条：点击切换、中键/按钮关闭、拖拽排序、右键菜单。
class WorkbenchTabStrip extends StatelessWidget {
  const WorkbenchTabStrip({
    super.key,
    required this.tabs,
    required this.active,
    required this.label,
    required this.icon,
    required this.onActivate,
    required this.onClose,
    required this.onMove,
    required this.onMenu,
  });
  final List<String> tabs;
  final String? active;
  final String Function(String view) label;
  final IconData Function(String view) icon;
  final ValueChanged<String> onActivate;
  final ValueChanged<String> onClose;
  final void Function(String view, int index) onMove;
  final void Function(String view, Offset globalPosition) onMenu;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 36,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < tabs.length; index++)
              DragTarget<String>(
                onWillAcceptWithDetails: (details) => details.data != tabs[index],
                onAcceptWithDetails: (details) => onMove(details.data, index),
                builder: (context, candidates, _) => _Tab(
                  view: tabs[index],
                  label: label(tabs[index]),
                  icon: icon(tabs[index]),
                  selected: tabs[index] == active,
                  highlighted: candidates.isNotEmpty,
                  onTap: () => onActivate(tabs[index]),
                  onClose: () => onClose(tabs[index]),
                  onMenu: (position) => onMenu(tabs[index], position),
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.view,
    required this.label,
    required this.icon,
    required this.selected,
    required this.highlighted,
    required this.onTap,
    required this.onClose,
    required this.onMenu,
  });
  final String view;
  final String label;
  final IconData icon;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chip = Container(
      height: 28,
      margin: const EdgeInsets.only(top: 4, bottom: 4, right: 2),
      padding: const EdgeInsets.only(left: 8, right: 2),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primaryContainer
            : selected
            ? scheme.surface
            : null,
        border: selected
            ? Border.all(color: scheme.outlineVariant)
            : Border.all(color: Colors.transparent),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: selected
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onClose,
            child: Tooltip(
              message: '关闭标签 (Ctrl+W)',
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Draggable<String>(
      data: view,
      feedback: Opacity(
        opacity: 0.85,
        child: Material(
          color: Colors.transparent,
          child: _plainChip(context),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: chip),
      child: GestureDetector(
        onSecondaryTapDown: (details) => onMenu(details.globalPosition),
        child: Tooltip(
          message: label,
          waitDuration: const Duration(milliseconds: 600),
          child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(7), child: chip),
        ),
      ),
    );
  }

  Widget _plainChip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 28,
      margin: const EdgeInsets.only(top: 4, right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}

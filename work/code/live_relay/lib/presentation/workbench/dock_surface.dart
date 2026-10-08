import 'package:flutter/material.dart';

import 'state/workbench_layout.dart';

typedef WorkbenchViewBuilder = Widget Function(String view, String groupId);

class DockSurface extends StatelessWidget {
  const DockSurface({
    super.key,
    required this.layout,
    required this.dragging,
    required this.builder,
    required this.label,
    required this.icon,
    this.onDetach,
    this.canDetach,
  });
  final WorkbenchLayout layout;
  final ValueNotifier<String?> dragging;
  final WorkbenchViewBuilder builder;
  final String Function(String) label;
  final IconData Function(String) icon;
  final ValueChanged<String>? onDetach;
  final bool Function(String)? canDetach;

  Widget draggable(String view, Widget child) => Draggable<String>(
    data: view,
    onDragStarted: () => dragging.value = view,
    onDragEnd: (_) => dragging.value = null,
    feedback: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(label(view)),
      ),
    ),
    childWhenDragging: Opacity(opacity: .4, child: child),
    child: child,
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: layout,
    builder: (context, _) => LayoutBuilder(
      builder: (context, size) => Stack(
        children: [
          Positioned.fill(child: _node(context, layout.root)),
          for (final f in layout.floating)
            Positioned(
              left: f.x.clamp(
                0,
                (size.maxWidth - 80).clamp(0, double.infinity),
              ),
              top: f.y.clamp(
                0,
                (size.maxHeight - 60).clamp(0, double.infinity),
              ),
              width: f.width.clamp(
                260,
                size.maxWidth.clamp(260, double.infinity),
              ),
              height: f.height.clamp(
                180,
                size.maxHeight.clamp(180, double.infinity),
              ),
              child: Material(
                elevation: 12,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        GestureDetector(
                          key: ValueKey('dock-floating-move-${f.group.id}'),
                          onPanUpdate: (d) {
                            f.x += d.delta.dx;
                            f.y += d.delta.dy;
                            layout.changed();
                          },
                          child: Container(
                            height: 26,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: const Row(
                              children: [
                                SizedBox(width: 8),
                                Icon(Icons.drag_indicator, size: 16),
                                Text('工作台内浮动', style: TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                        Expanded(child: _group(context, f.group)),
                      ],
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: GestureDetector(
                          key: ValueKey('dock-floating-resize-${f.group.id}'),
                          onPanUpdate: (d) {
                            f.width = (f.width + d.delta.dx).clamp(
                              260,
                              size.maxWidth.clamp(260, double.infinity),
                            );
                            f.height = (f.height + d.delta.dy).clamp(
                              180,
                              size.maxHeight.clamp(180, double.infinity),
                            );
                            layout.changed();
                          },
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: Icon(Icons.south_east, size: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
  Widget _node(BuildContext context, DockNode node) {
    if (node is DockGroup) return _group(context, node);
    final split = node as DockSplit;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available =
            (split.vertical ? constraints.maxHeight : constraints.maxWidth) - 6;
        final handle = MouseRegion(
          cursor: split.vertical
              ? SystemMouseCursors.resizeUpDown
              : SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            key: ObjectKey(split),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) {
              if (available <= 0) return;
              layout.resize(
                split,
                split.fraction +
                    (split.vertical ? d.delta.dy : d.delta.dx) / available,
              );
            },
            child: SizedBox(
              width: split.vertical ? null : 6,
              height: split.vertical ? 6 : null,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        );
        final children = [
          SizedBox(
            width: split.vertical ? null : available * split.fraction,
            height: split.vertical ? available * split.fraction : null,
            child: _node(context, split.first),
          ),
          handle,
          Expanded(child: _node(context, split.second)),
        ];
        return split.vertical
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              );
      },
    );
  }

  Widget _group(BuildContext context, DockGroup group) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 42,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final view in group.tabs)
                        draggable(
                          view,
                          Container(
                            width: 160,
                            decoration: BoxDecoration(
                              color: group.selected == view
                                  ? Theme.of(context).colorScheme.surface
                                  : null,
                              border: Border(
                                bottom: BorderSide(
                                  width: 2,
                                  color: group.selected == view
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => layout.select(group, view),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(icon(view), size: 17),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              label(view),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '关闭标签',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close, size: 15),
                                  onPressed: () => layout.close(view),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (onDetach != null &&
                  group.selected != null &&
                  (canDetach?.call(group.selected!) ?? false))
                IconButton(
                  tooltip: '移到独立桌面窗口',
                  icon: const Icon(Icons.launch, size: 18),
                  onPressed: () => onDetach!(group.selected!),
                ),
              PopupMenuButton<DockPlacement>(
                tooltip: '移动当前视图',
                iconSize: 18,
                onSelected: (p) {
                  if (group.selected != null) {
                    layout.move(group.selected!, layout.groups.first.id, p);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: DockPlacement.center,
                    child: Text('合并到首个标签组'),
                  ),
                  const PopupMenuItem(
                    value: DockPlacement.left,
                    child: Text('向左分屏'),
                  ),
                  const PopupMenuItem(
                    value: DockPlacement.right,
                    child: Text('向右分屏'),
                  ),
                  const PopupMenuItem(
                    value: DockPlacement.top,
                    child: Text('向上分屏'),
                  ),
                  const PopupMenuItem(
                    value: DockPlacement.bottom,
                    child: Text('向下分屏'),
                  ),
                  const PopupMenuItem(
                    value: DockPlacement.floating,
                    child: Text('工作台内浮动'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: group.selected == null
                    ? const Center(child: Text('拖入视图或从左侧打开'))
                    : KeyedSubtree(
                        key: ValueKey(group.selected),
                        child: builder(group.selected!, group.id),
                      ),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: dragging,
                builder: (context, view, _) {
                  if (view == null) return const SizedBox.shrink();
                  return Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface
                          .withValues(alpha: .7),
                      child: LayoutBuilder(
                        builder: (context, size) => Stack(
                          children: [
                            for (final p in [
                              DockPlacement.left,
                              DockPlacement.right,
                              DockPlacement.top,
                              DockPlacement.bottom,
                              DockPlacement.center,
                            ])
                              Align(
                                alignment: switch (p) {
                                  DockPlacement.left => Alignment.centerLeft,
                                  DockPlacement.right => Alignment.centerRight,
                                  DockPlacement.top => Alignment.topCenter,
                                  DockPlacement.bottom =>
                                    Alignment.bottomCenter,
                                  _ => Alignment.center,
                                },
                                child: _target(context, group, p),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _target(BuildContext context, DockGroup group, DockPlacement p) =>
      DragTarget<String>(
        key: ValueKey('dock-target-${group.id}-${p.name}'),
        onAcceptWithDetails: (d) => layout.move(d.data, group.id, p),
        builder: (context, candidates, rejected) => Container(
          width: p == DockPlacement.center ? 110 : 64,
          height: 64,
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              width: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
            color: candidates.isEmpty
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Theme.of(context).colorScheme.primaryContainer,
          ),
          child: Center(
            child: Text(switch (p) {
              DockPlacement.left => '左侧',
              DockPlacement.right => '右侧',
              DockPlacement.top => '上方',
              DockPlacement.bottom => '下方',
              _ => '标签合并',
            }),
          ),
        ),
      );
}

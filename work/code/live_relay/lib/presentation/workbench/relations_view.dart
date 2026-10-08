import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../../core/domain/entities.dart';
import 'reference_panel.dart';

class _Node {
  const _Node(this.id, this.label, this.source);
  final String id, label;
  final bool source;
}

class _Edge {
  const _Edge(this.from, this.to, this.kind);
  final String from, to, kind;
}

class _Graph {
  const _Graph(this.nodes, this.edges);
  final Map<String, _Node> nodes;
  final List<_Edge> edges;
}

class RelationsView extends StatefulWidget {
  const RelationsView({
    super.key,
    required this.controller,
    required this.onCard,
    required this.onSource,
  });
  final AppController controller;
  final ValueChanged<String> onCard, onSource;
  @override
  State<RelationsView> createState() => _RelationsViewState();
}

class _RelationsViewState extends State<RelationsView> {
  late Future<_Graph> _graph;
  String _signature = '', _filter = 'all';
  String? _focus;
  final _positions = <String, Offset>{};
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant RelationsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reload();
  }

  void _reload() {
    final c = widget.controller;
    final signature =
        '${c.cards.map((v) => '${v.id}:${v.revisionNumber}').join(',')}|${c.cardReferences.map((r) => '${r.from}:${r.to}').join(',')}|${c.blobs.length}';
    if (_signature == signature) return;
    _signature = signature;
    _graph = _load();
  }

  Future<_Graph> _load() async {
    final c = widget.controller;
    final cards = List.of(c.cards);
    final nodes = {
      for (final card in cards) card.id: _Node(card.id, card.title, false),
    };
    final edges = <_Edge>[];
    final seen = <String>{};
    void add(String from, String to, String kind) {
      if (seen.add('$kind:$from:$to')) edges.add(_Edge(from, to, kind));
    }

    for (final r in c.cardReferences) {
      if (nodes.containsKey(r.from) && nodes.containsKey(r.to)) {
        add(r.from, r.to, 'reference');
      }
    }
    final details = await Future.wait([
      for (final card in cards)
        Future.wait<Object>([
          c.cardRelations(card.id),
          c.currentCardSources(card.id),
        ]),
    ]);
    for (var i = 0; i < cards.length; i++) {
      for (final r in details[i][0] as List<CardRelation>) {
        if (nodes.containsKey(r.fromCardId) && nodes.containsKey(r.toCardId)) {
          add(
            r.fromCardId,
            r.toCardId,
            r.kind == RelationKind.bundleMember ? 'collection' : 'split',
          );
        }
      }
      for (final s in details[i][1] as List<CardSource>) {
        if (s.blobId == null) continue;
        final blob = c.blobs.where((b) => b.id == s.blobId).firstOrNull;
        if (blob == null) continue;
        final id = 'source/${blob.id}';
        nodes[id] = _Node(id, blob.originalName, true);
        add(cards[i].id, id, 'source');
      }
    }
    return _Graph(nodes, edges);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DropdownButton<String>(
              value:
                  _focus != null &&
                      widget.controller.cards.any((c) => c.id == _focus)
                  ? _focus
                  : '',
              items: [
                const DropdownMenuItem(value: '', child: Text('全局关系')),
                for (final c in widget.controller.cards)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.title, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) => setState(() => _focus = id == '' ? null : id),
            ),
            DropdownButton<String>(
              value: _filter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('全部关系')),
                DropdownMenuItem(value: 'reference', child: Text('卡片引用 →')),
                DropdownMenuItem(value: 'source', child: Text('原件来源')),
                DropdownMenuItem(value: 'collection', child: Text('收纳')),
                DropdownMenuItem(value: 'split', child: Text('拆分沿革')),
              ],
              onChanged: (v) => setState(() => _filter = v!),
            ),
          ],
        ),
      ),
      if (_focus != null && widget.controller.cards.any((c) => c.id == _focus))
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ReferencePanel(
            controller: widget.controller,
            cardId: _focus!,
            onOpen: widget.onCard,
          ),
        ),
      Expanded(
        child: FutureBuilder<_Graph>(
          future: _graph,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('关系读取失败，切换视图可重试'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final graph = snapshot.data!;
            final edges = graph.edges
                .where((e) => _filter == 'all' || e.kind == _filter)
                .toList();
            final visible = graph.nodes.keys.toSet();
            if (_focus != null) {
              visible.clear();
              visible.add(_focus!);
              // Two hops reveal cards sharing the same original without invented edges.
              for (var hop = 0; hop < 2; hop++) {
                final adjacent = <String>{};
                for (final e in edges) {
                  if (visible.contains(e.from)) adjacent.add(e.to);
                  if (visible.contains(e.to)) adjacent.add(e.from);
                }
                visible.addAll(adjacent);
              }
            }
            final nodes = graph.nodes.values
                .where((n) => visible.contains(n.id))
                .take(150)
                .toList();
            if (nodes.isEmpty) {
              return const Center(child: Text('添加资料后可以查看真实引用、来源和收纳关系'));
            }
            final visibleEdges = edges
                .where(
                  (e) => visible.contains(e.from) && visible.contains(e.to),
                )
                .toList();
            return Column(
              children: [
                Text(
                  '${nodes.length} 个节点 · ${visibleEdges.where((e) => e.kind == 'reference').length} 条引用 · ${visibleEdges.where((e) => e.kind == 'source').length} 条来源 · ${visibleEdges.where((e) => e.kind == 'collection').length} 条收纳',
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = math.max(350.0, constraints.maxWidth),
                          height = math.max(200.0, constraints.maxHeight);
                      final points = <String, Offset>{};
                      for (var i = 0; i < nodes.length; i++) {
                        final angle = 2 * math.pi * i / nodes.length;
                        points[nodes[i].id] =
                            _positions[nodes[i].id] ??
                            Offset(
                              width / 2 + math.cos(angle) * (width / 2 - 110),
                              height / 2 + math.sin(angle) * (height / 2 - 70),
                            );
                      }
                      return InteractiveViewer(
                        constrained: false,
                        minScale: .3,
                        maxScale: 3,
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _GraphPainter(
                                    points,
                                    edges,
                                    Theme.of(context).colorScheme,
                                  ),
                                ),
                              ),
                              for (final node in nodes)
                                Positioned(
                                  left: points[node.id]!.dx - 70,
                                  top: points[node.id]!.dy - 26,
                                  width: 140,
                                  child: GestureDetector(
                                    onPanUpdate: (d) => setState(
                                      () => _positions[node.id] =
                                          points[node.id]! + d.delta,
                                    ),
                                    child: Tooltip(
                                      message: node.label,
                                      child: FilledButton.tonalIcon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: node.source
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .tertiaryContainer
                                              : null,
                                        ),
                                        onPressed: () => node.source
                                            ? widget.onSource(
                                                node.id.substring(7),
                                              )
                                            : widget.onCard(node.id),
                                        icon: Icon(
                                          node.source
                                              ? Icons.attach_file
                                              : Icons.description_outlined,
                                          size: 15,
                                        ),
                                        label: Text(
                                          node.label,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          '箭头表示引用方向；原件连接表示来源；标签仅用于筛选。',
          style: TextStyle(fontSize: 11),
        ),
      ),
    ],
  );
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.points, this.edges, this.scheme);
  final Map<String, Offset> points;
  final List<_Edge> edges;
  final ColorScheme scheme;
  @override
  void paint(Canvas canvas, Size size) {
    for (final e in edges) {
      final a = points[e.from], b = points[e.to];
      if (a == null || b == null) continue;
      final paint = Paint()
        ..color = e.kind == 'source'
            ? scheme.tertiary
            : e.kind == 'reference'
            ? scheme.primary
            : scheme.outline
        ..strokeWidth = 1.7;
      canvas.drawLine(a, b, paint);
      if (e.kind == 'reference') {
        final delta = b - a, length = delta.distance;
        if (length < 1) continue;
        final unit = delta / length,
            tip = b - unit * 78,
            normal = Offset(-unit.dy, unit.dx);
        canvas.drawLine(tip, tip - unit * 10 + normal * 5, paint);
        canvas.drawLine(tip, tip - unit * 10 - normal * 5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) => true;
}

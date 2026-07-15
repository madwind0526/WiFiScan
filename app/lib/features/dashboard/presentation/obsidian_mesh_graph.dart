import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

class MeshGraphCluster {
  const MeshGraphCluster({
    required this.label,
    required this.members,
    this.hub,
  });

  final String label;
  final NetworkDevice? hub;
  final List<NetworkDevice> members;
}

class MeshGraphEdge {
  const MeshGraphEdge(this.sourceId, this.targetId);

  final String sourceId;
  final String targetId;

  bool touches(String nodeId) => sourceId == nodeId || targetId == nodeId;

  String other(String nodeId) => sourceId == nodeId ? targetId : sourceId;
}

class MeshGraphLayout {
  const MeshGraphLayout({required this.positions, required this.size});

  final Map<String, Offset> positions;
  final Size size;
}

class MeshGraphLayoutEngine {
  const MeshGraphLayoutEngine();

  MeshGraphLayout calculate({
    required List<String> nodeIds,
    required List<MeshGraphEdge> edges,
    required Map<String, int> groups,
    required Set<String> hubIds,
    required Size size,
  }) {
    if (nodeIds.isEmpty) {
      return MeshGraphLayout(positions: const {}, size: size);
    }

    final positions = <String, Offset>{};
    final groupCount = groups.values.toSet().length.clamp(1, nodeIds.length);
    final center = size.center(Offset.zero);
    final componentRadius = groupCount == 1
        ? 0.0
        : math.min(size.width, size.height) * 0.27;
    final groupCenters = <int, Offset>{};

    for (final group in groups.values.toSet()) {
      final angle = -math.pi / 2 + (2 * math.pi * group / groupCount);
      groupCenters[group] = Offset(
        center.dx + math.cos(angle) * componentRadius,
        center.dy + math.sin(angle) * componentRadius,
      );
    }

    for (var index = 0; index < nodeIds.length; index++) {
      final id = nodeIds[index];
      final hash = _stableHash(id);
      final groupCenter = groupCenters[groups[id] ?? 0] ?? center;
      final angle = ((hash % 360) / 360) * math.pi * 2;
      final radius = 22.0 + (hash % 79).toDouble();
      positions[id] = Offset(
        groupCenter.dx + math.cos(angle) * radius,
        groupCenter.dy + math.sin(angle) * radius,
      );
    }

    final iterations = nodeIds.length > 90 ? 90 : 150;
    const margin = 58.0;
    for (var iteration = 0; iteration < iterations; iteration++) {
      final forces = {for (final id in nodeIds) id: Offset.zero};

      for (var i = 0; i < nodeIds.length; i++) {
        for (var j = i + 1; j < nodeIds.length; j++) {
          final firstId = nodeIds[i];
          final secondId = nodeIds[j];
          final delta = positions[firstId]! - positions[secondId]!;
          final distanceSquared = math.max(delta.distanceSquared, 36.0);
          final direction = delta / math.sqrt(distanceSquared);
          final strength = 5200.0 / distanceSquared;
          forces[firstId] = forces[firstId]! + direction * strength;
          forces[secondId] = forces[secondId]! - direction * strength;
        }
      }

      for (final edge in edges) {
        final source = positions[edge.sourceId];
        final target = positions[edge.targetId];
        if (source == null || target == null) continue;
        final delta = target - source;
        final distance = math.max(delta.distance, 1.0);
        final desiredDistance =
            hubIds.contains(edge.sourceId) || hubIds.contains(edge.targetId)
            ? 104.0
            : 82.0;
        final spring =
            delta / distance * ((distance - desiredDistance) * 0.035);
        forces[edge.sourceId] = forces[edge.sourceId]! + spring;
        forces[edge.targetId] = forces[edge.targetId]! - spring;
      }

      for (final id in nodeIds) {
        final target = groupCenters[groups[id] ?? 0] ?? center;
        final gravity = (target - positions[id]!) * 0.008;
        forces[id] = forces[id]! + gravity;
      }

      final temperature = 7.5 * (1 - iteration / iterations) + 0.35;
      for (final id in nodeIds) {
        var force = forces[id]!;
        if (force.distance > temperature) {
          force = force / force.distance * temperature;
        }
        final next = positions[id]! + force;
        positions[id] = Offset(
          next.dx.clamp(margin, size.width - margin),
          next.dy.clamp(margin, size.height - margin),
        );
      }
    }

    return MeshGraphLayout(positions: positions, size: size);
  }
}

class ObsidianMeshGraph extends StatefulWidget {
  const ObsidianMeshGraph({
    super.key,
    required this.devices,
    required this.newDeviceIds,
    required this.onDeviceTap,
    this.gateway,
    this.clusters,
    this.framed = true,
  });

  final List<NetworkDevice> devices;
  final Set<String> newDeviceIds;
  final ValueChanged<NetworkDevice> onDeviceTap;
  final String? gateway;
  final List<MeshGraphCluster>? clusters;
  final bool framed;

  @override
  State<ObsidianMeshGraph> createState() => _ObsidianMeshGraphState();
}

class _ObsidianMeshGraphState extends State<ObsidianMeshGraph> {
  static const _layoutEngine = MeshGraphLayoutEngine();

  final TransformationController _transformationController =
      TransformationController();
  String? _hoveredId;
  String? _selectedId;
  String? _layoutKey;
  MeshGraphLayout? _layout;
  Size _viewportSize = Size.zero;
  bool _fitScheduled = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final graph = _buildGraph();
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 560.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 440.0;
        _viewportSize = Size(width, height);
        final density = math.sqrt(math.max(graph.devices.length, 1)) * 54;
        final graphSize = Size(
          math.max(width, 500 + density),
          math.max(height, 360 + density * 0.72),
        );
        final layoutKey = _makeLayoutKey(graph, graphSize);
        if (_layout == null || _layoutKey != layoutKey) {
          _layoutKey = layoutKey;
          _layout = _layoutEngine.calculate(
            nodeIds: graph.devices.map((device) => device.id).toList(),
            edges: graph.edges,
            groups: graph.groups,
            hubIds: graph.hubIds,
            size: graphSize,
          );
          _scheduleFit();
        }
        return _buildGraphSurface(context, graph, _layout!);
      },
    );

    if (!widget.framed) return content;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(height: 440, child: content),
    );
  }

  _MeshGraphData _buildGraph() {
    final byId = {for (final device in widget.devices) device.id: device};
    final sourceClusters = widget.clusters;
    final activeClusters = sourceClusters != null && sourceClusters.length > 1
        ? sourceClusters
        : [
            MeshGraphCluster(
              label: '',
              hub: _findHub(widget.devices),
              members: widget.devices,
            ),
          ];
    final edges = <MeshGraphEdge>[];
    final edgeKeys = <String>{};
    final groups = <String, int>{};
    final hubIds = <String>{};
    final labels = <String, String>{};

    for (var index = 0; index < activeClusters.length; index++) {
      final cluster = activeClusters[index];
      final members = cluster.members.where(
        (item) => byId.containsKey(item.id),
      );
      for (final device in members) {
        groups.putIfAbsent(device.id, () => index);
      }
      final hub = cluster.hub;
      if (hub != null && byId.containsKey(hub.id)) {
        hubIds.add(hub.id);
        if (cluster.label.isNotEmpty) labels[hub.id] = cluster.label;
        for (final device in members) {
          if (device.id == hub.id) continue;
          final key = [hub.id, device.id]..sort();
          if (edgeKeys.add(key.join('|'))) {
            edges.add(MeshGraphEdge(hub.id, device.id));
          }
        }
      } else if (cluster.label.isNotEmpty && members.isNotEmpty) {
        labels[members.first.id] = cluster.label;
      }
    }

    var nextGroup = activeClusters.length;
    for (final device in widget.devices) {
      groups.putIfAbsent(device.id, () => nextGroup++);
    }
    return _MeshGraphData(
      devices: widget.devices,
      edges: edges,
      groups: groups,
      hubIds: hubIds,
      labels: labels,
    );
  }

  NetworkDevice? _findHub(List<NetworkDevice> devices) {
    for (final device in devices) {
      if (widget.gateway != null &&
          device.ipAddresses.contains(widget.gateway)) {
        return device;
      }
    }
    for (final device in devices) {
      if (device.category == DeviceCategory.router) return device;
    }
    for (final device in devices) {
      if (device.sources.contains(DiscoverySource.localInterface)) {
        return device;
      }
    }
    return null;
  }

  Widget _buildGraphSurface(
    BuildContext context,
    _MeshGraphData graph,
    MeshGraphLayout layout,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF0D0E13)
        : const Color(0xFFF2F3F7);
    final foreground = isDark
        ? const Color(0xFFE8E9F1)
        : const Color(0xFF252631);
    final focusedId = _hoveredId ?? _selectedId;
    final relatedIds = <String>{?focusedId};
    if (focusedId != null) {
      for (final edge in graph.edges.where((edge) => edge.touches(focusedId))) {
        relatedIds.add(edge.other(focusedId));
      }
    }

    return ColoredBox(
      color: background,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _transformationController,
              boundaryMargin: const EdgeInsets.all(180),
              minScale: 0.28,
              maxScale: 3.5,
              constrained: false,
              child: SizedBox(
                width: layout.size.width,
                height: layout.size.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        key: const ValueKey('mesh-graph-background'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selectedId = null),
                        child: CustomPaint(
                          painter: _ObsidianGraphPainter(
                            positions: layout.positions,
                            edges: graph.edges,
                            focusedId: focusedId,
                            background: background,
                            isDark: isDark,
                          ),
                        ),
                      ),
                    ),
                    for (final entry in graph.labels.entries)
                      if (layout.positions[entry.key] case final position?)
                        Positioned(
                          left: position.dx - 72,
                          top: position.dy - 53,
                          width: 144,
                          child: IgnorePointer(
                            child: Text(
                              entry.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: foreground.withValues(alpha: 0.62),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    for (final device in graph.devices)
                      if (layout.positions[device.id] case final position?)
                        Positioned(
                          left: position.dx - 58,
                          top: position.dy - 28,
                          width: 116,
                          height: 72,
                          child: _ObsidianGraphNode(
                            key: ValueKey('mesh-node-${device.id}'),
                            device: device,
                            isHub: graph.hubIds.contains(device.id),
                            isNew: widget.newDeviceIds.contains(device.id),
                            isFocused: focusedId == device.id,
                            isRelated:
                                focusedId == null ||
                                relatedIds.contains(device.id),
                            showLabel:
                                graph.devices.length <= 32 ||
                                focusedId == device.id ||
                                graph.hubIds.contains(device.id) ||
                                device.sources.contains(
                                  DiscoverySource.localInterface,
                                ),
                            isDark: isDark,
                            onEnter: () =>
                                setState(() => _hoveredId = device.id),
                            onExit: () {
                              if (_hoveredId == device.id) {
                                setState(() => _hoveredId = null);
                              }
                            },
                            onTap: () {
                              setState(() => _selectedId = device.id);
                              widget.onDeviceTap(device);
                            },
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 10,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: background.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        graph.groups.values.toSet().length > 1
                            ? '메시 그래프 · 네트워크 ${graph.groups.values.toSet().length}개'
                            : '메시 그래프',
                        style: TextStyle(
                          color: foreground,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${graph.devices.length}개 노드 · ${graph.edges.length}개 관계',
                        style: TextStyle(
                          color: foreground.withValues(alpha: 0.62),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: _GraphControls(
              background: background,
              foreground: foreground,
              onZoomIn: () => _zoom(1.22),
              onZoomOut: () => _zoom(1 / 1.22),
              onFit: _fitGraph,
            ),
          ),
          Positioned(
            right: 10,
            top: 52,
            child: _GraphLegend(
              background: background,
              foreground: foreground,
              isDark: isDark,
            ),
          ),
          if (widget.framed)
            Positioned(
              left: 12,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: background.withValues(alpha: 0.84),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  child: Text(
                    '드래그로 이동 · 스크롤로 확대 · 노드를 눌러 상세 확인',
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.62),
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _makeLayoutKey(_MeshGraphData graph, Size size) {
    final ids = graph.devices.map((device) => device.id).toList()..sort();
    final edges =
        graph.edges.map((edge) => '${edge.sourceId}>${edge.targetId}').toList()
          ..sort();
    return '${size.width.round()}x${size.height.round()}|${ids.join(',')}|${edges.join(',')}';
  }

  void _scheduleFit() {
    if (_fitScheduled) return;
    _fitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitScheduled = false;
      if (mounted) _fitGraph();
    });
  }

  void _fitGraph() {
    final layout = _layout;
    if (layout == null || _viewportSize.isEmpty) return;
    final scale =
        math
            .min(
              _viewportSize.width / layout.size.width,
              _viewportSize.height / layout.size.height,
            )
            .clamp(0.28, 1.0) *
        0.94;
    final dx = (_viewportSize.width - layout.size.width * scale) / 2;
    final dy = (_viewportSize.height - layout.size.height * scale) / 2;
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _zoom(double factor) {
    final next = _transformationController.value.clone()
      ..scaleByDouble(factor, factor, factor, 1);
    _transformationController.value = next;
  }
}

class _MeshGraphData {
  const _MeshGraphData({
    required this.devices,
    required this.edges,
    required this.groups,
    required this.hubIds,
    required this.labels,
  });

  final List<NetworkDevice> devices;
  final List<MeshGraphEdge> edges;
  final Map<String, int> groups;
  final Set<String> hubIds;
  final Map<String, String> labels;
}

class _ObsidianGraphPainter extends CustomPainter {
  const _ObsidianGraphPainter({
    required this.positions,
    required this.edges,
    required this.focusedId,
    required this.background,
    required this.isDark,
  });

  final Map<String, Offset> positions;
  final List<MeshGraphEdge> edges;
  final String? focusedId;
  final Color background;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.035);
    for (var x = 24.0; x < size.width; x += 36) {
      for (var y = 24.0; y < size.height; y += 36) {
        canvas.drawCircle(Offset(x, y), 0.8, dotPaint);
      }
    }

    for (final edge in edges) {
      final source = positions[edge.sourceId];
      final target = positions[edge.targetId];
      if (source == null || target == null) continue;
      final highlighted = focusedId != null && edge.touches(focusedId!);
      final faded = focusedId != null && !highlighted;
      final paint = Paint()
        ..color = const Color(
          0xFF777DA7,
        ).withValues(alpha: faded ? 0.06 : (highlighted ? 0.78 : 0.30))
        ..strokeWidth = highlighted ? 2.2 : 1.15
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(source, target, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ObsidianGraphPainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.edges != edges ||
        oldDelegate.focusedId != focusedId ||
        oldDelegate.background != background;
  }
}

class _ObsidianGraphNode extends StatelessWidget {
  const _ObsidianGraphNode({
    super.key,
    required this.device,
    required this.isHub,
    required this.isNew,
    required this.isFocused,
    required this.isRelated,
    required this.showLabel,
    required this.isDark,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
  });

  final NetworkDevice device;
  final bool isHub;
  final bool isNew;
  final bool isFocused;
  final bool isRelated;
  final bool showLabel;
  final bool isDark;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualCategory = _visualCategory(device.category);
    final color = _categoryColor(visualCategory, isDark);
    final diameter = switch (visualCategory) {
      _GraphVisualCategory.router => 40.0,
      _GraphVisualCategory.computer => 30.0,
      _GraphVisualCategory.phone => 25.0,
      _GraphVisualCategory.television => 28.0,
      _GraphVisualCategory.appliance => 25.0,
      _GraphVisualCategory.other => 22.0,
    };
    final labelColor = isDark
        ? const Color(0xFFE8E9F1)
        : const Color(0xFF252631);
    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: Tooltip(
        waitDuration: const Duration(milliseconds: 250),
        message: [
          device.displayName,
          if (device.ipAddresses.isNotEmpty) device.ipAddresses.join(', '),
        ].join('\n'),
        child: Semantics(
          button: true,
          label: '${device.displayName} 장비 상세 열기',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(34),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: isRelated ? 1 : 0.18,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 42,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            width: diameter + (isFocused ? 6 : 0),
                            height: diameter + (isFocused ? 6 : 0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                center: const Alignment(-0.34, -0.38),
                                radius: 0.86,
                                colors: [
                                  Color.lerp(Colors.white, color, 0.28)!,
                                  color,
                                  Color.lerp(color, Colors.black, 0.48)!,
                                ],
                                stops: const [0, 0.46, 1],
                              ),
                              border: Border.all(
                                color: isFocused
                                    ? Color.lerp(Colors.white, color, 0.30)!
                                    : color.withValues(alpha: 0.78),
                                width: isFocused ? 2.4 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(
                                    alpha: isFocused ? 0.48 : 0.24,
                                  ),
                                  blurRadius: isFocused ? 13 : 7,
                                  spreadRadius: isFocused ? 2 : 0,
                                ),
                                const BoxShadow(
                                  color: Color(0x66000000),
                                  offset: Offset(1.5, 2.5),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          if (isNew)
                            Positioned(
                              right: 1,
                              top: 1,
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF5A67),
                                  shape: BoxShape.circle,
                                ),
                                child: const SizedBox.square(dimension: 8),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (showLabel)
                      SizedBox(
                        width: 112,
                        child: Text(
                          device.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: labelColor.withValues(alpha: 0.88),
                            fontSize: 10,
                            fontWeight: isHub
                                ? FontWeight.w700
                                : FontWeight.w500,
                            height: 1.1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GraphControls extends StatelessWidget {
  const _GraphControls({
    required this.background,
    required this.foreground,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final Color background;
  final Color foreground;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(
            key: const ValueKey('mesh-zoom-out'),
            icon: Icons.remove,
            tooltip: '축소',
            onPressed: onZoomOut,
          ),
          _button(
            key: const ValueKey('mesh-fit'),
            icon: Icons.center_focus_strong,
            tooltip: '전체 그래프 맞춤',
            onPressed: onFit,
          ),
          _button(
            key: const ValueKey('mesh-zoom-in'),
            icon: Icons.add,
            tooltip: '확대',
            onPressed: onZoomIn,
          ),
        ],
      ),
    );
  }

  Widget _button({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      key: key,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      color: foreground.withValues(alpha: 0.78),
      iconSize: 17,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

class _GraphLegend extends StatelessWidget {
  const _GraphLegend({
    required this.background,
    required this.foreground,
    required this.isDark,
  });

  final Color background;
  final Color foreground;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    const entries = [
      (_GraphVisualCategory.router, 'Wi-Fi 공유기'),
      (_GraphVisualCategory.computer, 'PC'),
      (_GraphVisualCategory.phone, '핸드폰'),
      (_GraphVisualCategory.television, '모니터/TV'),
      (_GraphVisualCategory.appliance, '가전제품'),
      (_GraphVisualCategory.other, '기타'),
    ];
    return IgnorePointer(
      child: Material(
        color: background.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.25,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '범례',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.76),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LegendSphere(
                          color: _categoryColor(entry.$1, isDark),
                          diameter: entry.$1 == _GraphVisualCategory.router
                              ? 13
                              : 10,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          entry.$2,
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.72),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendSphere extends StatelessWidget {
  const _LegendSphere({required this.color, required this.diameter});

  final Color color;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.34, -0.38),
          colors: [
            Color.lerp(Colors.white, color, 0.28)!,
            color,
            Color.lerp(color, Colors.black, 0.48)!,
          ],
          stops: const [0, 0.48, 1],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            offset: Offset(1, 1.5),
            blurRadius: 2,
          ),
        ],
      ),
      child: SizedBox.square(dimension: diameter),
    );
  }
}

enum _GraphVisualCategory {
  router,
  computer,
  phone,
  television,
  appliance,
  other,
}

_GraphVisualCategory _visualCategory(DeviceCategory category) {
  return switch (category) {
    DeviceCategory.router => _GraphVisualCategory.router,
    DeviceCategory.computer => _GraphVisualCategory.computer,
    DeviceCategory.phone => _GraphVisualCategory.phone,
    DeviceCategory.television => _GraphVisualCategory.television,
    DeviceCategory.appliance ||
    DeviceCategory.camera ||
    DeviceCategory.speaker ||
    DeviceCategory.printer ||
    DeviceCategory.iot => _GraphVisualCategory.appliance,
    DeviceCategory.unknown => _GraphVisualCategory.other,
  };
}

Color _categoryColor(_GraphVisualCategory category, bool isDark) {
  return switch (category) {
    _GraphVisualCategory.router => const Color(0xFFFFA43A),
    _GraphVisualCategory.computer => const Color(0xFF4E9DFF),
    _GraphVisualCategory.phone => const Color(0xFF4BD1A0),
    _GraphVisualCategory.television => const Color(0xFFA978F2),
    _GraphVisualCategory.appliance => const Color(0xFF37C2D0),
    _GraphVisualCategory.other =>
      isDark ? const Color(0xFFA7A9BA) : const Color(0xFF727586),
  };
}

int _stableHash(String value) {
  var hash = 2166136261;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0x7fffffff;
  }
  return hash;
}

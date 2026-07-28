class SduiTreeNode {
  const SduiTreeNode({
    required this.id,
    required this.label,
    this.expandable = false,
    this.children = const [],
    this.icon,
    this.meta = const {},
  });

  final String id;
  final String label;
  final bool expandable;
  final List<SduiTreeNode> children;
  final String? icon;
  final Map<String, Object?> meta;

  bool get hasChildren => children.isNotEmpty;

  SduiTreeNode copyWith({
    List<SduiTreeNode>? children,
    bool? expandable,
  }) {
    return SduiTreeNode(
      id: id,
      label: label,
      expandable: expandable ?? this.expandable,
      children: children ?? this.children,
      icon: icon,
      meta: meta,
    );
  }

  factory SduiTreeNode.fromJson(Map<String, dynamic> json) {
    final childrenRaw = json['children'];
    final children = <SduiTreeNode>[];
    if (childrenRaw is List) {
      for (final item in childrenRaw) {
        if (item is Map<String, dynamic>) {
          children.add(SduiTreeNode.fromJson(item));
        } else if (item is Map) {
          children.add(SduiTreeNode.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final metaRaw = json['meta'] ?? json['metadata'];
    final meta = <String, Object?>{};
    if (metaRaw is Map) {
      meta.addAll(metaRaw.map((k, v) => MapEntry('$k', v)));
    }
    if (json['nodeType'] != null && !meta.containsKey('nodeType')) {
      meta['nodeType'] = json['nodeType'];
    }
    if (json['node_type'] != null && !meta.containsKey('nodeType')) {
      meta['nodeType'] = json['node_type'];
    }

    return SduiTreeNode(
      id: '${json['id'] ?? ''}',
      label: '${json['label'] ?? json['name'] ?? json['id'] ?? ''}',
      expandable: json['expandable'] == true ||
          json['lazy'] == true ||
          json['hasChildren'] == true ||
          json['has_children'] == true,
      children: children,
      icon: json['icon'] as String?,
      meta: meta,
    );
  }
}

/// Schema returned by `extension.getTreeSchema`.
class SduiTreeSchema {
  const SduiTreeSchema({this.roots = const []});

  final List<SduiTreeNode> roots;

  factory SduiTreeSchema.fromJson(Map<String, dynamic> json) {
    final rootsRaw =
        json['roots'] ?? json['rootNodes'] ?? json['children'] ?? json['nodes'];
    final roots = <SduiTreeNode>[];
    if (rootsRaw is List) {
      for (final item in rootsRaw) {
        if (item is Map<String, dynamic>) {
          roots.add(SduiTreeNode.fromJson(item));
        } else if (item is Map) {
          roots.add(SduiTreeNode.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return SduiTreeSchema(roots: roots);
  }
}

/// Loads children for an expandable node (`fetchTreeChildren` RPC).
typedef SduiFetchTreeChildren = Future<List<SduiTreeNode>> Function(
    String nodeId);

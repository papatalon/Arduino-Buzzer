import 'dart:convert';

enum WindowKind { main, popout }

class WindowLaunchArgs {
  const WindowLaunchArgs({required this.kind});

  final WindowKind kind;

  static WindowLaunchArgs parse(String raw) {
    if (raw.isEmpty) return const WindowLaunchArgs(kind: WindowKind.main);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final kind = WindowKind.values.byName(json['kind'] as String);
    return WindowLaunchArgs(kind: kind);
  }

  String encode() => jsonEncode({'kind': kind.name});
}

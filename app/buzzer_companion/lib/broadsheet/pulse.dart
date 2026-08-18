import 'package:flutter/material.dart';

// L'unique animation du design system (design_handoff_buzzer_console/
// README.md, "L'animation unique") : opacité 1 <-> .35, ease-in-out,
// en boucle. Un `delay` permet de décaler plusieurs pulsations entre elles
// (ex. les trois carrés de l'état "personne n'a buzzé").
class Pulse extends StatefulWidget {
  const Pulse({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1100),
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = Tween<double>(begin: 1, end: 0.35).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    Future.delayed(widget.delay, () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

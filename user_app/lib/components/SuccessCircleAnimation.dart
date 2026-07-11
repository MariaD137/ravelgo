import 'package:flutter/material.dart';

class SuccessCircleAnimation extends StatefulWidget {
  @override
  _CircularBorderAnimationState createState() => _CircularBorderAnimationState();
}

class _CircularBorderAnimationState extends State<SuccessCircleAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _showCheck = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(() {
      setState(() {});
    });

    _controller.forward().whenComplete(() {
      setState(() {
        _showCheck = true;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double progress = _controller.value;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: CustomPaint(
          painter: CircleBorderPainter(progress),
          child: SizedBox(
            width: 150,
            height: 150,
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: _showCheck ? 1.0 : 0.0,
                child: Icon(
                  Icons.check,
                  color: Colors.green,
                  size: 60,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CircleBorderPainter extends CustomPainter {
  final double progress;
  CircleBorderPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final startAngle = -90.0 * (3.1416 / 180); // start from top
    final sweepAngle = 2 * 3.1416 * progress;

    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
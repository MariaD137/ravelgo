import 'package:flutter/material.dart';

/// A confirmation dialog that requires a non-empty, trimmed reason before a
/// rejection can be confirmed — every backend rejection endpoint this app
/// calls (document review, vehicle approval, rental listing review, Car
/// Paddy review) enforces the same non-empty requirement server-side; this
/// is the one shared client-side prompt for all of them, so a driver always
/// knows what to fix before resubmitting.
///
/// Usage: call showDialog with builder `(_) =>
/// RejectReasonDialog(itemLabel: someLabel)` — a null result means cancelled.
class RejectReasonDialog extends StatefulWidget {
  final String itemLabel;
  const RejectReasonDialog({super.key, required this.itemLabel});

  @override
  State<RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<RejectReasonDialog> {
  final _controller = TextEditingController();
  bool get _valid => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reject "${widget.itemLabel}"'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 1000,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Reason for rejection',
          hintText: 'e.g. Photo is blurry, please retake it.',
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: _valid ? () => Navigator.of(context).pop(_controller.text.trim()) : null,
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

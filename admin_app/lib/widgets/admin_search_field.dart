import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// A server-side search box for an admin list screen. Debounced (350ms) so
/// it doesn't fire a request per keystroke, and every call resets to page 1
/// — a search narrowing the whole table from wherever the admin happened to
/// be paged to would otherwise silently look like "no results" instead of
/// what it actually is (page 4 of a now much shorter list).
///
/// This never filters client-side: [onChanged] is expected to re-fetch from
/// the backend's own ?q= support, the same real search every list screen
/// this widget is used on already has server-side.
class AdminSearchField extends StatefulWidget {
  final String hintText;
  final ValueChanged<String?> onChanged;
  const AdminSearchField({super.key, required this.hintText, required this.onChanged});

  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      widget.onChanged(value.trim().isEmpty ? null : value.trim());
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    widget.onChanged(null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _clear),
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceElevated,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        onChanged: (v) {
          setState(() {}); // toggles the clear button
          _onChanged(v);
        },
      ),
    );
  }
}

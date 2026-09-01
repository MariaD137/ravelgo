import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/places_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Address search backed by the RavelGo Places proxy (Google Places under the
/// hood, server-side). Pops with the chosen [PlaceLocation] — address +
/// coordinates — so the ride flow gets a real destination it can price and
/// send to the backend, not just a name string.
class PlaceSearchScreen extends StatefulWidget {
  final String title;
  const PlaceSearchScreen({super.key, this.title = 'Where to?'});

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = [];
  bool _loading = false;
  bool _resolving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Debounce so we don't fire a paid Places request on every keystroke.
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _suggestions = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await PlacesApi.autocomplete(q);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException && e.statusCode == 503
            ? 'Address search isn\'t available right now.'
            : 'Could not search addresses - check your connection.';
      });
    }
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    setState(() => _resolving = true);
    try {
      final place = await PlacesApi.details(suggestion.placeId);
      if (!mounted) return;
      Navigator.of(context).pop(place);
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load that place - try another.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: const BackButton(color: AppColors.textPrimary),
        title: Text(widget.title, style: const TextStyle(color: AppColors.textPrimary)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onChanged,
                      decoration: const InputDecoration(
                        hintText: 'Search for a destination',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_loading)
                    const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: AppColors.error)),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = _suggestions[i];
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined, color: AppColors.textPrimary),
                  title: Text(s.description),
                  onTap: _resolving ? null : () => _select(s),
                );
              },
            ),
          ),
          if (_resolving) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}

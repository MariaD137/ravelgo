import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/places_api.dart';
import 'package:ravelgo_user_app/views/TexiModule/SelectRide.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Destination search that feeds the ride flow.
///
/// Address search + geocoding go through the RavelGo backend Places proxy (see
/// services/places_api.dart), NOT a direct browser call to Google — Google's
/// Places web-service endpoints send no CORS headers, so the old direct call
/// silently failed on Flutter Web. Selecting a place resolves it to real
/// coordinates and carries them into SelectRide so the trip can be priced.
class FindRouteScreen extends StatefulWidget {
  const FindRouteScreen({super.key});

  @override
  State<FindRouteScreen> createState() => _FindRouteScreenState();
}

class _FindRouteScreenState extends State<FindRouteScreen> {
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
            : 'Could not load places - check your connection.';
      });
    }
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    setState(() => _resolving = true);
    try {
      final place = await PlacesApi.details(suggestion.placeId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => SelectRide(destination: place.address, initialDestination: place),
        ),
      );
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
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('Your route', style: TextStyle(color: AppColors.textPrimary)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.textMuted),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.textPrimary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onChanged,
                      decoration: const InputDecoration(
                        hintText: 'Where to?',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_loading)
                    const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_error!, style: const TextStyle(color: AppColors.error)),
              ),
            Expanded(
              child: ListView.separated(
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  return ListTile(
                    leading: const Icon(Icons.place_outlined, color: AppColors.textPrimary),
                    title: Text(s.description),
                    onTap: _resolving ? null : () => _select(s),
                  );
                },
              ),
            ),
            if (_resolving) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }
}

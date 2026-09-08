import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/courier_api.dart';
import 'package:ravelgo_user_app/services/places_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/Delivery/DeliveryTrackingScreen.dart';
import 'package:ravelgo_user_app/views/TexiModule/PlaceSearchScreen.dart';

/// The customer's "send a package" request form. Backed by the real
/// POST /api/courier-requests — the same endpoint a driver later browses and
/// accepts in driver_app. Price shown here is an estimate matching the
/// backend's flat rate table; the server always computes the authoritative
/// price when the request is created.
class SendPackageScreen extends StatefulWidget {
  const SendPackageScreen({super.key});

  @override
  State<SendPackageScreen> createState() => _SendPackageScreenState();
}

class _SendPackageScreenState extends State<SendPackageScreen> {
  static const _priceEstimates = {'SMALL': 800.0, 'MEDIUM': 1500.0, 'LARGE': 2500.0};
  static const _sizeLabels = {'SMALL': 'Small (envelope, small bag)', 'MEDIUM': 'Medium (box, backpack)', 'LARGE': 'Large (suitcase, multiple boxes)'};

  final _formKey = GlobalKey<FormState>();
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  final _recipientNameController = TextEditingController();
  final _recipientPhoneController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _packageSize = 'MEDIUM';
  bool _sending = false;
  // Coordinates resolved alongside the address text below — only set when the
  // sender actually picks a real place from search, never guessed. These are
  // what let the delivery-tracking map later show real pickup/dropoff pins
  // (see PRD audit: CourierRequest had no coordinates at all before this).
  PlaceLocation? _pickupLocation;
  PlaceLocation? _dropoffLocation;

  /// Opens the same real, Places-backed address search used by the ride
  /// booking flow, so pickup/drop-off here resolve to actual verified
  /// addresses instead of whatever free text a rider happens to type.
  Future<void> _pickAddress(
    TextEditingController controller, {
    required String title,
    required String hint,
    required void Function(PlaceLocation) onPicked,
  }) async {
    final place = await Navigator.of(context).push<PlaceLocation>(
      MaterialPageRoute(builder: (_) => PlaceSearchScreen(title: title, hint: hint)),
    );
    if (place == null || !mounted) return;
    setState(() {
      controller.text = place.address;
      onPicked(place);
    });
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _reviewAndSend() async {
    if (!_formKey.currentState!.validate()) return;
    final estimate = _priceEstimates[_packageSize]!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm delivery request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('From: ${_pickupController.text.trim()}'),
            const SizedBox(height: 4),
            Text('To: ${_dropoffController.text.trim()}'),
            const SizedBox(height: 4),
            Text('Recipient: ${_recipientNameController.text.trim()} · ${_recipientPhoneController.text.trim()}'),
            const SizedBox(height: 12),
            Text('Estimated price: ${Currency.format(estimate, decimals: 0)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final request = await CourierApi.create(
        pickupAddress: _pickupController.text.trim(),
        dropoffAddress: _dropoffController.text.trim(),
        packageDescription: _descriptionController.text.trim(),
        packageSize: _packageSize,
        recipientName: _recipientNameController.text.trim(),
        recipientPhone: _recipientPhoneController.text.trim(),
        pickupLat: _pickupLocation?.lat,
        pickupLng: _pickupLocation?.lng,
        dropoffLat: _dropoffLocation?.lat,
        dropoffLng: _dropoffLocation?.lng,
      );
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DeliveryTrackingScreen(deliveryId: request.id)));
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Could not send this request.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estimate = _priceEstimates[_packageSize]!;
    return Scaffold(
      appBar: AppBar(title: const Text('Send a package')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _label('Pickup address'),
            TextFormField(
              controller: _pickupController,
              readOnly: true,
              onTap: () => _pickAddress(
                _pickupController,
                title: 'Pickup address',
                hint: 'Search for a pickup address',
                onPicked: (place) => _pickupLocation = place,
              ),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.trip_origin),
                suffixIcon: Icon(Icons.search),
                hintText: 'Search for a pickup address',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a pickup address' : null,
            ),
            const SizedBox(height: 16),
            _label('Drop-off address'),
            TextFormField(
              controller: _dropoffController,
              readOnly: true,
              onTap: () => _pickAddress(
                _dropoffController,
                title: 'Drop-off address',
                hint: 'Search for a drop-off address',
                onPicked: (place) => _dropoffLocation = place,
              ),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_on_outlined),
                suffixIcon: Icon(Icons.search),
                hintText: 'Search for a drop-off address',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a drop-off address' : null,
            ),
            const SizedBox(height: 16),
            _label('Recipient name'),
            TextFormField(
              controller: _recipientNameController,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the recipient\'s name' : null,
            ),
            const SizedBox(height: 16),
            _label('Recipient phone'),
            TextFormField(
              controller: _recipientPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_outlined), border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the recipient\'s phone number' : null,
            ),
            const SizedBox(height: 16),
            _label('Package size'),
            DropdownButtonFormField<String>(
              value: _packageSize,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _sizeLabels.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _packageSize = v ?? _packageSize),
            ),
            const SizedBox(height: 16),
            _label('What are you sending? (optional details)'),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'e.g. Documents, birthday gift…', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Briefly describe the package' : null,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Estimated price', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(Currency.format(estimate, decimals: 0), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _sending ? null : _reviewAndSend,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Review & send', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
      );
}

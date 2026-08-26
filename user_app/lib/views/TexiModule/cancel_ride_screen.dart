import 'package:flutter/material.dart';
import 'package:ravelgo_user/services/api_client.dart';
import 'package:ravelgo_user/services/trip_service.dart';

class CancelRideScreen extends StatefulWidget {
  final String tripId;

  const CancelRideScreen({super.key, required this.tripId});

  @override
  State<CancelRideScreen> createState() => _CancelRideScreenState();
}

class _CancelRideScreenState extends State<CancelRideScreen> {
  int? selectedReasonIndex;
  bool _submitting = false;
  String? _error;
  final List<String> reasons = [
    "Long pick up time",
    "Accidental request",
    "Car not moving towards me",
    "Driver asked to cancel",
    "Driver not at pick up point",
  ];

  Future<void> _confirmCancel() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await TripService().cancelTrip(widget.tripId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Unable to cancel this trip. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _submitting ? null : () => Navigator.pop(context, false),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
              const SizedBox(height: 0),
              const Text(
                "What was the issue?",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 0),
                      ...List.generate(reasons.length, (index) => _buildRadioTile(index)),
                      _buildOtherOption(),
                      const SizedBox(height: 0),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              ],
              Container(
                padding: const EdgeInsets.all(4),
                color: Colors.grey.shade300,
                child: const Text(
                  "Note: A fee will be charged if you cancel more than 5 rides",
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (selectedReasonIndex == null || _submitting) ? null : _confirmCancel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedReasonIndex == null ? Colors.yellow[100] : Colors.yellow[700],
                    foregroundColor: Colors.black,
                    disabledForegroundColor: Colors.grey,
                    disabledBackgroundColor: Colors.yellow[100],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("DONE"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadioTile(int index) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          dense: true, // Reduces the height of the ListTile
          visualDensity: VisualDensity(horizontal: 0, vertical: -4), // Tighter vertical spacing
          title: Text(
            reasons[index],
            style: TextStyle(fontSize: 14), // Optional: smaller font size
          ),
          trailing: Radio<int>(
            value: index,
            // ignore: deprecated_member_use
            groupValue: selectedReasonIndex,
            // ignore: deprecated_member_use
            onChanged: (value) => setState(() => selectedReasonIndex = value),
            activeColor: Colors.black,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // reduces touch area padding
          ),
          onTap: () => setState(() => selectedReasonIndex = index),
        ),
        const Divider(height: 1, thickness: 0.5), // Minimal divider
      ],
    );
  }

  Widget _buildOtherOption() {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text("Others"),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        // Navigate to custom reason input
      },
    );
  }
}

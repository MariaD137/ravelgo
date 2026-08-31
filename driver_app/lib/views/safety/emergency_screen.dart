import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Safety & Emergency hub.
///
/// BACKEND BOUNDARY: no safety/alerting backend is connected, so nothing
/// here claims an alert was delivered. Emergency numbers copy to the
/// clipboard (no dialer plugin in this build), trusted contacts are kept
/// in local session state, and backend-dependent features say so.
class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  // LOCAL STATE ONLY: session-level trusted contacts.
  static final List<String> _trustedContacts = [];
  bool _sendingSos = false;

  Future<void> _sendSosAlert() async {
    setState(() => _sendingSos = true);
    try {
      await DriverApi.raiseSos(
        message: _trustedContacts.isEmpty ? null : 'Trusted contacts: ${_trustedContacts.join(', ')}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('SOS sent. The RavelGo safety team has been alerted.'),
        backgroundColor: AppColors.danger,
      ));
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _sendingSos = false);
    }
  }

  void _showEmergencyNumbers() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency assistance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'RavelGo\'s live SOS alerting is not connected in this build. '
                'For immediate help use the national emergency lines:'),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Emergency services'),
              subtitle: const Text('112'),
              trailing: const Icon(Icons.copy, size: 18),
              onTap: () => _copy('112'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Police'),
              subtitle: const Text('199'),
              trailing: const Icon(Icons.copy, size: 18),
              onTap: () => _copy('199'),
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _copy(String number) {
    Clipboard.setData(ClipboardData(text: number));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$number copied - paste it in your phone app to call')),
    );
  }

  Future<void> _manageTrustedContacts() async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Trusted contacts',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              const Text(
                'Saved for this session. Automatic trip sharing starts working once the trips service is connected.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              if (_trustedContacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No trusted contacts yet',
                      style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                for (final c in List<String>.from(_trustedContacts))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(c),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () {
                        _trustedContacts.remove(c);
                        setSheetState(() {});
                        setState(() {});
                      },
                    ),
                  ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(hintText: 'Name or phone number'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.primary),
                    onPressed: () {
                      final value = controller.text.trim();
                      if (value.isEmpty) return;
                      _trustedContacts.add(value);
                      controller.clear();
                      setSheetState(() {});
                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reportFraud() async {
    final controller = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report suspicious activity'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Describe the unusual booking or behavior...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim().isNotEmpty),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (submitted == true && mounted) {
      try {
        await DriverApi.reportFraud(message: controller.text.trim());
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Report submitted to the safety team.')));
      } catch (e) {
        if (!mounted) return;
        final msg = e is ApiException ? e.message : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Safety & Emergency")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                const Icon(Icons.shield, color: AppColors.danger, size: 40),
                const SizedBox(height: 10),
                const Text("In an emergency, get help immediately",
                    textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _showEmergencyNumbers,
                    icon: const Icon(Icons.sos),
                    label: const Text("SOS – Emergency assistance"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _sendingSos ? null : _sendSosAlert,
                    icon: _sendingSos
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.campaign_outlined, color: AppColors.danger),
                    label: Text(_sendingSos ? 'Sending…' : 'Alert RavelGo safety team',
                        style: const TextStyle(color: AppColors.danger)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                AppComponents.tile(
                    title: "Trusted contacts",
                    subtitle: _trustedContacts.isEmpty
                        ? "Add people to share trip details with"
                        : "${_trustedContacts.length} contact${_trustedContacts.length == 1 ? '' : 's'} added",
                    leading: Icons.people_outline,
                    onTap: _manageTrustedContacts),
                AppComponents.divider(),
                AppComponents.tile(
                    title: "Emergency ride scheduling",
                    subtitle: "Priority routing to hospitals & safe zones",
                    leading: Icons.local_hospital_outlined,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Emergency scheduling requires the dispatch service - not available in this build'),
                      ));
                    }),
                AppComponents.divider(),
                AppComponents.tile(
                    title: "Fraud & suspicious activity",
                    subtitle: "Report unusual booking behavior",
                    leading: Icons.warning_amber_outlined,
                    onTap: _reportFraud),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

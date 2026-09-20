import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

/// The pre-approval card on the driver home screen. Every branch reflects a
/// real, distinct backend outcome; none of them is a default the UI made up:
///
///   * not fetched yet            -> "Checking your account status…"
///   * fetch failed, nothing known -> the failure, with a retry
///   * Driver.status SUSPENDED    -> "Account suspended"
///   * Driver.status PENDING_REVIEW -> "Application under review" plus the
///     real per-document review state from the same GET /drivers/me
///   * anything else              -> the raw status, verbatim
///
/// "Application under review" therefore appears ONLY when the backend said
/// PENDING_REVIEW — never because the profile hasn't loaded or the request
/// failed.
class DriverAccountStatusCard extends StatelessWidget {
  final DriverProfile profile;
  final DriverProfileLoadState loadState;
  final String? loadError;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenDocuments;

  const DriverAccountStatusCard({
    super.key,
    required this.profile,
    required this.loadState,
    required this.loadError,
    required this.onRefresh,
    required this.onOpenDocuments,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String title;
    final String body;
    Widget? action;

    if (loadState == DriverProfileLoadState.loading ||
        (!profile.hasStatus && loadError == null)) {
      icon = Icons.sync;
      color = AppColors.textMuted;
      title = "Checking your account status…";
      body = "Fetching your driver profile from RavelGo.";
    } else if (!profile.hasStatus) {
      icon = Icons.cloud_off;
      color = AppColors.danger;
      title = "Couldn't load your account status";
      body = loadError ?? "Please check your connection and try again.";
      action = TextButton(onPressed: onRefresh, child: const Text("Try again"));
    } else if (profile.isSuspended) {
      icon = Icons.block;
      color = AppColors.danger;
      title = "Account suspended";
      body =
          "Your driver account is suspended and can't go online. Contact support for details.";
    } else if (profile.isPendingReview) {
      icon = Icons.hourglass_top;
      color = AppColors.warning;
      title = "Application under review";
      body = pendingReviewBody(profile);
      action = TextButton(
        onPressed: onOpenDocuments,
        child: Text(
          profile.documents.isEmpty ? "Upload documents" : "View documents",
        ),
      );
    } else {
      // A status value this build doesn't know. Show it verbatim rather than
      // guessing what it means.
      icon = Icons.help_outline;
      color = AppColors.textMuted;
      title = "Account status: ${profile.status}";
      body = "Pull down to refresh, or contact support if this persists.";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppComponents.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (loadError != null && profile.hasStatus) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Last refresh failed: $loadError",
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (action != null)
            Align(alignment: Alignment.centerRight, child: action),
        ],
      ),
    );
  }

  /// Describes the real per-document review state alongside the pending
  /// application, so the driver can see what (if anything) is still on them.
  /// Documents being approved is not, by itself, what unlocks going online —
  /// an admin's explicit approval of the driver is (Driver.status) — and the
  /// wording is careful not to promise otherwise.
  @visibleForTesting
  static String pendingReviewBody(DriverProfile profile) {
    if (profile.documents.isEmpty) {
      return "Upload your documents so our team can review your application. "
          "We'll notify you once it's approved and you can go online.";
    }
    final parts = <String>[
      if (profile.approvedDocumentCount > 0)
        "${profile.approvedDocumentCount} approved",
      if (profile.pendingDocumentCount > 0)
        "${profile.pendingDocumentCount} under review",
      if (profile.rejectedDocumentCount > 0)
        "${profile.rejectedDocumentCount} rejected",
    ];
    final summary = parts.isEmpty
        ? "${profile.documents.length} on file"
        : parts.join(" · ");
    final rejectedHint = profile.rejectedDocumentCount > 0
        ? " Re-upload any rejected document to keep your application moving."
        : "";
    return "Documents: $summary.$rejectedHint We'll notify you as soon as our team approves your application and you can go online.";
  }
}

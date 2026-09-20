import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/services/driver_profile_events.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/account/account_screen.dart';
import 'package:ravelgo_driver_app/views/earnings/earnings_screen.dart';
import 'package:ravelgo_driver_app/views/home/driver_home_screen.dart';
import 'package:ravelgo_driver_app/views/shell/side_menu_driver.dart';
import 'package:ravelgo_driver_app/views/trips/my_trips_screen.dart';

/// Whether the driver record has been fetched from the backend yet, and how
/// that went. Lets the home screen distinguish "we don't know yet" and "we
/// couldn't find out" from a real PENDING_REVIEW — previously a failed fetch
/// silently fell back to a default profile that *looked* like "under review".
enum DriverProfileLoadState { loading, ready, error }

class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> with WidgetsBindingObserver {
  int _index = 0;
  DriverProfile _profile = const DriverProfile();
  DriverProfileLoadState _loadState = DriverProfileLoadState.loading;
  String? _loadError;
  bool _togglingOnline = false;
  bool _loadingProfile = false;
  Timer? _statusPoll;

  // Driver.status only ever changes server-side (an admin decision), and there
  // is no realtime channel for it — the backend sends an in-app/device
  // notification, which is only a prompt to re-fetch. While the decision is
  // still pending, poll at a modest interval so the app converges on the
  // real status even if that notification never arrives (push unconfigured,
  // app in a browser tab, token registered late). Once approved, a slower
  // poll still picks up a later suspension.
  static const _pendingPollInterval = Duration(seconds: 30);
  static const _approvedPollInterval = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DriverProfileEvents.addListener(_onProfileEvent);
    _loadProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DriverProfileEvents.removeListener(_onProfileEvent);
    _statusPoll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Coming back from the background is exactly when an admin decision is
      // most likely to have landed while we weren't looking.
      _loadProfile(quiet: true);
      _schedulePoll();
    } else if (state == AppLifecycleState.paused) {
      _statusPoll?.cancel();
      _statusPoll = null;
    }
  }

  void _onProfileEvent() => _loadProfile(quiet: true);

  void _schedulePoll() {
    _statusPoll?.cancel();
    final interval = _profile.isApproved
        ? _approvedPollInterval
        : _pendingPollInterval;
    _statusPoll = Timer(interval, () {
      _statusPoll = null;
      if (!mounted) return;
      _loadProfile(quiet: true).whenComplete(_schedulePoll);
    });
  }

  /// Fetch the driver's own record — the ONLY place this app learns its
  /// approval status from. `quiet` keeps the current profile on screen while
  /// re-fetching (pull-to-refresh, background poll, notification tap) instead
  /// of flashing the loading state.
  Future<void> _loadProfile({bool quiet = false}) async {
    if (_loadingProfile) return;
    _loadingProfile = true;
    if (!quiet && mounted) {
      setState(() {
        _loadState = DriverProfileLoadState.loading;
        _loadError = null;
      });
    }
    try {
      final record = await _fetchOrProvision();
      if (!mounted) return;
      setState(() {
        _profile = DriverProfile.fromRecord(record);
        _loadState = DriverProfileLoadState.ready;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Keep whatever real status we last saw (a quiet refresh that fails
        // must not blank a known ACTIVE/PENDING state), but surface the
        // failure so a never-loaded profile is never mistaken for "pending".
        _loadState = _profile.hasStatus
            ? DriverProfileLoadState.ready
            : DriverProfileLoadState.error;
        _loadError = e is ApiException
            ? e.message
            : 'Could not reach the server.';
      });
    } finally {
      _loadingProfile = false;
      if (mounted && _statusPoll == null) _schedulePoll();
    }
  }

  /// GET /drivers/me, creating the application first if this identity has no
  /// driver profile yet (or its access token predates the server granting it
  /// the Driver group).
  ///
  /// Order matters: reading first means an existing driver's launch is one
  /// GET, not a re-submitted application on every app open. Only a 404 (no
  /// profile) or a 403 (token lacks the Driver group) triggers
  /// POST /drivers/apply — which is idempotent server-side — followed by a
  /// forced token refresh so the group the server just granted is actually
  /// on the token we send next (see AuthService.refreshTokens).
  Future<DriverRecord> _fetchOrProvision() async {
    try {
      return await DriverApi.getMe();
    } on ApiException catch (e) {
      if (e.statusCode != 404 && e.statusCode != 403) rethrow;
    }

    final applied = await DriverApi.provisionMe();
    if (!AuthService.hasGroup('Driver')) {
      await AuthService.refreshTokens();
    }
    try {
      return await DriverApi.getMe();
    } on ApiException catch (e) {
      // The application itself succeeded (it's the source of truth), but this
      // token still can't read it — the refresh failed or hasn't propagated.
      // Show the record the server just returned rather than nothing.
      if (applied != null && e.statusCode == 403) return applied;
      rethrow;
    }
  }

  Future<void> _setOnline(bool value) async {
    if (_togglingOnline) return;
    setState(() => _togglingOnline = true);
    try {
      final record = await DriverApi.setOnline(value);
      if (!mounted) return;
      setState(
        () => _profile = _profile.copyWith(
          isOnline: record.isOnline,
          status: record.status,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException && e.statusCode == 409
          ? 'Your account isn\'t approved to go online yet.'
          : (e is ApiException && e.statusCode == 403
                ? 'Your account isn\'t set up as a driver yet.'
                : e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      // A 409 means our view of the status is stale (e.g. just suspended) —
      // re-read it rather than leaving the toggle visible.
      if (e is ApiException && e.statusCode == 409) _loadProfile(quiet: true);
    } finally {
      if (mounted) setState(() => _togglingOnline = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DriverHomeScreen(
        profile: _profile,
        loadState: _loadState,
        loadError: _loadError,
        onOnlineToggle: _setOnline,
        onRefresh: () => _loadProfile(quiet: _profile.hasStatus),
      ),
      const MyTripsScreen(embedded: true),
      const EarningsScreen(embedded: true),
      AccountScreen(embedded: true, profile: _profile),
    ];

    return Scaffold(
      drawer: SideMenuDriver(profile: _profile),
      body: pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        selectedItemColor: AppColors.primaryDark,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            label: "Trips",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.payments_outlined),
            label: "Earnings",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: "Account",
          ),
        ],
      ),
    );
  }
}

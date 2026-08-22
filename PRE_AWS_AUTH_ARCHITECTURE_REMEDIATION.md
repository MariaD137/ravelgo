# Pre-AWS Auth Architecture Remediation

Scope: fix a real-release-build crash and a real login-bypass bug found during a live
end-to-end testing pass, across all three Flutter apps (`driver_app`, `user_app`,
`admin_app`), **without** implementing Cognito, without creating AWS resources, and
without weakening the existing release-mode safety guard.

**Final verdict: AUTH ARCHITECTURE READY FOR COGNITO.** (Not "Cognito integrated" —
Cognito still does not exist anywhere in this codebase or in AWS.)

---

## 1. Root cause of the release crash

`driver_app`'s `DriverSession` held a `static final` singleton that eagerly built a
shared `ApiClient()` with zero arguments. `ApiClient`'s constructor defaulted a missing
`AuthProvider` to `DevOnlyAuthProvider.instance`. `DevOnlyAuthProvider`'s constructor
correctly and intentionally throws `StateError` when `kReleaseMode` is `true` — that
guard is a deliberate safety feature, not a bug. The bug was everything upstream of it:
the instant any screen touched `DriverSession.instance` in a release build, the implicit
construction chain `DriverSession → ApiClient() → DevOnlyAuthProvider.instance` ran and
threw, crashing the app. There was no explicit choice being made anywhere about which
`AuthProvider` a release build should use — the app just fell into the dev-only one by
default and then got protected against itself, fatally.

A second, related bug (found in the same testing pass): every Login screen's "Sign in"
button navigated straight into the app via `Navigator.pushAndRemoveUntil(...)` without
ever calling any `AuthProvider`. Authentication state was never modeled — navigation
*was* the auth state.

## 2. Exact files changed

24 files changed, 935 insertions(+), 141 deletions(-). No backend files touched.

**driver_app**
- `lib/services/api/auth_provider.dart` — added `AuthStatus` enum, `UnauthenticatedAuthProvider`, `createDefaultAuthProvider()`.
- `lib/services/api/api_client.dart` — default `AuthProvider` fallback changed from `DevOnlyAuthProvider.instance` to `createDefaultAuthProvider()`; added `onUnauthorized` callback fired on HTTP 401.
- `lib/services/driver_session.dart` — rewritten from an eager `static final` singleton to `DriverSession.initialize(...)` / `DriverSession.instance` (throws if read before init); added `signIn`/`signOut` driving `AuthStatus`; added `resetForTesting`/`clearForTesting`.
- `lib/main.dart` — new composition root: builds the one `AuthProvider`, builds `ApiClient` with it, calls `DriverSession.initialize(...)` before `runApp()`.
- `lib/views/auth/login_screen.dart` — rewritten to a `StatefulWidget` that calls `DriverSession.instance.signIn(...)`, handles loading/failure, navigates only on success; dev-only token-injection UI compiled out via `if (!kReleaseMode)`.
- `lib/views/shell/side_menu_driver.dart`, `lib/views/account/account_screen.dart` — "Log out" now calls `DriverSession.instance.signOut()` before navigating (previously it just changed routes without clearing the session — a second real bug found during the sweep).
- `test/auth_architecture_test.dart` (new), plus `driver_session_test.dart`, `driver_home_gating_test.dart`, `widget_test.dart` updated for the new DI shape.

**user_app**
- `lib/services/api/auth_provider.dart`, `lib/services/api/api_client.dart` — same additions as driver_app.
- `lib/main.dart` — composition root builds `authProvider`, passes it down via constructor.
- `lib/views/SplashScreen/SplashScreen.dart`, `lib/views/Login/login.dart` — `Login` rewritten to a `StatefulWidget` taking an injected `AuthProvider`, drives local `AuthStatus`, calls `AuthProvider.login(...)` on submit, navigates only on success.
- `test/services/api/auth_architecture_test.dart` (new), `test/widget_test.dart` updated.

**admin_app**
- `lib/services/api/auth_provider.dart`, `lib/services/api/api_client.dart` — same additions.
- `lib/main.dart` — composition root.
- `lib/views/splash/splash_screen.dart`, `lib/views/auth/admin_login_screen.dart` — same Login rewrite pattern as user_app.
- `lib/views/shell/admin_shell.dart`, `lib/views/shell/side_menu_admin.dart` — `authProvider` threaded through; "Log out" now calls `authProvider.logout()` before navigating (previously never called `.logout()` at all — a second real bug found during the sweep, same class as driver_app's).
- `test/services/api/auth_architecture_test.dart` (new), `test/widget_test.dart` updated.

## 3. Authentication architecture — before

```
main() → runApp(MyApp())        // no AuthProvider decision made anywhere
Login screen → Navigator.pushAndRemoveUntil(HomeScreen)   // no AuthProvider call
DriverSession.instance (driver_app only) → static final ApiClient()
  → ApiClient(authProvider: null) → defaults to DevOnlyAuthProvider.instance
  → throws StateError in release builds the instant DriverSession is touched
```
Navigation was the only signal for "is the user logged in." No `AuthStatus`. No app ever
called `AuthProvider.login()`. `user_app` and `admin_app` had the identical Login-bypass
flaw as driver_app, though without the crash (they had no eager shared `ApiClient`
singleton to trip over — the same underlying mistake, just less severe by accident).

## 4. Authentication architecture — after

```
main() (composition root, all 3 apps)
  → authProvider = createDefaultAuthProvider()   // the ONE place this choice is made
       kReleaseMode ? UnauthenticatedAuthProvider() : DevOnlyAuthProvider.instance
  → apiClient = ApiClient(authProvider: authProvider, onUnauthorized: <clears session>)
  → (driver_app) DriverSession.initialize(authProvider: authProvider, apiClient: apiClient)
  → runApp(...)

Login screen (all 3 apps)
  → constructed with an injected AuthProvider (driver_app: via DriverSession.instance;
    user_app/admin_app: via a constructor parameter — no session singleton exists there)
  → Sign In: validate → AuthStatus.authenticating → AuthProvider.login(...)
      success → AuthStatus.authenticated → navigate
      failure → AuthStatus.authenticationFailed → show error, stay put
  → dev-only token-injection section compiled out entirely via `if (!kReleaseMode)`
```

`AuthStatus` (`unauthenticated | authenticating | authenticated | authenticationFailed`)
is now the source of truth; navigation follows it, never the reverse.
`ApiClient.onUnauthorized` fires on a real HTTP 401 and is wired at the composition root
to the app's sign-out path, so an expired/revoked token drops the app back to
unauthenticated instead of continuing to show screens that need a session that no longer
exists.

`DriverSession`'s singleton is no longer eager: `DriverSession.instance` throws a clear
`StateError` if read before `DriverSession.initialize(...)` runs, instead of silently
falling back to constructing anything. There is no code path left, in any of the three
apps, where an `ApiClient` or a session object can come into existence without an
explicit `AuthProvider` having been chosen first.

## 5. How Cognito will plug in later

`createDefaultAuthProvider()` is the single seam. When Cognito is deployed, its release
branch changes from `UnauthenticatedAuthProvider()` to a new `CognitoAuthProvider`
implementing the same `AuthProvider` interface (`login`, `logout`, `getAccessToken`,
`isAuthenticated`) — nothing else in any of the three apps needs to change, because
`ApiClient`, the session/session-equivalent, and the Login screens all depend on the
`AuthProvider` interface, never on a concrete implementation. This was true of the
existing `AuthProvider` abstraction already in the codebase (formalized in an earlier
pass) — this remediation reused it rather than inventing a second one, per the explicit
"do not duplicate authentication abstractions" instruction.

## 6. How local development authentication works

`DevOnlyAuthProvider` (pre-existing, unmodified in its core contract) is used for local
development and tests. Its `setToken(...)` method lets a developer or an integration
test paste/inject a token obtained some other way (a local backend's own test-token
minting, a test harness) — it never fabricates a token itself. Every Login screen now
has a `DEVELOPMENT ONLY` section (red text, clearly labeled, gated by
`if (!kReleaseMode) ...`) that calls `DevOnlyAuthProvider.instance.setToken(...)` and
then navigates only after that call — exercised by this remediation's own regression
tests and confirmed absent from the actual release build (see §10).

## 7. Why DevOnlyAuthProvider cannot ship in release

`DevOnlyAuthProvider`'s constructor throws `StateError` when `kReleaseMode` is `true` —
this guard already existed and was **not** touched, weakened, or bypassed anywhere in
this remediation. What changed is that nothing in production code paths can reach that
constructor anymore in a release build: `createDefaultAuthProvider()`'s release branch
returns `UnauthenticatedAuthProvider` instead, which is unconditionally safe to
construct (it never fabricates a session; `login()` on it always throws, `isAuthenticated()`
always returns `false`) and needs no such guard.

## 8. Tests added

New file per app (`driver_app/test/auth_architecture_test.dart`,
`user_app/test/services/api/auth_architecture_test.dart`,
`admin_app/test/services/api/auth_architecture_test.dart`), covering all 10 required
scenarios as they apply to each app's architecture:

1. **Release-safe dependency construction** — `ApiClient()` never throws; `createDefaultAuthProvider()` is the one factory point; `UnauthenticatedAuthProvider` never throws to construct.
2. **No implicit AuthProvider construction** — (driver_app) `DriverSession.instance` throws `StateError` if read before `initialize()`; `initialize()` accepts any `AuthProvider` implementation.
3. **Login invokes AuthProvider** — verified via a `_FakeAuthProvider` test double with a call counter.
4. **Failed auth does not navigate** — widget test: wrong credentials → error text shown, destination screen `findsNothing`.
5. **Successful dev auth navigates** — widget test: correct credentials via the fake provider → destination screen `findsOneWidget`.
6. **Authenticated API request receives token** — covered by each app's pre-existing `api_client_test.dart` bearer-token-attachment test (not duplicated here).
7. **401 causes appropriate session behavior** — `MockClient` returns a 401; `onUnauthorized` callback verified to fire exactly once before `ApiException` is thrown.
8. **Logout clears authentication state** — (driver_app) `signOut()` calls `AuthProvider.logout()`, resets `authStatus` and operational state; (admin_app) a widget test drives the actual side-menu "Log out" tap and asserts `logoutCallCount == 1` and navigation back to the login screen.
9. **DevOnlyAuthProvider cannot be constructed in release** — **cannot be expressed as a `flutter test`**, because `kReleaseMode` is a compile-time constant that no unit/widget test can flip to `true`; every test file documents this limitation inline. This scenario is instead proven empirically by an actual `flutter build web --release` (see §10) — the strongest verification actually available, per the task's own instruction to "create the strongest architecture-level test possible and explain the remaining limitation."
10. **No hardcoded authentication token exists** — proven structurally: `UnauthenticatedAuthProvider.getAccessToken()` always returns `null`, `DevOnlyAuthProvider` only ever holds a token it was explicitly given via `setToken(...)`, and the repo-wide grep sweep (§ below) found no literal token string anywhere in production code.

## 9. Tests executed

| Suite | Result |
|---|---|
| Backend (`npm test`) | **191/191 passing**, 0 failures — unchanged, backend was not touched |
| driver_app `flutter analyze` | 0 errors |
| driver_app `flutter test` | **38/38 passing** (27 pre-existing + 11 new) |
| user_app `flutter analyze` | 0 errors (175 pre-existing `info`-level lints, none new) |
| user_app `flutter test` | **30/30 passing** |
| admin_app `flutter analyze` | 0 errors |
| admin_app `flutter test` | **44/44 passing** |

One pre-existing, unrelated issue was found and *not* fixed (out of scope per the
"do not change existing working UI unnecessarily" constraint): `user_app`'s
`Home.dart` "Invite Card" wraps a `ListTile` in a colored `DecoratedBox`, which trips a
Material ink-visibility paint warning when the widget tree is fully exercised in a test.
It's drained via `tester.takeException()` in the one test that reaches that screen, with
an inline comment explaining it's unrelated to authentication.

## 10. Release build results

```
cd driver_app && flutter build web --release
✓ Built build/web
```
Succeeded cleanly (58.6s compile). Served the output locally and drove it with a real
headless Chromium via Playwright:

- The app loaded and painted the **Login screen** (logo, email/password fields, Sign In
  button) — **no crash**, and specifically no `DevOnlyAuthProvider must never be
  constructed in a release build` error, which is exactly what this release build would
  have thrown before this fix.
- The dev-only token-injection section (present in debug builds) was **absent**,
  confirming `if (!kReleaseMode) ...` was correctly compiled out.
- Tapping "Sign in" with empty fields showed a validation snackbar and did **not**
  navigate, did **not** crash, and did **not** silently authenticate.

## 11. Browser verification results

Performed via headless Chromium (Playwright, `/opt/pw-browsers/chromium`) serving
`driver_app/build/web` over a local static HTTP server. Screenshots were captured before
and after interacting with the Sign In button; both show the Login screen intact with no
uncaught page errors. (The Roboto webfont failed to load because `fonts.gstatic.com` is
blocked by this sandbox's outbound network policy — an environment limitation unrelated
to the app.)

`user_app` and `admin_app` were not release-built for the web in this pass — their
authentication architecture is verified via `flutter analyze`/`flutter test` only, per
the task's "if practical" phrasing for the other two apps. The critical, explicitly
required verification (driver_app no longer crashes) is the one performed empirically.

## 12. Remaining AWS/Cognito-dependent work

**FIXED NOW**
- Release-mode crash in driver_app (root cause eliminated, not papered over).
- Login-bypass bug in all three apps' Login screens.
- Two additional logout bugs found during the sweep (driver_app side menu + account
  screen, admin_app side menu) — logout now actually calls `AuthProvider.logout()`/
  `DriverSession.signOut()` before navigating, instead of just changing routes.
- Explicit `AuthStatus` state machine in place of navigation-as-truth.
- `ApiClient.onUnauthorized` wired to session sign-out on a real 401.
- DevOnlyAuthProvider's release-mode guard preserved exactly, and now genuinely
  unreachable from any release-build code path.

**READY FOR COGNITO**
- `AuthProvider` interface (`login`/`logout`/`getAccessToken`/`isAuthenticated`) is the
  only seam any of the three apps depend on.
- `createDefaultAuthProvider()` is the single point where a `CognitoAuthProvider` will
  be substituted in for the release branch.
- Token handling is fully centralized: UI never sees or injects an `Authorization`
  header; `ApiClient` alone owns that.

**REQUIRES AWS/COGNITO**
- The actual `CognitoAuthProvider` implementation (Amplify or raw Cognito SDK calls) —
  not started, and correctly so; there is no Cognito user pool to call yet.
- Any persistent/secure token storage across app restarts — deliberately not built.
  Building it now against nothing would mean inventing insecure storage or fake
  persistence; this is documented as **deferred until Cognito/secure-storage
  configuration exists**, not silently skipped.
- Real password/credential validation, MFA, password reset, session refresh — all
  Cognito-side concerns with no local substitute worth building.

---

## Final verdict

**AUTH ARCHITECTURE READY FOR COGNITO.**

Cognito is not integrated, and this remediation did not attempt to integrate it. What
changed is structural: every place that used to implicitly reach for an `AuthProvider`
now receives one explicitly from a single composition root, the release-mode safety
guard against `DevOnlyAuthProvider` is intact and now actually enforced (nothing in a
release build can reach it), and all three apps' Login screens genuinely authenticate
through that seam instead of bypassing it. When Cognito is deployed, the only new code
required is one `CognitoAuthProvider` class per the existing interface, substituted into
`createDefaultAuthProvider()`'s release branch.

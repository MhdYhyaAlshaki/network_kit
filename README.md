# network_kit

Reusable Flutter network toolkit built on `dio`, with:
- Configurable Dio factory
- Auth/refresh/cancel/language/general interceptors
- Connectivity abstraction (`NetworkInfo`)
- Page-scoped cancellation (`CancelTokenService`, `CancellablePage`)
- Host-driven preferences and side effects (no `get_it` dependency)

## Install

Add path dependency (or publish and use version):

```yaml
dependencies:
  network_kit:
    git: 
      https://github.com/MhdYhyaAlshaki/network_kit.git
```

## Example

A runnable Flutter example is available at `example/`.

From `packages/network_kit` run:

```bash
cd example
flutter pub get
flutter run
```

## Core Concepts

### 1) `DioPreferences`
Host app must provide token and language access:

```dart
class AppDioPreferences implements DioPreferences {
  @override
  String get accessToken => ...;

  @override
  String get refreshToken => ...;

  @override
  String get languageCode => ...;

  @override
  Future<void> setAccessToken(String token) async => ...;

  @override
  Future<void> setRefreshToken(String token) async => ...;
}
```

### 2) `NetworkConfig`
Defines network-level behavior:
- `baseUrl`
- `appVersion`
- `refreshPath`
- request timeouts + socket timeouts (`connectTimeout`, `receiveTimeout`, `idleTimeout`, `connectionTimeout`)
- auto OS header (configurable via `includeOsHeader` or `osOverride`)
- customizable header keys (`headerKeys`)
- optional Bearer prefix (`useBearerTokenPrefix`)
- logging toggle

### 3) `NetworkEvents`
App callbacks for side effects:
- `onUnauthorized`
- `onOldVersion`
- `onNeedCompleteProfile`
- `onVpnDetected`

## Create Dio

```dart
final cancelTokenService = CancelTokenService();

final factory = NetworkKitFactory(
  preferences: appDioPreferences,
  config: NetworkConfig(
    baseUrl: 'https://example.com/api/',
    appVersion: '1.0.0',
    enableLogging: true,
  ),
  events: NetworkEvents(
    onUnauthorized: () async {
      // logout + navigate
    },
    onOldVersion: (payload) async {
      // show update dialog
    },
  ),
  cancelTokenService: cancelTokenService,
  getDeviceToken: () async => null, // optional
);

final dio = await factory.createDio();
```

Advanced header configuration:

```dart
config: NetworkConfig(
  baseUrl: 'https://example.com/api/',
  appVersion: '1.0.0',
  useBearerTokenPrefix: false,
  includeOsHeader: true,
  headerKeys: const NetworkHeaderKeys(
    authorization: 'Authorization',
    language: 'X-Language',
  ),
)
```

## Connectivity

```dart
final networkInfo = NetworkInfoImplementer(
  Connectivity(),
  events: NetworkEvents(
    onVpnDetected: () async {
      // warning toast/dialog
    },
  ),
);

final connected = await networkInfo.isConnected;
```

## Request Cancellation

### Service usage

```dart
final token = cancelTokenService.getOrCreateCancelToken(pageKey);
cancelTokenService.cancelRequests(pageKey);
```

### `CancellablePage`

```dart
class MyPage extends CancellablePage {
  const MyPage({super.key, required super.cancelTokenService});

  @override
  CancellablePageState createState() => _MyPageState();
}

class _MyPageState extends CancellablePageState<MyPage> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold();
  }
}
```

## Response Status Codes

`network_kit` exposes `ResponseStatusCode` with numeric defaults and runtime overrides:

```dart
ResponseStatusCode.setCodeOverride(ResponseStatusCode.errorUnauthorized, '401');
ResponseStatusCode.setCodeOverrides({
  ResponseStatusCode.needToCompleteProfile: '299',
});
ResponseStatusCode.clearCodeOverride(ResponseStatusCode.needToCompleteProfile);
ResponseStatusCode.clearAllCodeOverrides();
```

## Exports

Import everything from:

```dart
import 'package:network_kit/network_kit.dart';
```

## Notes

- Package is Flutter-based (not pure Dart) because it includes widget and connectivity support.
- Package is DI-agnostic by design; host app owns wiring and side effects.
- Keep business/UI decisions in app callbacks, not in package internals.

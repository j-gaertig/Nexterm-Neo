import 'package:local_auth/local_auth.dart';

enum ScreenLockAuthResult { success, canceled, unavailable, lockedOut, failed }

extension ScreenLockAuthResultMessage on ScreenLockAuthResult {
  String get message {
    switch (this) {
      case ScreenLockAuthResult.success:
        return 'Authentication successful.';
      case ScreenLockAuthResult.canceled:
        return 'Authentication was canceled.';
      case ScreenLockAuthResult.unavailable:
        return 'Set up a screen lock (PIN, pattern, password, or biometrics) in your device settings and try again.';
      case ScreenLockAuthResult.lockedOut:
        return 'Too many attempts. Try again later.';
      case ScreenLockAuthResult.failed:
        return 'Authentication failed. Please try again.';
    }
  }
}

class ScreenLockService {
  ScreenLockService({LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;
  bool _authenticating = false;

  bool get isAuthenticating => _authenticating;

  Future<bool> isDeviceSupported() async {
    try {
      return await _authentication.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<ScreenLockAuthResult> authenticate({required String reason}) async {
    if (_authenticating) return ScreenLockAuthResult.failed;

    _authenticating = true;
    try {
      final authenticated = await _authentication.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return authenticated
          ? ScreenLockAuthResult.success
          : ScreenLockAuthResult.failed;
    } on LocalAuthException catch (error) {
      return _mapException(error.code);
    } catch (_) {
      return ScreenLockAuthResult.failed;
    } finally {
      _authenticating = false;
    }
  }

  Future<void> cancel() async {
    try {
      await _authentication.stopAuthentication();
    } catch (_) {}
  }

  ScreenLockAuthResult _mapException(LocalAuthExceptionCode code) {
    switch (code) {
      case LocalAuthExceptionCode.userCanceled:
        return ScreenLockAuthResult.canceled;
      case LocalAuthExceptionCode.noCredentialsSet:
      case LocalAuthExceptionCode.noBiometricHardware:
      case LocalAuthExceptionCode.noBiometricsEnrolled:
        return ScreenLockAuthResult.unavailable;
      case LocalAuthExceptionCode.temporaryLockout:
      case LocalAuthExceptionCode.biometricLockout:
        return ScreenLockAuthResult.lockedOut;
      case LocalAuthExceptionCode.systemCanceled:
      case LocalAuthExceptionCode.timeout:
        return ScreenLockAuthResult.canceled;
      case LocalAuthExceptionCode.authInProgress:
      case LocalAuthExceptionCode.uiUnavailable:
        return ScreenLockAuthResult.failed;
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
      case LocalAuthExceptionCode.userRequestedFallback:
      case LocalAuthExceptionCode.deviceError:
      case LocalAuthExceptionCode.unknownError:
        return ScreenLockAuthResult.failed;
    }
  }
}

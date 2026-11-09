import 'package:flutter/material.dart';

import '../models/caregiver.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  Caregiver? _user;
  String? _lastError;

  AuthStatus get status => _status;
  Caregiver? get user => _user;
  String? get lastError => _lastError;

  Future<void> bootstrap() async {
    if (!await DatabaseService.isLoggedIn()) {
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    final me = await DatabaseService.me();
    if (me != null) {
      _user = me;
      _status = AuthStatus.signedIn;
    } else {
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<bool> register({
    required String name,
    required String pin,
    String? email,
    String? mobileNumber,
    String accountType = 'caregiver',
    int? age,
  }) async {
    final resp = await DatabaseService.register(
      name: name,
      pin: pin,
      email: email,
      mobileNumber: mobileNumber,
      accountType: accountType,
      age: age,
    );
    return _handleAuthResponse(resp);
  }

  Future<bool> login({
    required String pin,
    String? email,
    String? mobileNumber,
  }) async {
    final resp = await DatabaseService.loginWithPin(
      pin: pin,
      email: email,
      mobileNumber: mobileNumber,
    );
    return _handleAuthResponse(resp);
  }

  bool _handleAuthResponse(ApiResponse resp) {
    if (resp.success && resp.data is Map<String, dynamic>) {
      final caregiverJson = (resp.data as Map<String, dynamic>)['caregiver'];
      if (caregiverJson is Map<String, dynamic>) {
        _user = Caregiver.fromJson(caregiverJson);
      }
      _status = AuthStatus.signedIn;
      _lastError = null;
      notifyListeners();
      return true;
    }
    _lastError = resp.message;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    await DatabaseService.logout();
    _user = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
  }
}

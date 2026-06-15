class AppConfig {
  AppConfig._();

  // For Android emulator
  static const String databaseApiUrl = 'http://10.0.2.2:8000/api';
  //static const String databaseApiUrl = 'http://10.134.142.130:8000/api';

  static const String appName = 'Audiobook for Autism';

  // Default caregiver PIN used on first run, user changes it in Settings.
  static const String defaultPin = '1234';
}

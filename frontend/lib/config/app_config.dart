class AppConfig {
  AppConfig._();

  // Android emulator: 10.0.2.2 is the emulator's alias for your computer.
  //static const String databaseApiUrl = 'http://10.0.2.2:8000/api';
  static const String databaseApiUrl = 'https://audiobooksystem-production.up.railway.app/api';
  // Physical phone on the same Wi-Fi: use your PC's LAN IP instead, and run
  // the server with `php artisan serve --host=0.0.0.0 --port=8000`.
  //static const String databaseApiUrl = 'http://10.50.51.130:8000/api';

  static const String appName = 'Audiobook for Autism';

  // Default caregiver PIN used on first run, user changes it in Settings.
  static const String defaultPin = '1234';
}

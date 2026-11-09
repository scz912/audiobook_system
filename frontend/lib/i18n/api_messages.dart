import 'app_strings.dart';

/* Messages from the server (and from the network code) are written in
   English. In Malay they're swapped here, so a pop-up never mixes the two.
   Anything not listed (rare, or with details only a developer needs) stays
   as it is. */
String localizeApiMessage(String message) {
  if (AppStrings.currentCode != 'ms' || message.isEmpty) return message;
  final text = message.trim();
  final exact = _ms[text];
  if (exact != null) return exact;

  // "Validation failed: a, b" -> each part on its own.
  for (final entry in _prefixes.entries) {
    if (text.startsWith(entry.key)) {
      final rest = text.substring(entry.key.length);
      final parts = rest.split(', ').map((p) => _ms[p.trim()] ?? p.trim());
      return '${entry.value}${parts.join(', ')}';
    }
  }
  return message;
}

const _prefixes = {
  'Validation failed: ': 'Maklumat tidak sah: ',
  'Network error: ': 'Masalah rangkaian: ',
  'Upload failed: ': 'Muat naik gagal: ',
  'AI generation failed: ': 'AI tidak dapat membuat cerita: ',
};

const _ms = <String, String>{
  // From the app's own network code.
  'Not signed in': 'Anda belum log masuk',
  'Empty response': 'Tiada jawapan daripada pelayan',
  'Unexpected response shape': 'Jawapan pelayan tidak dijangka',
  'Request timed out': 'Sambungan mengambil masa terlalu lama',
  'Network error': 'Masalah rangkaian',
  'Upload timed out': 'Muat naik mengambil masa terlalu lama',
  'No internet connection. Please check your network settings.':
      'Tiada sambungan internet. Sila semak tetapan rangkaian anda.',
  'This file is too large to upload.': 'Fail ini terlalu besar untuk dimuat naik.',
  'No audio was returned': 'Tiada audio diterima',

  // Errors from the server.
  'Audiobook not found': 'Buku audio tidak dijumpai',
  'Audiobook not found.': 'Buku audio tidak dijumpai.',
  'Child profile not found': 'Profil anak tidak dijumpai',
  'Profile not found': 'Profil tidak dijumpai',
  'Post not found': 'Hantaran tidak dijumpai',
  'Person not found': 'Orang itu tidak dijumpai',
  'Internal server error': 'Ada masalah pada pelayan. Sila cuba lagi.',
  'Conversation not found': 'Perbualan tidak dijumpai',
  'Suggestion item not found': 'Cadangan tidak dijumpai',
  'Page not found': 'Halaman tidak dijumpai',
  'Request not found': 'Permintaan tidak dijumpai',
  'Comment not found': 'Komen tidak dijumpai',
  'Not found': 'Tidak dijumpai',
  'You cannot friend yourself': 'Anda tidak boleh berkawan dengan diri sendiri',
  'You cannot accept your own invite': 'Anda tidak boleh menerima jemputan sendiri',
  'Unknown setting in suggestion': 'Tetapan dalam cadangan tidak dikenali',
  'Unknown reaction': 'Reaksi tidak dikenali',
  'This invite was already used': 'Jemputan ini sudah digunakan',
  'That is you': 'Itu anda sendiri',
  'Suggested value is out of range': 'Nilai yang dicadangkan di luar julat',
  'PIN must be 4 digits': 'PIN mesti 4 digit',
  'Not your post': 'Ini bukan hantaran anda',
  'Not your comment': 'Ini bukan komen anda',
  'No suggestions to dismiss': 'Tiada cadangan untuk diketepikan',
  'No suggestions to apply': 'Tiada cadangan untuk digunakan',
  'Join the community first': 'Sila sertai komuniti dahulu',
  'Invite code not found': 'Kod jemputan tidak dijumpai',
  'Invalid credentials': 'E-mel atau PIN salah',
  'Invalid PIN': 'PIN salah',
  'Current PIN is incorrect': 'PIN semasa salah',
  'Could not update page': 'Tidak dapat mengemas kini halaman',
  'Could not update content': 'Tidak dapat mengemas kini buku',
  'Could not save this audiobook': 'Tidak dapat menyimpan buku audio ini',
  'Could not register caregiver': 'Tidak dapat mendaftar akaun',
  'Could not delete page': 'Tidak dapat memadam halaman',
  'Could not delete content': 'Tidak dapat memadam buku',
  'Could not add page': 'Tidak dapat menambah halaman',
  'Cannot message yourself': 'Anda tidak boleh menghantar mesej kepada diri sendiri',
  'Add a story or some text': 'Tambah cerita atau sedikit teks',
  'AI is not configured.': 'AI belum disediakan.',
  'AI is not configured. Add GEMINI_API_KEY to the backend .env file.': 'AI belum disediakan.',
  'A request already exists': 'Permintaan sudah dihantar',
  "You can't message this person.": 'Anda tidak boleh menghantar mesej kepada orang ini.',
  "You can't send a request to this person.": 'Anda tidak boleh menghantar permintaan kepada orang ini.',
  'Could not generate the natural voice. Please try again.':
      'Tidak dapat membuat suara. Sila cuba lagi.',
  'Please provide email or mobile number': 'Sila isi e-mel atau nombor telefon',
  'This file type is not supported. Please upload your music as an MP3 file.':
      'Jenis fail ini tidak disokong. Sila muat naik muzik dalam format MP3.',

  // Success messages that can show on screen.
  'AI story generated.': 'Cerita AI sudah siap.',
  'Your storybook is ready, with a picture on every page!':
      'Buku cerita anda sudah siap, dengan gambar pada setiap halaman!',
  'Your storybook is being created. It will appear in the library when ready.':
      'Buku cerita anda sedang dibuat. Ia akan muncul di pustaka apabila siap.',
  'Already in your library': 'Sudah ada dalam pustaka anda',
  'Saved to your library': 'Disimpan ke pustaka anda',
  'Welcome to the community': 'Selamat datang ke komuniti',
  'You are now friends': 'Anda kini berkawan',
  'You joined the community': 'Anda telah menyertai komuniti',
  'Request sent': 'Permintaan dihantar',
  'Request declined': 'Permintaan ditolak',
  'PIN updated': 'PIN dikemas kini',
  'Settings updated': 'Tetapan dikemas kini',
  'No suggestions yet': 'Belum ada cadangan',
  'No suggestions available': 'Tiada cadangan',

  // Common sign-up and form checks (Laravel's wording).
  'The email has already been taken.': 'E-mel ini sudah digunakan.',
  'The email field must be a valid email address.': 'Sila isi alamat e-mel yang betul.',
  'The mobile number has already been taken.': 'Nombor telefon ini sudah digunakan.',
  'The name field is required.': 'Sila isi nama.',
  'The pin field is required.': 'Sila isi PIN.',
  'The pin field must be 4 digits.': 'PIN mesti 4 digit.',
  'The title field is required.': 'Sila isi tajuk.',
  'The age field must not be greater than 120.': 'Umur tidak boleh lebih daripada 120.',
};

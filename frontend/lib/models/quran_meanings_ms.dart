// Malay meanings of the 114 chapter names, in order (index 0 = chapter 1).
// From Quran.com (api.quran.com/api/v4/chapters?language=ms).
const quranMeaningsMs = <String>[
  'Pembukaan', // 1 Al-Fatihah
  'Lembu Betina', // 2 Al-Baqarah
  'Keluarga Imran', // 3 Ali Imran
  'Wanita', // 4 An-Nisa
  'Hidangan', // 5 Al-Maidah
  'Binatang Ternakan', // 6 Al-Anam
  'Tempat Tertinggi', // 7 Al-Araf
  'Rampasan Perang', // 8 Al-Anfal
  'Pengampunan', // 9 At-Tawbah
  'Nabi Yunus a.s.', // 10 Yunus
  'Nabi Hud a.s.', // 11 Hud
  'Nabi Yusuf a.s.', // 12 Yusuf
  'Guruh', // 13 Ar-Rad
  'Nabi Ibrahim a.s.', // 14 Ibrahim
  'Kawasan Berbatu', // 15 Al-Hijr
  'Lebah', // 16 An-Nahl
  'Perjalanan Malam', // 17 Al-Isra
  'Gua', // 18 Al-Kahf
  'Siti Maryam', // 19 Maryam
  'Taahaa', // 20 Taha
  'Para Nabi', // 21 Al-Anbya
  'Haji', // 22 Al-Hajj
  'Golongan yang Beriman', // 23 Al-Muminun
  'Cahaya', // 24 An-Nur
  'Pembeza Kebenaran dan Kebatilan', // 25 Al-Furqan
  'Para Penyair', // 26 Ash-Shuara
  'Semut', // 27 An-Naml
  'Cerita-cerita', // 28 Al-Qasas
  'Labah-labah', // 29 Al-Ankabut
  'Bangsa Rom', // 30 Ar-Rum
  'Luqman', // 31 Luqman
  'Sujud', // 32 As-Sajdah
  'Golongan yang Bersekutu', // 33 Al-Ahzab
  'Kaum Saba’', // 34 Saba
  'Pencipta', // 35 Fatir
  'Yaasin', // 36 Ya-Sin
  'Yang Teratur Berbaris', // 37 As-Saffat
  'Saad', // 38 Sad
  'Rombongan', // 39 Az-Zumar
  'Orang yang Beriman', // 40 Ghafir
  'Dijelaskan', // 41 Fussilat
  'Permesyuaratan', // 42 Ash-Shuraa
  'Perhiasan Emas', // 43 Az-Zukhruf
  'Kabut / Asap', // 44 Ad-Dukhan
  'Yang Berlutut', // 45 Al-Jathiyah
  'Bukit-bukit Pasir', // 46 Al-Ahqaf
  'Nabi Muhammad SAW', // 47 Muhammad
  'Kemenangan', // 48 Al-Fath
  'Bilik-bilik', // 49 Al-Hujurat
  'Qaaf', // 50 Qaf
  'Angin yang Menerbangkan', // 51 Adh-Dhariyat
  'Bukit', // 52 At-Tur
  'Bintang', // 53 An-Najm
  'Bulan', // 54 Al-Qamar
  'Yang Maha Pemurah', // 55 Ar-Rahman
  'Peristiwa yang Tidak Dapat Dielakkan', // 56 Al-Waqiah
  'Besi', // 57 Al-Hadid
  'Perempuan yang Merayu', // 58 Al-Mujadila
  'Pengusiran', // 59 Al-Hashr
  'Perempuan yang Diuji', // 60 Al-Mumtahanah
  'Barisan', // 61 As-Saf
  'Hari Jumaat', // 62 Al-Jumuah
  'Golongan Munafik', // 63 Al-Munafiqun
  'Dinampakkan Kesalahan', // 64 At-Taghabun
  'Cerai / Talak', // 65 At-Talaq
  'Mengharamkan', // 66 At-Tahrim
  'Kerajaan', // 67 Al-Mulk
  'Pena / Kalam', // 68 Al-Qalam
  'Keadaan Sebenar / Hari Kiamat', // 69 Al-Haqqah
  'Tempat-tempat Naik', // 70 Al-Maarij
  'Nabi Nuh a.s.', // 71 Nuh
  'Jin', // 72 Al-Jinn
  'Yang Berselimut', // 73 Al-Muzzammil
  'Yang Berselubung', // 74 Al-Muddaththir
  'Hari Kebangkitan / Kiamat', // 75 Al-Qiyamah
  'Manusia', // 76 Al-Insan
  'Malaikat Yang Diutus', // 77 Al-Mursalat
  'Berita Besar', // 78 An-Naba
  'Malaikat Yang Mencabut', // 79 An-Naziat
  'Dia Bermasam Muka', // 80 Abasa
  'Menggulung', // 81 At-Takwir
  'Terpecah & Terbelah', // 82 Al-Infitar
  'Golongan yang Curang', // 83 Al-Mutaffifin
  'Terbelah', // 84 Al-Inshiqaq
  'Gugusan Bintang', // 85 Al-Buruj
  'Pengunjung Malam', // 86 At-Tariq
  'Yang Tertinggi', // 87 Al-Ala
  'Peristiwa Menggelisahkan/Hari Pembalasan', // 88 Al-Ghashiyah
  'Fajar / Sinar Mentari', // 89 Al-Fajr
  'Negeri', // 90 Al-Balad
  'Matahari', // 91 Ash-Shams
  'Malam', // 92 Al-Layl
  'Pagi yang Cemerlang / Matahari Meninggi', // 93 Ad-Duhaa
  'Melapangkan', // 94 Ash-Sharh
  'Buah Tin / Buah Ara', // 95 At-Tin
  'Segumpal Darah', // 96 Al-Alaq
  'Kemuliaan', // 97 Al-Qadr
  'Bukti yang Nyata', // 98 Al-Bayyinah
  'Kegoncangan', // 99 Az-Zalzalah
  'Yang Berlari Kencang', // 100 Al-Adiyat
  'Hari Yang Hingar Bingar / Kiamat', // 101 Al-Qariah
  'Bermegah-megah', // 102 At-Takathur
  'Masa', // 103 Al-Asr
  'Pengumpat', // 104 Al-Humazah
  'Gajah', // 105 Al-Fil
  'Kaum Quraisy', // 106 Quraysh
  'Barangan Berguna', // 107 Al-Maun
  'Sungai Di Syurga', // 108 Al-Kawthar
  'Golongan Kafir', // 109 Al-Kafirun
  'Pertolongan', // 110 An-Nasr
  'Nyalaan Api', // 111 Al-Masad
  'Tulus Ikhlas / Memurnikan Keesaan Allah', // 112 Al-Ikhlas
  'Waktu Subuh / Dinihari', // 113 Al-Falaq
  'Manusia', // 114 An-Nas
];

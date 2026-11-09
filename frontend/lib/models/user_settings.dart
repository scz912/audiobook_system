import '_json_helpers.dart';

// Two voices: one female, one male.
enum NarratorVoice {
  calmFemale,
  warmMale,
}

extension NarratorVoiceX on NarratorVoice {
  String get apiValue {
    switch (this) {
      case NarratorVoice.calmFemale:
        return 'calm_female';
      case NarratorVoice.warmMale:
        return 'warm_male';
    }
  }

  String get label {
    switch (this) {
      case NarratorVoice.calmFemale:
        return 'Female';
      case NarratorVoice.warmMale:
        return 'Male';
    }
  }

  // The three retired voices map to the nearest of the two.
  static NarratorVoice fromApi(String? value) {
    switch (value) {
      case 'warm_male':
      case 'soothing_elder':
        return NarratorVoice.warmMale;
      default:
        return NarratorVoice.calmFemale;
    }
  }
}

class UserSettings {
  final NarratorVoice narratorVoice;
  final double readingSpeed;
  final double volume;
  final double textScale;
  final bool reducedAnimations;
  final bool autoPlayNext;
  final bool readAlong;

  const UserSettings({
    this.narratorVoice = NarratorVoice.calmFemale,
    this.readingSpeed = 1.0,
    this.volume = 0.8,
    this.textScale = 1.0,
    this.reducedAnimations = true,
    this.autoPlayNext = true,
    this.readAlong = true,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      narratorVoice: NarratorVoiceX.fromApi(safeNullableString(json['narrator_voice'])),
      readingSpeed: safeDouble(json['reading_speed']) ?? 1.0,
      volume: safeDouble(json['volume']) ?? 0.8,
      textScale: safeDouble(json['text_scale']) ?? 1.0,
      reducedAnimations: safeBool(json['reduced_animations'], true),
      autoPlayNext: safeBool(json['auto_play_next'], true),
      readAlong: safeBool(json['read_along'], true),
    );
  }

  Map<String, dynamic> toJson() => {
        'narrator_voice': narratorVoice.apiValue,
        'reading_speed': readingSpeed,
        'volume': volume,
        'text_scale': textScale,
        'reduced_animations': reducedAnimations,
        'auto_play_next': autoPlayNext,
        'read_along': readAlong,
      };

  UserSettings copyWith({
    NarratorVoice? narratorVoice,
    double? readingSpeed,
    double? volume,
    double? textScale,
    bool? reducedAnimations,
    bool? autoPlayNext,
    bool? readAlong,
  }) {
    return UserSettings(
      narratorVoice: narratorVoice ?? this.narratorVoice,
      readingSpeed: readingSpeed ?? this.readingSpeed,
      volume: volume ?? this.volume,
      textScale: textScale ?? this.textScale,
      reducedAnimations: reducedAnimations ?? this.reducedAnimations,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      readAlong: readAlong ?? this.readAlong,
    );
  }
}

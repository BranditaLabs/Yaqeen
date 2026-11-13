/// The 16 bundled preset avatars. Mirrors `packages/brand/avatars/avatars.json` (parity-tested) and
/// contracts `AVATAR_PRESETS`; the art is `assets/avatars/<id>.webp`, so presets render offline.
enum AvatarGender { m, f }

class AvatarPreset {
  const AvatarPreset({required this.id, required this.gender, required this.ar, required this.en});
  final String id;
  final AvatarGender gender;

  /// Accessible description (e.g. «عمامة» / "Imama").
  final String ar;
  final String en;

  String get asset => 'assets/avatars/$id.webp';
  String label(String locale) => locale == 'ar' ? ar : en;
}

const kAvatarPresets = [
  AvatarPreset(id: 'm01', gender: AvatarGender.m, ar: 'طاقية بيضاء', en: 'White kufi'),
  AvatarPreset(id: 'm02', gender: AvatarGender.m, ar: 'غترة وعقال', en: 'Ghutra & agal'),
  AvatarPreset(id: 'm03', gender: AvatarGender.m, ar: 'عمامة', en: 'Imama'),
  AvatarPreset(id: 'm04', gender: AvatarGender.m, ar: 'لحية مشذّبة', en: 'Trimmed beard'),
  AvatarPreset(id: 'm05', gender: AvatarGender.m, ar: 'طاقية ذهبية', en: 'Gold kufi'),
  AvatarPreset(id: 'm06', gender: AvatarGender.m, ar: 'شاب', en: 'Young'),
  AvatarPreset(id: 'm07', gender: AvatarGender.m, ar: 'شيخ وقور', en: 'Elder'),
  AvatarPreset(id: 'm08', gender: AvatarGender.m, ar: 'عمامة كحلية', en: 'Navy imama'),
  AvatarPreset(id: 'f01', gender: AvatarGender.f, ar: 'حجاب كحلي', en: 'Navy hijab'),
  AvatarPreset(id: 'f02', gender: AvatarGender.f, ar: 'حجاب سماوي', en: 'Sky hijab'),
  AvatarPreset(id: 'f03', gender: AvatarGender.f, ar: 'خمار', en: 'Khimar'),
  AvatarPreset(id: 'f04', gender: AvatarGender.f, ar: 'نقاب', en: 'Niqab'),
  AvatarPreset(id: 'f05', gender: AvatarGender.f, ar: 'شيلة ذهبية', en: 'Gold shayla'),
  AvatarPreset(id: 'f06', gender: AvatarGender.f, ar: 'حجاب أبيض', en: 'White hijab'),
  AvatarPreset(id: 'f07', gender: AvatarGender.f, ar: 'فتاة', en: 'Young'),
  AvatarPreset(id: 'f08', gender: AvatarGender.f, ar: 'سيدة وقورة', en: 'Elder'),
];

AvatarPreset? presetById(String id) {
  for (final p in kAvatarPresets) {
    if (p.id == id) return p;
  }
  return null;
}

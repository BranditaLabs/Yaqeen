# Yaqeen sounds — «أصوات يقين»

Synthesised notification and UI sounds: short, clean soft-FM tones; the signature is the name «يَ‑قين» (short tone rising a fifth into a long one); no instrument timbres, bells or melodies. See `docs/NOTIFICATIONS.md §3` for the mapping and rules.

```bash
pip install numpy scipy soundfile pyloudnorm pedalboard   # + ffmpeg with libvorbis
python3 packages/brand/sounds/generate_sounds.py
```

Writes the 48 kHz/24-bit masters to `master/`, Android `.ogg` to `apps/mobile/android/app/src/main/res/raw`,
iOS `.caf` to `apps/mobile/ios/Runner/Sounds`, and UI sounds to `apps/mobile/assets/sounds`. The seed is fixed,
so re-running gives identical files. Everything here is original work, free of third-party licences.

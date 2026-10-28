# Yaqeen sounds — «أصوات يقين»

Synthesised notification and UI sounds: one signature voice and one interval (D → A) as a sonic identity; no instrument timbres, bells or melodies. See `docs/NOTIFICATIONS.md §3` for the mapping and rules.

```bash
pip install numpy scipy soundfile pyloudnorm   # + ffmpeg with libvorbis
python3 packages/brand/sounds/generate_sounds.py
```

Writes the 48 kHz/24-bit masters to `master/`, Android `.ogg` to `apps/mobile/android/app/src/main/res/raw`,
iOS `.caf` to `apps/mobile/ios/Runner/Sounds`, and UI sounds to `apps/mobile/assets/sounds`. The seed is fixed,
so re-running gives identical files. Everything here is original work, free of third-party licences.

# Home Assistant Mac VPE

Native macOS voice client for Home Assistant Assist.

The app can:

- stream 16 kHz mono PCM microphone audio into a Home Assistant Assist pipeline;
- retrieve Assist pipelines from Home Assistant and choose one from a picker;
- use Home Assistant wake word detection;
- choose the macOS microphone input and speaker output;
- play Assist TTS responses on the selected speaker;
- register or unregister itself as a launch-at-login app.
- optionally start listening as soon as the app opens.

Documentation checked while building:

- Home Assistant Assist pipeline WebSocket API: `assist_pipeline/run`, binary STT handler, wake word/STT/TTS events.
- ESPHome `voice_assistant`: microphone, speaker/media player, `use_wake_word`, and conversation timeout behavior.

Run locally:

```bash
./script/build_and_run.sh
```

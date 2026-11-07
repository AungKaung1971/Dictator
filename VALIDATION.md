# Validation

## Current release: 1.2.2

- Universal release ZIP: Intel (`x86_64`) and Apple silicon (`arm64`) slices compiled for macOS 13+, merged and checked with `lipo`. The signed bundle was verified after extracting the archive.
- Built with Apple Swift 6.2.1 Command Line Tools on an Intel Mac running macOS 26.5.2.
- `./scripts/test.sh`: **26 passed, 0 failed**. The runner uses stub API responses for network checks; it does not access an API key or change permissions.
- Physical hold-to-talk and cleaned text insertion passed in TextEdit.
- After the macOS 26 Fn companion-event fix, the user confirmed hands-free double-tap works in the field where it previously failed. The app's final status was independently inspected and showed **Inserted**.
- The dedicated local signing identity remained unchanged across changed-binary updates. Microphone and Accessibility grants stayed enabled, the saved key remained available, and the final update reopened without a new permission or Keychain prompt.
- `SMAppService.mainApp` reports automatic startup enabled. A full reboot/login or sleep/wake acceptance test has **not** been performed after the final fix.
- Apple silicon hardware, another person's Mac, Gatekeeper first-launch flow, Mail, Notes and VS Code have **not** been individually tested.

## Automated coverage

WAV header and PCM preservation; vocabulary sanitisation; model access requests; multipart transcription; cleanup request privacy and instruction boundaries; refusal and incomplete output; HTTP errors without leaked server bodies; disabled cleanup; newer-model reasoning settings; Fn holds; duplicate edges; fallback autorepeat; Fn combinations; synthetic paste tagging; double-tap timing; delayed main-thread microphone startup; stopping hands-free mode once; cancellation and timer expiry; and both orders of macOS 26 keycodes 63/179, including keyDown on a short release.

The macOS 26 regression failed before the fix. It now verifies that companion events neither cancel a recording nor double-count taps, and ordinary typing still reaches cancellation.

## Limits

The checks are not proof of compatibility with every app, keyboard, accent or clipboard manager. A protected-field fixture did not obtain a reliable global-shortcut positive control, so it is not counted as a passed end-to-end password-field test. Sensitive-field and focus checks are implemented but depend on the target app's Accessibility metadata.

A small earlier comparison of short synthetic cleanup requests found the lowest median latency with the selected default, `gpt-4.1-mini`. This is not a general model-quality or speed ranking. Model access, latency, billing and transcription accuracy vary by account and network.

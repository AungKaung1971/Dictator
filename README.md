# Dictator

**Hold Fn. Speak naturally. Release to type.**

Dictator is a small, native macOS menu bar app that turns speech into clean text in your focused editor. Double-tap Fn for hands-free recording, then press Fn once to finish. Speech recognition and optional text cleanup use your own OpenAI API key.

Built with Swift, SwiftUI and AppKit. No accounts, subscriptions, analytics, third-party packages or local AI models.

## Download and install

**[Download the latest release](https://github.com/AungKaung1971/Dictator/releases/latest)** and choose `Dictator-universal.zip`.

The download contains both Intel and Apple silicon executables. macOS 13 Ventura or newer is required. Live recording and insertion have been tested on an Intel Mac; the Apple silicon build is compiled and packaged but has not yet been tested on Apple silicon hardware.

1. Unzip the download to get **Dictator.app**.
2. Move it to your **Applications** folder, or to **Applications inside your home folder**. Keep one installed copy in the same location for future updates.
3. Open Dictator. It lives in the menu bar, with a waveform icon, rather than the Dock.
4. Complete the short setup below.

The release is signed with the maintainer's persistent local certificate. It is **not Apple Developer ID signed or notarised**, so a downloaded copy may be blocked by macOS. If you trust this source, attempt to open it, then use **System Settings → Privacy & Security → Open Anyway** and confirm. See [Apple's instructions for opening apps safely](https://support.apple.com/en-gb/102445). Do not disable Gatekeeper or SIP. Building from source is another option.

The release ZIP contains the app and its public signature, with no API keys or private signing credentials. You can share the release link or the ZIP directly.

## First-time setup

Open **Dictator → Settings → Setup** from the menu bar.

1. Allow **Microphone** access when macOS asks.
2. Allow **Accessibility** in **System Settings → Privacy & Security → Accessibility**. Add the installed `Dictator.app` if needed, and enable its switch.
3. Enter your **OpenAI API key**, click **Save in Keychain**, then **Check model access**. If Keychain asks whether Dictator may use your saved key, choose **Always Allow** to avoid repeated approval prompts for this app identity.
4. In **System Settings → Keyboard**, set **Press Fn / Globe key to → Do Nothing**. Choose another shortcut for Apple's built-in Dictation if it is also assigned to Fn.
5. Click into a normal text field and try a short recording.

**You need an OpenAI API project with access to the selected models and available API billing or credits.** Do not assume a ChatGPT subscription includes API credits; check your [API billing](https://platform.openai.com/settings/organization/billing/overview). Each person can use their own key. Never paste an API key into an issue, README, terminal command or chat.

Each Mac needs its own initial permissions and API-key setup. Settings and keys are not transferred with the download. “Open Dictator when I log in” is enabled on first launch and can be changed in Setup. If macOS requires approval for startup, allow Dictator under **General → Login Items**.

## Using Dictator

| Mode | Start | Finish |
|---|---|---|
| Hold-to-talk | Hold **Fn / Globe** and speak | Release Fn |
| Hands-free | **Double-tap Fn**, let go, then speak | Press Fn once |
| Fallback shortcut | Hold **Control–Option–Space** or **Control–Shift–Space** | Release the shortcut |

For double-tap, keep the first tap under 350 ms and the gap before the second press under 500 ms. The recording indicator stays visible in hands-free mode and shows **Fn to finish**.

Stay in the same application and keep the cursor in place until processing finishes. Typing, clicking, switching apps or sleep can cancel dictation. Recordings are limited to two minutes. Use the menu bar's **Cancel dictation** to discard a take.

Dictator is intended for standard text fields in apps such as TextEdit, Chrome, ChatGPT, Mail, Notes and VS Code. Compatibility depends on each app's Accessibility support; these apps have not all been individually tested. Password fields, sensitive fields and unrecognised editors are blocked.

## Preferences

- **Microphone:** use the system default or choose a specific input device.
- **Cleanup:** remove unnecessary fillers and false starts, fix punctuation and grammar, and preserve meaning. Turn it off to skip the cleanup API request.
- **Models:** speech recognition uses `gpt-transcribe`; cleanup defaults to `gpt-4.1-mini`. Other selectable models depend on your project's access. Newer reasoning-capable cleanup choices run with reasoning disabled to reduce latency.
- **Vocabulary:** add names, products and technical terms as comma-separated hints. Recognition can still make mistakes.
- **Spelling:** British English is enabled by default.
- **Shortcut:** choose one of the fallback chords if your keyboard or remapper does not expose Fn to macOS.

Example cleanup:

> “I think we should, um, actually no, let's launch on Friday”
>
> “I think we should launch on Friday.”

Audio is uploaded after recording stops; this version does not stream while you speak. Network speed, recording length and model response time affect how quickly text appears.

## Privacy and safe insertion

- **Your key stays in macOS Keychain.** The app sends it only to OpenAI's API. Preferences store no API key.
- **No recording or transcript history.** Audio stays in memory. Failed processing may keep a recoverable transcript in memory for up to five minutes; successful insertion clears it. Starting another recording, discarding, cancelling or quitting clears retained text.
- **Cloud processing:** audio and transcripts are sent to OpenAI for transcription and optional cleanup. Cleanup requests use `store: false`; OpenAI's separate [API data policies](https://developers.openai.com/api/docs/guides/your-data) still apply.
- **No surrounding text is sent to the AI.** Accessibility is used locally to inspect focus, reject protected fields and validate the insertion target. Dictator does not take screenshots or request Screen Recording access.
- **Clipboard preservation:** browser and other compatible editors use normal paste, then restore the previous clipboard if it has not changed. TextEdit uses direct selected-text insertion. Clipboard managers and unusual editors can limit restoration or confirmation.
- **No automatic duplicate pastes.** An unconfirmed or failed insertion leaves text available in the menu for manual copying. If you move the cursor or edit the target while processing, insertion may be refused.
- The optional shortcut diagnostic view keeps a bounded in-memory trace of Fn events, lifecycle status and cancellation categories. It does not log ordinary typed text, speech or transcripts.

Sensitive-field checks rely on metadata exposed by the target app. Review important text, and avoid dictating secrets.

## Troubleshooting

| Problem | What to check |
|---|---|
| No recording bar | Confirm the app is running in the menu bar, the key is saved, and Microphone and Accessibility show as enabled in Setup. |
| Fn opens emoji or Apple Dictation | Set the system Fn action to **Do Nothing** and remove Apple's Fn Dictation shortcut. |
| Fn is not detected | Try a fallback shortcut. If Setup reports the keyboard listener is unavailable, enable **Input Monitoring** for Dictator and reopen it. |
| Cannot identify the text field | Click directly inside the editor. Chrome/Electron accessibility is requested automatically when needed; some custom editors still need their own accessibility setting enabled. |
| No microphone signal | Check the selected device, input volume and microphone permission. Try **System Default**. |
| No text appears | Wait for processing, then check the menu status. A retained result may be available to copy. Do not repeatedly trigger paste. |
| API error 401/403/404 | Check your API key, project permissions and model access. |
| API error 429 | Check your API balance, quota and rate limits. |
| Repeated permission prompts after a custom build | Keep the app path, bundle ID and signing certificate stable. Ad-hoc signatures or a new certificate can invalidate old grants. |
| Does not open after login | Check **Open Dictator when I log in** in Setup and Dictator's entry under macOS **General → Login Items**. |

**macOS 26 Fn note:** quick Fn taps can produce both modifier event `63` and companion key event `179`. Dictator uses the physical modifier stream for the gesture and ignores the companion for recording and typing-cancellation logic. This fixes the brief recording-bar flash on double-tap. See the independently documented [dual-event behaviour](https://github.com/4over7/SpeakOut/blob/main/CHANGELOG.md).

## Build from source

Requires macOS, Apple's Command Line Tools or Xcode with Swift 5.9 or newer, and Python 3 for the one-time local signing setup. There are no Swift package dependencies to download.

```sh
git clone https://github.com/AungKaung1971/Dictator.git
cd Dictator
xcode-select --install  # skip if Apple's developer tools are already installed

python3 scripts/setup-signing.py  # run once on your development Mac
./scripts/test.sh
./scripts/build.sh
./scripts/install.sh
open "$HOME/Applications/Dictator.app"
```

For a ZIP containing both architectures:

```sh
./scripts/build.sh --universal
```

Both builds produce `build/Dictator.zip`. The install script installs to `~/Applications` by default; quit a running Dictator before installing. You can pass another destination directory to `scripts/install.sh`.

The local setup creates a non-extractable signing key in a dedicated Keychain at `~/Library/Keychains/DictatorSigning.keychain-db`, with private configuration under `~/Library/Application Support/DictatorSigning/`. It preserves existing Keychain search-list entries and does not change system certificate trust. Keep these files private and backed up. Do not commit them. Builds reuse the certificate so macOS can recognise the same application across updates.

If you already have an Apple signing identity, skip local signing setup and select it explicitly:

```sh
DICTATOR_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build.sh --universal
```

Notarisation is a separate distribution step and is not automated here. Rebuilding a downloaded release with your own signing identity requires granting permissions for that new identity.

## Implementation and validation

SwiftUI provides Settings and the small recording indicator; AppKit provides the menu bar app. A dedicated Core Graphics event-tap thread handles shortcuts independently of microphone startup. AVAudioEngine captures in-memory mono 16 kHz WAV audio. The OpenAI client uses ephemeral networking with bounded errors and no automatic charge-duplicating retries.

Run `./scripts/test.sh` for the standalone checks supported by Command Line Tools. The suite covers audio encoding, API requests and errors, response parsing, privacy flags, Fn holds, hands-free state, delayed microphone startup, duplicate Fn events and macOS 26 companion-event ordering. See [VALIDATION.md](VALIDATION.md) for tested behaviour and remaining limits.

Official references: [OpenAI speech-to-text](https://developers.openai.com/api/docs/guides/speech-to-text), [Responses API](https://developers.openai.com/api/docs/api-reference/responses), [Apple Fn flag](https://developer.apple.com/documentation/coregraphics/cgeventflags/masksecondaryfn), and [launch-at-login service](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp).

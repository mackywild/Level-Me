# Android fixed release signing — setup and acceptance

## Why
CI-generated debug keys differ across runners. APK signature verification alone does not guarantee update compatibility. Only the fixed-key artifact is intended for ongoing installation.

## One-time owner setup
1. On a trusted local machine, install a JDK (17 recommended). If the key that signed the installed app is still available, reuse it instead of generating another key. Otherwise create a new PKCS12 key:
   ```sh
   keytool -genkeypair -keystore level-me-release.p12 -storetype PKCS12 -alias level-me -keyalg RSA -keysize 3072 -validity 10000
   ```
   Use a strong password, enter interactively, and retain the key and password securely with an offline backup. PKCS12 usually uses the same password for store and private key. Do not commit or upload the key to chats, issues, or other public locations.
2. In repository Settings > Environments create **android-release**. Restrict deployment branches to main, and add a required reviewer if your GitHub plan/repository permits it. Do not expose release secrets to PR builds.
3. Add four environment secrets:
   - ANDROID_KEYSTORE_BASE64: Base64 of the complete PKCS12 file (Base64 is not encryption).
   - ANDROID_KEYSTORE_PASSWORD: store password.
   - ANDROID_KEY_ALIAS: level-me (or existing key alias).
   - ANDROID_KEY_PASSWORD: private key password.
   Windows PowerShell can copy Base64 without printing: `[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path 'level-me-release.p12').Path)) | Set-Clipboard`. Paste directly into the secret field and clear clipboard afterwards. macOS: `base64 -i level-me-release.p12 | pbcopy`.
4. Obtain SHA-256 certificate fingerprint via `keytool -list -v -keystore level-me-release.p12 -alias level-me`. In the same environment, create variable ANDROID_CERT_SHA256 with the SHA256 certificate fingerprint (with or without colons). Record the fingerprint separately. Never change this variable just to bypass a failed check.

## Build and verify
After merging the workflow change, manually run Build Android APK on main, check signed_release, and approve the protected environment if prompted.
- level-me-test-apk: CI test build, temporary signing key, not a persistent-install release.
- level-me-signed-release-apk: release job only, fixed signer verified against the expected fingerprint.
The normal PR build runs a disposable-key re-signing smoke test and rejects a wrong expected fingerprint. The production key is not used in that test.
Run two separate signed builds and compare certificate fingerprints. Every update must retain the signing key, package ID and increase versionCode for a newer release.

## Existing installation (important)
If the old APK used a different key, the new key cannot update it in place. The fixed-signing workflow cannot recover a private key that is no longer available.
- Before attempting migration, export a portable backup using the installed application and copy it off the phone. Verify the backup on a separate test device/profile where possible.
- Do NOT uninstall or clear data merely to resolve an install error. If backup cannot be verified, stop. If the old signing key is recoverable, use that key.
- Only after the backup is verified and the owner explicitly chooses a one-time migration, replace the old app with the fixed-key build, import the backup and confirm daily records, FE history, quest progress and WORLD data.
- Test subsequent signed APK updates without clearing data. Do not distribute the test APK as an update.

## Acceptance gates
- CI build, analysis, tests, disposable signing and mismatch rejection pass.
- Owner configures environment and secrets; signed release job passes.
- Existing installation signature compared, safe migration verified if required.
- Android upgrade and backup restore verified on device.
No production key is created or stored by this PR. Production signing remains unverified until owner setup.

References: https://developer.android.com/tools/apksigner ; https://developer.android.com/studio/publish/app-signing ; https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions

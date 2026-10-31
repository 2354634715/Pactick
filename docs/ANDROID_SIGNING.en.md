[简体中文](ANDROID_SIGNING.md) | English

# Creating and backing up an Android signing key on Windows

This guide creates the long-term signing key for the first Pactick preview APK. Maintainers run these commands in their own PowerShell terminal and enter passwords locally; passwords must not be provided through chat or public logs. A JDK is required. Building Android also requires Flutter and the Android SDK; see the version requirements in the [build guide](BUILDING.en.md).

The first release distributes APKs directly through Releases. The key created here signs the actual APK; it is different from an upload key that might later be used with Google Play App Signing. Updates to directly distributed APKs require a compatible signature. Generating a new file with the same name cannot recover the old key. See [Android app signing](https://developer.android.com/studio/publish/app-signing).

## 1. Create the key

Run in your own PowerShell terminal, from any directory:

```powershell
Get-Command keytool.exe
$signingDir = Join-Path $env:LOCALAPPDATA 'Pactick\signing'
$keystorePath = Join-Path $signingDir 'pactick-release.jks'
if (Test-Path -LiteralPath $keystorePath) {
    throw '目标密钥已存在，请先核对已有密钥，不要重新生成。'
}
New-Item -ItemType Directory -Path $signingDir -Force | Out-Null
keytool.exe -genkeypair -v -keystore $keystorePath -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias pactick -dname 'CN=Pactick'
```

`keytool` is supplied with the JDK. If it cannot be found, locate `bin/keytool.exe` in the JDK you use and replace the command name with `& 'actual-full-path'`. If the preceding command fails, resolve the error before continuing.

The command creates a JKS-format RSA 2048-bit private key, with a self-signed certificate valid for 10000 days and alias `pactick`. The certificate name is `Pactick`; no government ID number or home address is required. Certificate information is published with the APK. The parameters follow the [Flutter Android signing guide](https://docs.flutter.dev/deployment/android#sign-the-app); `-storetype JKS` explicitly selects the actual format.

Enter and confirm the keystore password, then handle the private-key password prompt. For initial setup, you can press Enter when prompted to use the same password. Generate and save a random password in a password manager. Do not put passwords in `-storepass` or `-keypass` command arguments, where they can enter shell history. The later `key.properties` configuration must match the actual passwords.

After creation, check the file and certificate:

```powershell
keytool.exe -list -v -keystore $keystorePath -alias pactick
Get-FileHash -LiteralPath $keystorePath -Algorithm SHA256
```

`keytool` must open the key with the saved password, and the entry must be a private-key entry. Record the alias, certificate SHA-256 fingerprint, and validity period. The key-file hash verifies backups; the certificate fingerprint verifies APKs. They are different values.

## 2. Verify an independent backup

Keep at least one protected copy independent of the development machine's disk, such as on encrypted removable media. Store the password in a password manager and confirm how to recover it. A file stored only under `%LOCALAPPDATA%` does not protect against reinstallation or disk failure.

After copying, run `Get-FileHash` on the backup and compare it with the original. Then run `keytool -list -v -keystore 'actual-backup-path' -alias pactick` to verify that it opens and has the same certificate fingerprint. Record the backup date, alias, certificate fingerprint, and location. Passwords must not enter public release records.

Do not overwrite an existing key backup. Losing the key or password after use may prevent further updates with the same signature for directly distributed APKs. Do not uninstall an app containing the only copy of user data to resolve a signing problem.

## 3. Configure the source copy

Maintainers can run the local configuration script in their own interactive terminal, from any directory:

```powershell
python scripts/configure_android_signing.py --keystore $keystorePath --keytool 'JDK的实际目录/bin/keytool.exe'
```

This example assumes the project root is the working directory. From another directory, use the script's absolute path. By default, the script writes `client/android/key.properties` in its own project. Use `--root 'reviewed-copy-root'` to select a copy. The script hides password input, passes passwords to `keytool` through child-process environment variables, verifies the alias and private-key password by generating and discarding a certificate request, then writes configuration escaped according to Java properties rules. Pressing Enter at the private-key password prompt uses the keystore password.

The script fails without overwriting an existing file if the target exists, the key or passwords do not match, or the terminal is not interactive. Windows access permissions are inherited from the target directory. This file contains plaintext passwords and must be stored only in a protected local directory. Before copying configuration into a build copy, archive the source and confirm that the copy has no existing signing configuration.

If you do not use the script, configure it manually as follows.

First create and review a clean source copy using the [release process](RELEASING.en.md). After confirming there is no existing configuration, run from that copy's root:

```powershell
if (Test-Path -LiteralPath 'client\android\key.properties') {
    throw '已有签名配置，请先核对，不用模板覆盖。'
}
Copy-Item -LiteralPath 'client\android\key.properties.example' -Destination 'client\android\key.properties'
```

Fill in these four entries using a local editor:

```properties
storeFile=actual-absolute-path-to-keystore
storePassword=actual-keystore-password
keyAlias=pactick
keyPassword=actual-private-key-password
```

`storeFile` can use forward slashes, such as `D:/private-signing/pactick-release.jks`; this illustrates path syntax only. Java properties files do not expand environment variables, so enter the real path. Write a backslash as `\\`; passwords containing backslashes, leading spaces, non-ASCII characters, and similar characters also require Java properties escaping. If passwords do not match, check input and escaping; do not generate a new key to solve the problem.

Gradle already configures release signing; no change to `build.gradle.kts` is required. A release task fails if any of the four entries is missing and does not fall back to a debug certificate. `key.properties` contains plaintext passwords. Neither it nor the keystore may be committed or included in ordinary source archives; the public-source tool excludes them.

If a Windows path contains special characters such as `&`, use a separate build directory without those characters. Generate the source archive before adding private signing configuration or build files.

## 4. Build and verify

Run these commands in order from the reviewed copy's `client` directory. Continue only after each step succeeds:

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --release --dart-define=RELEASES_URL=https://github.com/2354634715/Pactick/releases
```

The output is `client/build/app/outputs/flutter-apk/app-release.apk` in that copy. Locate `apksigner.bat` in the actual `build-tools/version/` directory of the Android SDK, then run:

```powershell
& 'apksigner.bat的实际完整路径' verify --verbose --print-certs 'APK的实际完整路径'
Get-FileHash -LiteralPath 'APK的实际完整路径' -Algorithm SHA256
```

Signature verification must succeed, and the APK certificate SHA-256 fingerprint must match `keytool` output. Record the APK hash, certificate fingerprint, corresponding source version, and build environment with the candidate. Notification, database, device, backup/restore, and multiple-device checks must still be run separately; a successful build alone does not justify public distribution.

For GitHub candidate builds, configure this key and its passwords in the protected `android-release` environment. Variable names are listed in the [release process](RELEASING.en.md). Do not upload keys in Issues, ordinary PRs, or chat. After changes affecting the APK, including Android UI, sorting, or native notifications, rebuild the final signed candidate, verify its source and artifacts, and run the applicable device checks. An earlier candidate does not represent the modified version.

# Platform setup

Create the standard Flutter platform folders once:

```bash
flutter create .
```

Then restore the provided `lib/` and `pubspec.yaml` if Flutter overwrites anything.

For Android internet access, ensure this exists in:
`android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Some stream hosts require headers, signed URLs, tokens, cookies or DRM. This starter assumes a directly playable authorized URL.

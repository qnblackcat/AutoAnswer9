# AutoPickUp

Automatically answers incoming calls on jailbroken iOS 14+ after a delay, with per-app and per-contact rules.

## Features

- Works with Telephony, FaceTime and CallKit apps: Zalo, WhatsApp, Messenger, Telegram, Viber, Signal, LINE
- Per-app mode: **Off** (default), **Everyone** (with excluded contacts) or **Only Specific Contacts**
- Match contacts by phone number, caller name, or pick them from Contacts (Telephony / FaceTime)
- Delay from 0 to 40 seconds (default 10)
- Optionally switch auto-answered calls to the speaker, keeping headphones if connected
- FaceTime video calls: don't answer, answer as audio only, or answer
- Settings apply immediately, no respring needed

Only apps that ring through CallKit (the system incoming call screen) can be answered. Some apps report a phone number, others only a caller name, so if one doesn't match, try the other.

## Building

Requires [Theos](https://theos.dev) (the [roothide fork](https://github.com/roothide/theos) for roothide packages).

```bash
make package FINALPACKAGE=1                               # rootful
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless # rootless
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide # roothide
```

Add `AA_DEBUG=1` to log the tweak's decisions to Console.app (filter by `AutoPickUp`).

## Credits

Based on [AutoAnswer9](https://github.com/leftyfl1p/AutoAnswer9) by leftyfl1p. The code has since been rewritten.

## License

[GPL-3.0](LICENSE)

# Fire TV Stick 4K Select (Vega OS)

The 4K Select doesn't run Fire OS (Android). It runs **Vega OS**, Amazon's Linux-based system. That
means:

- There's no ADB, so `claudetv.sh` can't connect to it.
- You can't sideload Android apps or install a custom launcher.
- There's no known way to unlock the bootloader or replace the OS.

You can still cut down the ads and tracking a lot.

## 1. Settings

Menu names may vary slightly between Vega OS versions:

- **Privacy settings:** turn off device usage data, app usage data collection and interest-based ads.
- **Featured content:** turn off autoplay for video and audio on the home screen.
- **Notifications:** turn off promotional and app notifications.
- **Alexa / voice:** turn off anything you don't use.

## 2. DNS ad blocking

This does the most to help. Point your router's DNS at an ad-blocking resolver such as
[NextDNS](https://nextdns.io), [AdGuard DNS](https://adguard-dns.io) or a Pi-hole on your network.
That blocks many of the banner ads and tracking requests on every device in the house, including
the Select and smart TVs. Some home screen tiles will show up blank instead of ads. A few Amazon
features might also break if they share domains with the ads. If one does, allow that domain again
in your DNS dashboard.

## 3. Swap the stick

If you want a fully clean home screen, use the Select on a TV where you don't mind the stock UI.
Then use a Fire OS stick (debloated with this toolkit and running Projectivy) or a Google TV / Android
TV device that lets you change the default launcher.

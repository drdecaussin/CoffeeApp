# Shot Log (iPhone app)

A native SwiftUI app for logging your morning espresso and dialing in grind and dose on a
Breville Barista Pro. Data stays on your iPhone (SwiftData). iOS 17 or later.

## Features
- **Log a shot:** machine, roaster, bean, roast level, roast date and days off roast, bag photo
  (saved per bean), grind setting and inner burr, grams in, grams out of the grinder, basket,
  puck prep (WDT, distributor, dosing funnel, puck screen, paper filter), shot timer, espresso out,
  puck (soupy / wet / firm / dry), taste, drink made, puck photo, notes. Ratio, grinder retention
  and the 1:2 target are worked out as you type.
- **Dial-in help:** pick a bean and see your last shot with it, a suggested change
  (finer, coarser, more dose) and your best settings so far. One tap fills them in.
- **History:** shots by day, filter by bean, edit, delete, or "brew again" with the same settings.
- **Stats:** totals, streak, firm-puck rate, per-bean best settings, grind vs time chart,
  all-beans comparison, drinks breakdown, CSV export.

## How it gets built (no Mac needed)
GitHub Actions builds the app on a cloud Mac every time code is pushed to `main`.
The project file is generated from `project.yml` with XcodeGen.

## One-time setup for TestFlight
1. **Apple Developer Program:** enroll at https://developer.apple.com/programs/enroll/ ($99/yr).
2. **Register the app ID:** in https://developer.apple.com/account/resources/identifiers
   add an App ID with bundle ID `com.dyl.shotlog` (if it is taken, pick another and set a
   GitHub repository *variable* named `BUNDLE_ID` to it).
3. **Create the app in App Store Connect:** https://appstoreconnect.apple.com → Apps → + → New App,
   platform iOS, name "Shot Log" (or any free name), bundle ID from step 2, SKU `shotlog`.
4. **Create an API key:** App Store Connect → Users and Access → Integrations →
   App Store Connect API → generate a key with the **Admin** role. Download the `.p8` file
   (you can only download it once). Note the Key ID and the Issuer ID shown on that page.
5. **Find your Team ID:** https://developer.apple.com/account → Membership details.
6. **Add four GitHub secrets:** repo → Settings → Secrets and variables → Actions → New repository secret:
   - `APPLE_TEAM_ID`: the Team ID
   - `ASC_KEY_ID`: the Key ID
   - `ASC_ISSUER_ID`: the Issuer ID
   - `ASC_KEY_P8`: open the `.p8` file in Notepad and paste the whole text
7. **Run it:** repo → Actions → "Build iPhone app" → Run workflow. When it finishes (about 10–15 min,
   then Apple processes the build for a few more minutes), install **TestFlight** from the App Store on
   your iPhone, open it signed in with the same Apple ID, and install Shot Log.
   In App Store Connect → your app → TestFlight, add yourself under Internal Testing if it isn't offered.

Every later push to `main` sends a new build to TestFlight. TestFlight builds expire after 90 days,
so push (or re-run the workflow) at least that often; your data stays on the phone across updates.

## Without the paid account
The `build` job also produces `ShotLog-unsigned.ipa` (Actions run → Artifacts). You can install
that from Windows with Sideloadly and a free Apple ID, but it must be re-installed every 7 days.

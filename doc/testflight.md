# Getting this into TestFlight

There is no Xcode project, so the pieces Xcode would make behind the scenes
are made by hand, once, in a browser. After that every build is
`make testflight`.

## Once

Already on this machine, and shared with the other apps under the team
`Q47YS469F2`: an **Apple Distribution** certificate in the keychain, and an
**App Store Connect API key** in `~/.appstoreconnect/private_keys/`.

1. **Register the App ID.**
   [Identifiers](https://developer.apple.com/account/resources/identifiers/list)
   › **+** › App IDs › App. Description `UPC Logger`, Bundle ID **explicit**,
   `com.burnsidemk.upclogger`. No capabilities: the camera and the photo
   library need none.

2. **Make an App Store profile.**
   [Profiles](https://developer.apple.com/account/resources/profiles/list)
   › **+** › Distribution › **App Store Connect** › App ID
   `com.burnsidemk.upclogger` › the Apple Distribution certificate › name it
   `UPC Logger App Store` › Generate › Download, and put it where
   `IOS_DISTRIBUTION_PROFILE` in `local.mk` says. It grants
   `beta-reports-active`, which is what lets a build be tested in TestFlight.

3. **Create the app in App Store Connect.**
   [Apps](https://appstoreconnect.apple.com/apps) › **+** › New App. iOS;
   name `UPC Logger` (or whatever is free -- the store name need not match
   `CFBundleName`); bundle ID `com.burnsidemk.upclogger`; SKU `upc-logger`.

4. **The issuer id.** Users and Access › Integrations › App Store Connect
   API: the **Issuer ID** is above the list of keys. It goes in
   `ASC_ISSUER_ID` in `local.mk`.

`local.mk` then holds:

```make
IOS_DISTRIBUTION_IDENTITY = Apple Distribution: Your Name (TEAMID1234)
IOS_DISTRIBUTION_PROFILE = /path/to/UPC_Logger_App_Store.mobileprovision
IOS_DEVELOPMENT_TEAM = TEAMID1234
ASC_KEY_ID = XXXXXXXXXX
ASC_ISSUER_ID = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

## Every build

```sh
make testflight              # build, check, validate, upload
make testflight BUILD=1.0.90 # a build number of your own
make ipa                     # just build/UPC-Logger.ipa
```

The build is for the device alone, from a clean `build/iphoneos`, numbered
`1.0.<commits>` so it never goes backwards and says which commit a tester
holds. Before anything is sent, `tools/testflight.sh` checks that the
signature is an Apple Distribution one, carries `beta-reports-active` and
not `get-task-allow`; then `altool` validates and uploads.

`CFBundleShortVersionString` stays `1.0`; raise `:bundle-short-version` in
`upc-logger-app.asd` when the app itself changes version.

## Then, in App Store Connect

Processing takes a few minutes, after which the build is under
**TestFlight**. Internal testers -- your own team -- can install it at once,
with no review. External testers need Beta App Review, and before that
**App Privacy** (everything is "Data Not Collected": nothing leaves the
phone except what you share yourself) and Test Information.

Export compliance is already answered: `ITSAppUsesNonExemptEncryption` is
false in the plist.

## If the upload is refused

- *"Invalid Code Signing Entitlements"* -- the profile is not for
  `com.burnsidemk.upclogger`, or is a development one.
- *"... does not include the beta-reports-active entitlement"* -- an Ad Hoc
  or Development profile. Make an App Store one (step 2).
- *"The bundle version must be higher ..."* -- commit, or pass `BUILD=`.
- *"No suitable application records were found"* -- step 3 is not done.

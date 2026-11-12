# SafeCampus

SafeCampus is a campus safety mobile application for students, campus
responders, and administrators. Students can report incidents, trigger SOS
alerts, manage their profile and emergency contacts, view safety locations,
and contact campus helplines. Responders can triage and update incidents, and
administrators can manage accounts, campus data, and incident summaries.

## Requirements

- Flutter SDK compatible with the Dart constraint in `pubspec.yaml`
- A Firebase project configured for the platforms you want to run

## Firebase setup

Firebase configuration is intentionally not committed to this public
repository. Before running the app:

1. Create or select an authorized Firebase project.
2. Configure FlutterFire for the platforms you need. This generates
   `lib/firebase_options.dart`, which is ignored by Git.
3. For Android, add your own `android/app/google-services.json` from the
   Firebase Console.
4. Enable the Firebase services used by the app and deploy the repository's
   Firestore rules and Cloud Functions as appropriate.

Do not commit Firebase service-account keys, signing keys, or other private
credentials.

## Publish the web app

The GitHub Actions workflow builds the web app using the Firebase options
provided as a repository secret. In the GitHub repository settings:

1. Add an Actions secret named `FIREBASE_OPTIONS_DART` containing the contents
   of your locally generated `lib/firebase_options.dart`.
2. Under **Settings → Pages**, set the build and deployment source to
   **GitHub Actions**.
3. In Firebase Authentication, add `knp1325.github.io` to the authorized
   domains for the web app.
4. Push to `main` or run the **Deploy SafeCampus web app** workflow manually.

After a successful deployment, the app will be available at
`https://knp1325.github.io/SafeCampus/`. Firebase web options are client-side
configuration and will be included in the published web bundle; never use a
service-account key or other private credential for this setting.

## Run the application

From the project directory:

```sh
flutter pub get
flutter run
```

Select an available target with `flutter devices`, or specify one, for example:

```sh
flutter run -d chrome
```

## Campus safety locations

Administrators can add, edit and remove named safety locations under Campus
Data. Students see them in Helpline Contacts alongside the existing phone
numbers. These descriptions do not place markers on the map. Any previously
saved map markers remain visible on the map but cannot be managed in the admin
screen. Verify descriptions with campus staff before relying on them. No phone
numbers are supplied for these locations.

For initial setup only, an operator with Firebase application-default
credentials can run `node functions/scripts/add_potsdam_safety_locations.js`.
It creates the safety locations document only if it does not already exist and
never overwrites existing locations. Later changes should be made in the admin
screen.

## Technology

- Flutter and Dart
- Firebase Authentication, Cloud Firestore, Cloud Functions, and Cloud
  Messaging
- OpenStreetMap tiles via `flutter_map`

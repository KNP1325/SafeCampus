# SafeCampus responder notifications

When deployed, the `notifyRespondersOnIncident` Cloud Function sends Firebase
Cloud Messaging push notifications when a new document is created in
`incidents`. It checks each registered device against the account's current
Firebase Authentication custom claim before sending. Notification text avoids
student identity, location, and incident-description details; responders must
open the app to review the secured incident record.
The trigger retries delivery failures. Since FCM delivery is at-least-once,
some devices may receive a duplicate notification if a retry follows a partial
success.

The function is configured for `africa-south1`, matching the SafeCampus
Cloud Firestore location.

## Spark-plan admin operations

Student registration is restricted to a nine-digit student number at
`@mywsu.ac.za`. New students begin as `pending`; Firebase sends an email
verification link, and the account activates automatically after the verified
student signs in. Firestore rules require Firebase's verified-email token claim
for this transition. This verifies control of the email address, not enrollment
against an official university roster.

System managers can submit an admin-access request with their real email and
nine-digit staff number. They use that real email and password for login and
password reset; the staff number is only used for identification during
operator verification. Registration never grants an admin role. After checking
the request and the user's verified email, a trusted operator can assign the
admin role using the script below. For a `manager_request`, the script activates
the profile as part of that trusted operation.

On the Spark plan, the dashboard supports Firestore-only account deactivation
and reactivation. This updates `accountStatus`, which the app checks at sign-in.
It does not disable Firebase Authentication, revoke tokens, or prevent a
modified client from authenticating; do not treat it as a security-grade
suspension. Firestore rules restrict access to approved-user operations, while
the owner can still read their own profile and incident records.

In-app staff approvals, role changes, permanent account deletion, and campus
broadcasts are unavailable without a trusted backend. Do not grant clients
permission to change their own role or another user's custom claims. A trusted
operator can continue to assign roles with the `set-staff-role` script below;
the script runs on the operator's machine and is not a Cloud Function. Student
deactivation does not delete or anonymize reports.

Campus map markers and helpline contacts are stored in Firestore and can only
be edited by admins. All signed-in users can read this public campus resource
data. The Safe Map opens saved coordinates in Google Maps; it does not embed a
native map view.

The incident notification and campus broadcast functions in `index.js` are
available only when deployed to a project that supports Cloud Functions.

## Grant a responder role

Only a trusted administrator workstation should assign roles. Install the
Google Cloud CLI and authenticate Application Default Credentials as an
operator who is permitted to manage Firebase Authentication:

```powershell
gcloud auth application-default login
gcloud config set project safecampus-1f0a3
```

Find the staff member or manager's Firebase Auth UID in Firebase Console →
Authentication → Users. Verify their employment and registration request
before assigning a role. For a manager request, first ensure the person has
verified their real email. Then from the project root run:

```powershell
npm --prefix functions install
npm --prefix functions run set-staff-role -- FIREBASE_AUTH_UID campus_security
```

Valid roles are `campus_security`, `medical_services`, `fire_services`,
`student_welfare`, and `admin`. Do not place service-account keys in the
repository or let users set claims through the Flutter app. Staff must sign out
and sign in again after their role is assigned.

## Deploy rules on Spark

From the project root:

```powershell
firebase deploy --project safecampus-1f0a3 --only firestore:rules
```

Do not include `functions` in the deploy command on Spark. Deploying Cloud
Functions requires the Blaze (pay-as-you-go) plan and Google Cloud build APIs.

The `cloud_functions` package remains in the dependency manifest for a future
backend deployment; the Spark-plan dashboard does not call it.

## Device setup and test

On Android, install the updated Flutter app and allow notifications. User
tokens are stored under `user_tokens/{uid}/devices`; responder tokens are also
stored under `staff_tokens/{uid}/devices`. A new student incident or SOS
generates a notification for matching responder teams and admins, while
campus-wide broadcasts go to active registered user devices.

Responder and campus-wide push notifications sent by Cloud Functions are
unavailable until those functions are deployed. While the app is in the
foreground, the responder queue updates live; a foreground notification banner
is not configured.

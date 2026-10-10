// Where the extension's iCloud data is: the same CloudKit container as the
// Safience app, and an API token made for it in CloudKit Console. The token
// identifies the extension to CloudKit, not the user; it ships inside the
// extension, as a web page's CloudKit token does. See README.md.
export default {
  container: 'iCloud.net.taehee.safience',
  // The app's debug builds use 'development'; TestFlight and the App Store, 'production'.
  environment: 'development',
  // CloudKit Console › the container › API Access › API Tokens.
  apiToken: '',
};

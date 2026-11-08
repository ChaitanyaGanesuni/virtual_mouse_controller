/**
 * Signs release builds with your own upload key instead of the shared debug key.
 * The key itself is never committed: point these environment variables at it when building.
 *
 *   PAISA_KEYSTORE=/path/paisa-watch-upload.jks
 *   PAISA_KEYSTORE_PASSWORD=...
 *   PAISA_KEY_ALIAS=paisa-upload
 *   PAISA_KEY_PASSWORD=...
 *
 * Without them, release builds fail instead of silently falling back to the debug key,
 * because an APK signed with a different key cannot update one that is already installed.
 */
const { withAppBuildGradle } = require('expo/config-plugins');

const SIGNING = `
        release {
            def ks = System.getenv('PAISA_KEYSTORE')
            if (ks) {
                storeFile file(ks)
                storePassword System.getenv('PAISA_KEYSTORE_PASSWORD')
                keyAlias System.getenv('PAISA_KEY_ALIAS') ?: 'paisa-upload'
                keyPassword System.getenv('PAISA_KEY_PASSWORD') ?: System.getenv('PAISA_KEYSTORE_PASSWORD')
            }
        }`;

const GUARD = `
gradle.taskGraph.whenReady { graph ->
    if (graph.allTasks.any { it.name.toLowerCase().contains('release') } && !System.getenv('PAISA_KEYSTORE')) {
        throw new GradleException('Set PAISA_KEYSTORE (and its passwords) to sign the release build with your own key. See README.')
    }
}
`;

module.exports = function withReleaseSigning(config) {
  return withAppBuildGradle(config, (c) => {
    let g = c.modResults.contents;
    if (g.includes('PAISA_KEYSTORE')) return c;

    const buildTypesAt = g.indexOf('buildTypes {');
    const releaseAt = g.indexOf('release {', buildTypesAt);
    const debugSign = g.indexOf('signingConfig signingConfigs.debug', releaseAt);
    if (buildTypesAt < 0 || releaseAt < 0 || debugSign < 0) {
      throw new Error('withReleaseSigning: unexpected android/app/build.gradle layout');
    }
    g = g.slice(0, debugSign) + 'signingConfig signingConfigs.release' + g.slice(debugSign + 'signingConfig signingConfigs.debug'.length);
    g = g.replace(/signingConfigs \{/, 'signingConfigs {' + SIGNING);
    g += GUARD;
    c.modResults.contents = g;
    return c;
  });
};

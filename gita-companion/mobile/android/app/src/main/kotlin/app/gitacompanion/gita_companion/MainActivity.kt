package app.gitacompanion.gita_companion

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity keeps the Flutter engine shared with the background
// audio service, so listening continues when the app is in the background.
class MainActivity : AudioServiceActivity()

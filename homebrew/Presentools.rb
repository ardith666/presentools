cask "presentools" do
  version "0.4.0"
  sha256 "42899e2a9c289ee54b68c0b2c27b1edc5a10e4de13fd5c4bcc3143761befacf2"

  url "https://github.com/ardith666/presentools/releases/download/v#{version}/Presentools-#{version}.dmg"
  name "Presentools"
  desc "Spotlight, Laser Pointer, and Zoom Lens for macOS presentations"
  homepage "https://github.com/ardith666/presentools"

  depends_on macos: :tahoe

  app "Presentools.app"

  # Ad-hoc signed with no Developer ID, so quarantine stays on: Homebrew must
  # not strip it, or the first launch stops telling the user the app is
  # unsigned. They right-click Open once, same as the DMG path.
  auto_updates true
end
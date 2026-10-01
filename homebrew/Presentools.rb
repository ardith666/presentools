cask "presentools" do
  version "0.3.0"
  # Filled in after the release DMG is built; see knowledge/history.md.
  sha256 ""

  url "https://github.com/ardith666/presentools/releases/download/v#{version}/Presentools-#{version}.dmg"
  name "Presentools"
  desc "Spotlight, Laser Pointer, and Zoom Lens for macOS presentations"
  homepage "https://github.com/ardith666/presentools"

  depends_on macos: ">= :tahoe"

  app "Presentools.app"

  # Ad-hoc signed with no Developer ID, so quarantine stays on: Homebrew must
  # not strip it, or the first launch stops telling the user the app is
  # unsigned. They right-click Open once, same as the DMG path.
  auto_updates true
end
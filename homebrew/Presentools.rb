cask "presentools" do
  version "0.3.0"
  sha256 "878b948e30fa34d18797b19c9aee10553321f40c6888465cd0ca325bfaf81b5d"

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
cask "presentools" do
  version "0.5.1"
  sha256 "8a0f4bc305fce2909085f397fd2a85426e132e75d64bd9490605df5ba0b07b37"

  # The asset is named without a version so the website can link to
  # /releases/latest/download/Presentools.dmg and never go stale. The tag is
  # still pinned here: a cask URL must resolve to one immutable artifact.
  #
  # The sha256 above is of the exact file uploaded as this release's asset.
  # `make-dmg.sh` is not byte-reproducible — `hdiutil create` mints a new
  # volume identifier every run, so two consecutive builds of identical input
  # hash differently. Rebuild and re-upload without re-running the script, or
  # the digest below no longer matches what Homebrew downloads.
  url "https://github.com/ardith666/presentools/releases/download/v#{version}/Presentools.dmg"
  name "Presentools"
  desc "Spotlight, Laser Pointer, and Zoom Lens for macOS presentations"
  homepage "https://github.com/ardith666/presentools"

  # Ad-hoc signed with no Developer ID, so quarantine stays on: Homebrew must
  # not strip it, or the first launch stops telling the user the app is
  # unsigned. They right-click Open once, same as the DMG path.
  auto_updates true
  # macOS 15.2, which `LSMinimumSystemVersion` in the app's Info.plist also
  # declares. That is the floor `SCScreenshotManager.captureImage(in:)` sets for
  # Zoom Lens; the other two effects have nothing newer. :sequoia is 15 and
  # :tahoe is 26, so naming 26 here would have let Homebrew install the app on a
  # machine the app refuses to run on.
  depends_on macos: :sequoia

  app "Presentools.app"
end

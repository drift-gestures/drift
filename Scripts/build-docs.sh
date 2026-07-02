xcodebuild docbuild \
  -scheme "drift" \
  -destination "generic/platform=macOS" \
  OTHER_SWIFT_FLAGS="-symbol-graph-minimum-access-level private"


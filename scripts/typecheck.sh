#!/usr/bin/env bash
# Compile-check App/Sources against the iOS SDK on Linux (needs: xtool sdk installed).
# Zsign (C++/OpenSSL) is replaced by a stub with the same Swift signature: this checks OUR code only.
# Real linking/packaging is done by GitHub Actions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="${TYPECHECK_DIR:-${TMPDIR:-/tmp}/infinityx-typecheck}"
mkdir -p "$T/Sources" "$T/zsign-stub/Sources/Zsign"
ln -sfn "$ROOT/App/Sources" "$T/Sources/App"

cat > "$T/zsign-stub/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "zsign-stub", platforms: [.iOS(.v12)],
  products: [.library(name: "Zsign", targets: ["Zsign"])], targets: [.target(name: "Zsign")])
SWIFT
cat > "$T/zsign-stub/Sources/Zsign/Zsign.swift" <<'SWIFT'
// Stub: same public signature as khcrysalis/Zsign-Package. Update if SigningEngine uses more of its API.
public enum Zsign {
    static public func sign(
        appPath: String = "", provisionPath: String = "", p12Path: String = "", p12Password: String = "",
        entitlementsPath: String = "", customIdentifier: String = "", customName: String = "",
        customVersion: String = "", adhoc: Bool = false, removeProvision: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) -> Bool { true }
}
SWIFT
cat > "$T/Package.swift" <<SWIFT
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "TypecheckApp",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(path: "$ROOT/Packages/InfinityXCore"),
        .package(path: "zsign-stub"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [.executableTarget(name: "App", dependencies: [
        "InfinityXCore", .product(name: "Zsign", package: "zsign-stub"), "ZIPFoundation",
    ], path: "Sources/App")]
)
SWIFT

cd "$T"
# --build-system native: the default one fails with "unable to find platform for 'iphoneos'" on Linux.
swift build --swift-sdk arm64-apple-ios --build-system native 2>&1 | grep -E "error|warning: .*App/Sources|Build complete" || true
swift build --swift-sdk arm64-apple-ios --build-system native >/dev/null 2>&1 && echo "OK" || { echo "FAILED"; exit 1; }

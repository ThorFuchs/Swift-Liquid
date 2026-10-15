# Package discovery and installation

The canonical package URL is
`https://github.com/ThorFuchs/Swift-Liquid.git`. Public releases use immutable
semantic-version tags; the current stable release is
[1.3.0](https://github.com/ThorFuchs/Swift-Liquid/releases/tag/1.3.0). The README
links to that release, qualification archives, Apache-2.0 terms and the hosted
[documentation](https://thorfuchs.github.io/Swift-Liquid/). `.spi.yml` directs the
package index to that same documentation site.

## Verify a public installation

Use Swift tools/compiler 6.4 or later, in Swift language mode 6. To build the
published CLI from a clean directory:

```sh
git clone --branch 1.3.0 --depth 1 https://github.com/ThorFuchs/Swift-Liquid.git
cd Swift-Liquid
swift build -c release --product liquid
swift run -c release liquid --version
```

Select the supported Xcode using `DEVELOPER_DIR` if your default compiler is older.
For a library target, use the repository URL and `Liquid` product shown in the
[README](../README.md#installation). The root package has no package dependencies;
Foundation and Swift Testing are supplied by the SDK/toolchain.

```sh
python3 -B Scripts/ci.py --lane installation
```

This additional qualification lane checks the immutable 1.3.0 compatibility anchor,
not a moving branch or an unpublished candidate version. It clones the tag through
the public URL, verifies its peeled commit, dumps the root package graph, builds
the release CLI and checks version/render/validation behavior. A separate fresh
consumer resolves the public package URL at exact version 1.3.0 and executes the
public examples. Source, build scratch, dependency stores, configuration and module
caches are temporary and fresh; global Git credentials/configuration are disabled.
The receipt retains commands, resolved revision, manifest, lockfile and output hash.
No build output, reference clone or credentials enter Git.

The native and clean-archive lanes separately qualify the current candidate's
public consumers. The installation lane complements those checks by testing the
published URL path. It is part of the CI matrix and release-evidence admission.

## Package-index status

On 2026-10-15, the official
[Swift Package Index package list](https://github.com/SwiftPackageIndex/PackageList)
contained Swift-JSON and RhoeLiquid, but did not contain Swift-Liquid. An index
submission is a separate registration change, not an automatic listing. Do not add
an index badge or claim index build/platform results until a live package page
supports it. Recheck the official list and page when the registration is accepted.

The separately submitted [registration PR #15709](https://github.com/SwiftPackageIndex/PackageList/pull/15709)
adds only this URL, preserving the list's case-insensitive
ordering and `.git` suffix. Before submission, the list was refreshed and checked for equivalent URLs or
pending registrations. Acceptance and ingestion are controlled by the index. The index's
[inclusion requirements](https://github.com/SwiftPackageIndex/PackageList#the-swift-package-index)
include a public valid package, a semantic-version release, successful compilation
and valid `swift package dump-package` output. Our installation receipt checks those
package properties with Swift 6.4; it does not imply the index currently offers every
required compiler or that its maintainers have accepted the package.

## Platform claims

Runtime qualification covers macOS 27 on the recorded Swift 6.4 host. The four Apple
simulator-SDK gates establish compilation, not execution on devices or older OS
versions. Declared deployment minimums remain macOS 14, iOS 17, tvOS 17, watchOS 10
and visionOS 1. Linux, WASI and browser execution have no runtime qualification
claim. Index badges, if added later, report the index's own observed matrix and
must not replace these distinctions.

# Continuous Integration

Sealbreak uses one GitHub Actions workflow for pull-request and main-branch validation.

Fast static checks are defined in `.pre-commit-config.yaml` so the same checks can run locally and in CI. The quality job runs those hooks plus the Swift package model tests. Simulator compilation, CodeQL security analysis, and SonarQube Cloud run as independent jobs so they do not unnecessarily extend the critical path.

The only CI helper script retained is `scripts/ci/build.sh`, which centralizes the shared `xcodebuild` invocations for Simulator Debug builds and unsigned device Release archives.

The workflow pins Xcode through `DEVELOPER_DIR` and pins third-party GitHub Actions to commit SHAs. SwiftFormat and SwiftLint versions are pinned by the pre-commit configuration and Renovate maintains those hook references.

SonarQube Cloud currently performs its native Swift analysis and quality gate without a custom coverage import. Coverage should be reintroduced through Xcode test result bundles and `xccov` once the project has a dedicated iOS test target, rather than through a repository-specific conversion script.

Local setup:

```sh
python3 -m pip install pre-commit==4.6.2
pre-commit install
```

Run the same static checks as CI with:

```sh
pre-commit run --all-files
```

Run model tests with:

```sh
swift test
```

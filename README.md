# Sealbreak

Sealbreak is a minimal iOS prototype for manually unsealing an OpenBao node with a locally protected Shamir share and Face ID authorization.

## Development

The project uses GitHub Actions for independent quality, test, build, and SonarQube Cloud gates. The dedicated `CI / tests` job runs the non-UI behavior tests, enforces the configured 100% behavior-code coverage threshold, and publishes the generated Sonar coverage report for the downstream Sonar job.

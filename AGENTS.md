# Agent Instructions

## Architecture

Before adding or modifying code, read `docs/architecture.md`.

Follow the documented module boundaries. Place each responsibility in the appropriate module, and split changes across modules where required by the architecture.

## Threat Model

After every code change, assess whether it affects `THREAT_MODEL.md`.

If it does, identify what is affected and explain why. Do not modify `THREAT_MODEL.md` unless explicitly requested.

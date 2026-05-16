# DirectMFTParsing (historical snapshot)

This folder is a **historical snapshot** of the `DirectMFTParsing` C++ tool as it existed in the external `mft/` development tree on 2026-02-11. It is preserved here for reference only.

## Canonical location

The production / current version lives at `CLAWS/DirectMFTParsing/` at the repo root. That is the version that should be built, deployed, and modified.

## Why keep this copy

The snapshot contains experimental and debug code paths that were trimmed before the merged version landed under `CLAWS/`. The Feb-11 file is larger (93 KB vs 77 KB in CLAWS) because it carries this extra material. Keeping it lets future investigators see the pre-cleanup state of the tool, in particular the experimental code referenced by the analysis docs under `MFT/docs/`.

## Do not edit

Do not make changes to files in this directory. Any fixes or feature work belong in `CLAWS/DirectMFTParsing/`. If this snapshot ever needs to be regenerated, copy from the original `mft/cpp/DirectMFTParsing/` working tree rather than editing in place.

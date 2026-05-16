# PowerShell Modules

Reusable PowerShell modules. Each subfolder is an importable module with its own manifest, sources, and (where present) tests.

## Modules

| Module | Purpose |
|---|---|
| `Cloud-API/` | Function wrappers for the SS&C Cloud API, intended to act as an API provider for future Windows-team scripting. Work in progress. See `Cloud-API/Readme.md`. |
| `DiagBundle/` | One-shot Windows Server diagnostic bundle collector. Produces a zip containing pre-aggregated JSON summaries, raw artifacts (EVTX, CBS.log, perf BLG, etc.), and a manifest with provenance and checksums -- designed for AI-assisted post-incident analysis. See `DiagBundle/CLAUDE.md` for design context and `DiagBundle/Resources/README.md` for user-facing docs. |
| `Resilio-API/` | Function wrappers for the Resilio Management Console and Agent APIs. Work in progress. See `Resilio-API/Readme.md`. |
| `WSUSTools/` | WSUS administration helpers. Targets PowerShell 5.1 / Windows PowerShell. See the manifest at `WSUSTools/WSUSTools.psd1`. |

## Loading a module

From the repo root:

```
Import-Module .\Powershell\Modules\DiagBundle\DiagBundle.psd1
```

For modules without a `.psd1` manifest (`Cloud-API`, `Resilio-API`), import the `.psm1` directly:

```
Import-Module .\Powershell\Modules\Cloud-API\Cloud-API.psm1
```

Once imported, `Get-Command -Module <name>` lists everything the module exports.

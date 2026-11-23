# Validation record

Status: **experimental / partial**, as of 23 November 2026. Native testing used Windows 11, Windows PowerShell 5.1.26100.9818, and Altium Designer 25.8.1.18 under a standard user account.

## Published runtime provenance

The released installer and runtime source are byte-identical to the native-tested installer 0.2.1. Public packaging adds English documentation, a license, integrity/build tools, and selected synthetic evidence. It does not broaden the generator's capabilities. SHA-256 values are checked by `tools/check_release.py`:

| File | SHA-256 |
| --- | --- |
| `install.ps1` | `d5162da75dfc8dfcbc4991cea56db914902c86e97259bdd5ad299e7d614b5c88` |
| `source/CopperBalancing.pas` | `4688814a89dbf7e6e36cb01756f2581a7a885e3f98c27e99bbdf053400b3495b` |
| `source/CopperBalancing.PrjScr` | `eb4de4e69da082ce5223284f907397b21902f07bb6f9bf1391913469ced781ea` |
| `TestBoard.PcbDoc` | `ad8417267b18a9d3c9367bb87605c70e3fff639df313ec5cbea132c62df39cb9` |

## Installer 0.2.1: demonstrated inside Altium

- The interactive `Install.cmd` discovered the registered executable/profile and installed in LocalAppData, without administrator rights.
- Existing DXP.RCS content was preserved byte for byte; the installer appended only its owned resource block, with backups before writes.
- On a fresh Designer start, Tools → Copper Balancing → Generate / Regenerate / Remove appeared without manual customization.
- Generate opened the native dialog and created 432 no-net diamonds: 108 each on Top, Mid1, Mid2, and Bottom. The two negative internal planes were disabled and received no islands. Runtime: 3.531 seconds.
- Regenerate with Mid1 alone replaced those islands with 108 on Mid1. Runtime: 2.500 seconds.
- Remove deleted the 108 verified owned regions. Runtime: 0.438 seconds.
- Independent parsing of saved snapshots found the original modeled board stack, tracks, split-plane definitions, rules, and other non-owned objects preserved. Expected save metadata, viewport, and UsedByPrims caches were excluded.
- A repeat install while Designer was running was refused without changing DXP.RCS; read-only Check succeeded. Setup never closes Designer or saves projects.

Seven temporary-profile test groups passed: repeat install/uninstall and restoration of pre-existing source; UTF-16/Unicode and preservation of later unrelated edits; refusal of locally modified source/menu; malformed ownership markers; read-only profile; changed payload; initially absent DXP.RCS. The suite ran before the final state-format identity guard was added. The final guard and installer were then exercised by actual installation, Check, and running-application refusal. Those are distinct scopes, not a claim that the whole suite was rerun on final code.

One real installation and fresh start were tested. Repeated restart cycles, Altium rewriting resources, multi-installation selection, other machines/versions, corporate policies, and power failure between filesystem writes remain unqualified. Backups and ownership state are required for recovery.

## Earlier generator tests: separate historical scope

The earlier 0.1 generator demonstrated diamond, square, and hexagonal regions; selected rectangular area; manual selection/Delete; regeneration after a layout change and manual deletion; name/manifest ownership after save/reopen; preservation of an unrelated named union; and conservative explicit HV net/distance exclusion on a synthetic board. An empty 400 × 300 mm board generated 2262 islands at 10 mm pitch in 31.828 seconds. This is not a dense-board performance guarantee.

A complete historical synthetic DRC run reported 773 violations: 770 intentional no-net islands, a deliberate no-net test track, an original unrouted via, and a deliberate test-track width violation. It reported zero clearance, short-circuit, or modified-polygon violations. Gerber and ODB++ checks matched all 770 tested external-layer hexagons. Those results are historical 0.1 tests; installer 0.2.1 did not rerun those exports or establish internal-layer manufacturing qualification.

Version 0.2 added native V7 layer-stack enumeration and selected-layer operation. A six-layer fixture demonstrated the four positive/two negative selection behavior, subset regeneration, and save/close/reopen followed by removal. Version 0.2.1 relocated stage diagnostics beside the saved PCB and added the automatic installer; it retained the geometry/ownership algorithms.

This repository includes the installer-era synthetic fixture, three saved result snapshots, screenshots, and machine-readable preservation results. Earlier 0.1 export artifacts are not bundled; their historical summary is not a newly reproduced check of this release.

## Optional independent snapshot check

`tools/verify_native.py` reads the supplied native snapshots using external `altium-monkey` (2026.9.22, upstream commit `aa9e39c3be9aeba8f11eb7cb9773e42dfafd37b9`). It verifies counts, layers, region properties, and modeled preservation; it does not execute Designer or establish electrical signoff. This dependency has its own AGPL-3.0-or-later license and is not bundled or required to install/run the generator.

## Remaining limitations

- No arbitrary outline or rigid-flex support in the standard generator.
- Conservative cross-layer bounding boxes; no polygon clipping, local density target, or optimization of layer-to-layer copper balance.
- No native named union creation; persistent names plus sidecar fingerprints are the tested fallback.
- DRC rules are not automatically resolved into exclusion distances. User settings must be checked against actual scoped rules. No-net islands commonly trigger dead-copper reports, which can exhaust the report limit.
- No automatic removal of existing no-net polygons. Existing polygons remain obstacles regardless of net.
- Interruption, Undo recovery, and future profile reserialization are not fully qualified.
- HV exclusions are explicit user-specified geometry only; no verified voltage-to-distance mapping, creepage calculation, or insulation approval.
- No production, SI/PI, EMI, or fabrication signoff.

## Primary API references

- [Altium server resource files](https://www.altium.com/documentation/altium-dxp-developer/server-configuration-files): process launchers and menu insertions.
- [Running Altium scripts](https://www.altium.com/documentation/altium-designer/scripting/running-scripts): script process parameters.
- [PCB layer-stack V7 interface](https://docs.developer.altium.com/ad-sdk-docs/reference/pcb/IPCB_LayerStack_V7/): layer enumeration. Native execution, rather than documentation alone, established the APIs used in the release.

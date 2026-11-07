# Standalone L3 carrier in GenThang

This fabrication/assembly package is imported from
[genthang-hw commit 3821f5d](https://github.com/shawnchivers/genthang-hw/commit/3821f5ddea4697ffd93e5d038287d4379023c5a5),
which includes the L3 GPIO17 PCB revision and its colorful build guide.

The ordered L3 OSH Park and generic Gerber archives are unchanged. The stock BOM
uses 10 nF at C1/C2; 47 nF and 56 nF are optional assembly substitutions.
Historical L2 archives, router/session files and stale preview images are not
part of this standalone package.

Ordering and hand assembly do not require a sibling hardware checkout.
Regeneration uses the existing shared helpers in the parent `hardware/` folder.
The generator audits this GenThang repository's live DB9 constraints.

From this directory:

```sh
bash ../cad-python -m unittest discover -s . -p 'test_build_board.py'
bash ../cad-python build_board.py check
bash ../cad-python build_board.py checksums
sha256sum -c SHA256SUMS
```

`check` regenerates CAD reports. Run `checksums` afterwards to refresh their
hashes without re-exporting the already-ordered Gerbers.
The illustrated [build guide](index.html) works offline from this checkout.

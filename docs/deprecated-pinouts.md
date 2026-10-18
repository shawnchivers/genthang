# Deprecated controller pinouts

These layouts are retained for reproducing older hardware and firmware only.
They are not included in current releases. New designs should use the single
canonical J6/J5 physical pinout documented in the main README:

- `GT_PAD=db9` for Genesis controllers.
- `GT_PAD=raw` for twelve direct switches (handheld pinout).

The DualShock 2 build (`GT_PAD=ds`) has been removed; use a release up to 1.6.2 to
reproduce it.

## Original single-DB9 breadboard

The first tested Genesis breadboard crossed between J6 and J5 and used a separate
`db9_breadboard` image. It is superseded by the canonical P1-on-J6 mapping. Its
complete wiring table, photographs, drawings, and bench notes remain in
[single-db9-breadboard.md](single-db9-breadboard.md).

The old `GT_PINOUT=breadboard` and `GT_PINOUT=breadboard-rev1` values are accepted
only as deprecated aliases for canonical `GT_PAD=db9`; they no longer reproduce
the retired wiring.

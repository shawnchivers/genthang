# Assembly instructions — dual-db9-opt-pcb O1, KYCON ONLY

## Scope: 4 through-hole components on top

1. J6 and J5: Harwin **M20-7822046**, 20-position female sockets, 8.5 mm body height.
   TOP side, openings up, soldered from the bottom. Parallel, straight, flush and
   unstressed at 20.32 mm row spacing; use a jig and do not solder the Nano in place.
   Pin 1 is the square pad, nearest the USB-C end.
2. J1 (player 1, left) and J2 (player 2, right): Kycon **K22X-E9P-N**, male right-angle
   DB9. TOP mounted, noses facing out across the BOTTOM edge. Solder all 9 signal pins
   and both boardlocks. Use the N option (recessed 4-40 inserts), **not NJ**.
3. H1-H4: mounting holes only. No component, rivet, metal standoff or solder.
4. The Nano is not part of the assembly; insert the separately flashed module afterwards.

There are 62 plated component holes (40 socket contacts + 18 DB9 pins + 4 boardlocks)
plus 4 nonplated mounting holes. No SMT parts, stencil or
centroid. THT-placement-reference.csv gives footprint pin-1 anchors in mm from the
bottom-left corner (X right / Y up), a manual insertion aid only.

## Connector geometry (relative to each DB9's pin 1; same for J1 and J2)

Pin pitch 2.77 mm, row offset 2.84 mm (pins 1-5 back row, 6-9 front row offset by
1.385 mm), boardlocks at -6.955 mm and +18.035 mm (3.05 mm holes, 24.99 mm apart),
signal holes 1.09 mm, flange 10.92 mm forward of pin 1. J1 pin 1 = (16.46, 59.08) mm,
J2 pin 1 = (72.46, 59.08) mm. Do not mirror the footprint in assembly; the drawing is a top view.

## Bring-up (ordering of steps matters)

1. Continuity-test every row of net-test.csv with the Nano removed. Check 3V3 and GND are
   not shorted and J5.1 (Nano 5 V) reads open to everything.
2. Insert the Nano with the standard Gen Thang `db9` bitstream loaded and no controller attached;
   check about 3.3 V between DB9 pins 5 and 8 on both ports.
3. Unplug USB, attach one controller, power from USB. Test each port on its own, then both.
   Never plug or unplug a controller while powered.

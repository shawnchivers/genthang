# Assembly guide — L3 two-player carrier with line-out

For the colorful step-by-step walkthrough and simple capacitor shopping guide,
see the [illustrated L3 build guide](index.html#caps).

Everything is through-hole and goes on the **top** (silkscreen) side, soldered from the
bottom. Solder low parts first so the board lies flat on the bench.

With the DB9 ports at the front/bottom, the Tang sits sideways on the two **8.5 mm
female headers**: USB-C power faces **left**, HDMI faces **right**, and J3 audio
faces the **rear/top**. J5 is the rear socket row; J6 is the front row. Both square
pin-1 pads are at the left/USB-C end. Cable plugs pass above the carrier; no side
cutouts or separate USB-C power connector are needed. Use a 1:1 fit print and check
your actual cable housings before designing an enclosure or ordering a large batch.

## Tools

Soldering iron (fine conical or 2 mm chisel tip), 0.6–0.8 mm rosin-core solder, flush
cutters, a multimeter. A third hand or a piece of tape helps hold parts while you flip the board.

## Order

1. **R1, R2 — 1 kΩ** (brown black red). Bend the leads to the 7.62 mm hole spacing, push
   flat against the board, solder, trim. Direction does not matter.
2. **R3, R4 — 47 kΩ** (yellow violet orange). Same as above.
3. **C1, C2 — 10 nF** ceramic discs, marked `103`. Either direction.
   For the optional [Model 1-style filter](README.md#optional-model-1-style-low-pass-filter),
   fit **56 nF (`563`) for VA3–VA6-style** or **47 nF (`473`) for VA0–VA2-style**
   in both positions instead. All other component values stay unchanged.
4. **C3, C4 — 10 µF electrolytic.** **Polarized**: the long lead (+) goes in the
   **square pad**, next to the `+` mark on the silkscreen; the stripe on the can marks
   the minus lead. Follow the pad polarity, not the direction of the jack.
   Reversed electrolytics can fail.
5. **J3 — 3.5 mm jack.** Its three flat pins go into the slotted holes and its plastic
   locating pegs into the small round holes; the barrel overhangs the rear/top edge. Tack
   one pin, check that the jack sits flat and square, then solder all three.
   **Use only the CUI / Same Sky SJ1-3523N (3-pin) jack.** Do not substitute the
   handheld's 5-pin PJ-307 switching jack, even with legs trimmed: its pins do not match
   this footprint, so a channel can end up on a switch contact that opens when a plug is
   inserted, giving a quiet, humming channel. With a plug inserted, check continuity
   from plug tip to C3's jack-side lead, plug ring to C4's jack-side lead, and plug sleeve to GND.
6. **J5, J6 — Nano sockets.** Put both sockets on the Nano's pins, sit the Nano with
   its sockets in the board (it keeps them straight at the 20.32 mm spacing), tack the
   end pins of each socket, check they are flat, then remove the Nano and solder every
   pin. Pin 1 is the square pad at the left/USB-C end; do not reverse the Tang.
7. **J1, J2 — DB9.** Noses face out across the bottom edge. Solder all 9 pins and both
   boardlocks on each.

Count when you are done: 13 parts, 4 empty mounting holes (H1–H4).

## Check before power

With the Nano **removed**:

1. Use [net-test.csv](net-test.csv) for continuity: every DB9 pin to its Nano contact, and
   the audio rows (J6.14 to R1, **J6.15 to R2**, J3 tip to C3 minus, J3 ring to C4 minus,
   J3 sleeve to GND).
2. 3V3 to GND must **not** be a short. J5.1 (Nano 5 V) and J5.7 (old GPIO56 audio)
   are not connected to anything on L3.
3. C3 and C4: the `+` lead connects to R1 / R2, not to the jack.

## First power-up

1. Flash a matching DB9 image with **right audio on GPIO17 (J6.15)**, then insert
   the Nano directly into the sockets. No audio jumper is needed on L3.
   Released images through 1.9.2 use GPIO56 and do not match this board. See
   [firmware compatibility](README.md#firmware).
2. With no controller attached, power over USB; measure about 3.3 V between DB9 pins 5
   and 8 on both ports.
3. Power off, attach controllers, power on. Never plug or unplug a controller while powered.
4. Line-out: power off, plug a **powered** speaker (volume at zero) into J3, power on,
   start a game and raise the volume slowly. On a TV that flickers with HDMI, open the
   options menu and set **Video output** to **DVI+LINE OUT**.

Headphones: not supported directly; the line-out is meant for powered speakers, a
soundbar or an amplifier.

import hashlib
import re
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import pcbnew as p

import build_board as build


def routed_board():
    return p.LoadBoard(str(build.HERE / (build.NAME + '.kicad_pcb')))


def jack_pads(board):
    jack = next(fp for fp in board.GetFootprints() if fp.GetReference() == 'J3')
    return [pad for pad in jack.Pads() if pad.GetNumber()]


class LineoutLayoutTests(unittest.TestCase):
    def test_constraints_source_for_repository_layout(self):
        in_repo = build.ROOT.parent / 'src/boards/nano20k_db9.cst'
        if in_repo.exists():
            self.assertEqual(build.CST, in_repo)
        else:
            self.assertIn(build.CST, (build.LIVE_CST, build.REFERENCE_CST))
        self.assertEqual(build.audio_pins()['R'][1:], (17, 'J6', '15'))

    def test_checksums_include_guide_and_assets(self):
        files = ['README.md', 'TEST-STATUS.md', 'index.html',
                 'assets/bear.svg', 'assets/capacitors.svg']
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in files:
                file = root / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(name)
            with patch.object(build, 'HERE', root):
                build.checksums()
            actual = dict(line.split('  ', 1)[::-1]
                          for line in (root / 'SHA256SUMS').read_text().splitlines())
            expected = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                        for name in files}
            self.assertEqual(actual, expected)

    def test_rotated_socket_pin_contract(self):
        components = {c['ref']: c for c in build.design().components}
        for ref, y in (('J6', 41), ('J5', 20.68)):
            c = components[ref]
            self.assertAlmostEqual(c['x'], 25.87)
            self.assertAlmostEqual(c['y'], y)
            self.assertEqual(c['rotation'], 90)
        self.assertEqual(components['J6']['nets']['14'], 'AUD_L_PWM')
        self.assertEqual(components['J6']['nets']['15'], 'AUD_R_PWM')
        self.assertIsNone(components['J5']['nets']['7'])
        self.assertIsNone(components['J5']['nets']['1'])

    def test_both_controller_pinouts_unchanged(self):
        contacts = {
            1: {1: '1', 2: '2', 3: '5', 4: '8', 5: '19', 6: '9', 7: '12', 8: '20', 9: '13'},
            2: {1: '5', 2: '6', 3: '9', 4: '10', 5: '16', 6: '12', 7: '17', 8: '15', 9: '18'},
        }
        for player, pins in contacts.items():
            header = 'J6' if player == 1 else 'J5'
            for db9_pin, contact in pins.items():
                self.assertEqual(build.WIRES[player, db9_pin][1:], (header, contact))

    def test_routed_right_audio_contact(self):
        board = routed_board()
        sockets = {fp.GetReference(): fp for fp in board.GetFootprints()
                   if fp.GetReference() in ('J5', 'J6')}
        front = {pad.GetNumber(): pad.GetNetname() for pad in sockets['J6'].Pads()}
        rear = {pad.GetNumber(): pad.GetNetname() for pad in sockets['J5'].Pads()}
        self.assertEqual(front['14'], 'AUD_L_PWM')
        self.assertEqual(front['15'], 'AUD_R_PWM')
        self.assertEqual(rear['7'], '')

    def test_jack_slots_meet_oshpark_minimum(self):
        board = routed_board()
        self.assertEqual(build.check_oshpark_drills(board), 3)
        for pad in jack_pads(board):
            sizes = sorted((round(p.ToMM(pad.GetDrillSize().x), 3), round(p.ToMM(pad.GetDrillSize().y), 3)))
            self.assertEqual(sizes, [.6, 1.4])
            self.assertEqual(pad.GetAttribute(), p.PAD_ATTRIB_PTH)

    def test_oshpark_soldermask_web(self):
        board = routed_board()
        self.assertGreaterEqual(p.ToMM(board.GetDesignSettings().m_SolderMaskMinWidth), .1016)

    def test_firmware_silkscreen(self):
        board = routed_board()
        texts = [item.GetText() for item in board.GetDrawings() if isinstance(item, p.PCB_TEXT)]
        self.assertIn('GT_PAD=db9  AUDIO L31 / R17', texts)
        self.assertIn('2 PLAYER + LINE OUT / L3', texts)

    def test_oshpark_package(self):
        suffixes = ('-F_Cu.gtl', '-B_Cu.gbl', '-F_Mask.gts', '-B_Mask.gbs',
                    '-F_Silkscreen.gto', '-B_Silkscreen.gbo', '-Edge_Cuts.gm1',
                    '-PTH.drl', '-NPTH.drl')
        with zipfile.ZipFile(build.HERE / build.ZIP_OSHPARK) as archive:
            self.assertEqual(set(archive.namelist()), {build.NAME + s for s in suffixes})
            self.assertEqual(len(archive.namelist()), len(suffixes))
            self.assertIsNone(archive.testzip())
            for name in archive.namelist():
                self.assertEqual(archive.read(name), (build.HERE / 'fabrication' / name).read_bytes())
            plated = archive.read(build.NAME + '-PTH.drl').decode()
            nonplated = archive.read(build.NAME + '-NPTH.drl').decode()
            self.assertEqual(len(re.findall(r'G85', plated)), 3)
            self.assertNotIn('G85', nonplated)
            self.assertRegex(plated, r'T\d+C0\.600')

    def test_old_narrow_slot_is_rejected(self):
        board = routed_board()
        jack_pads(board)[0].SetDrillSize(build.xy(1.4, .4))
        with self.assertRaisesRegex(AssertionError, 'slot below OSH Park minimum'):
            build.check_oshpark_drills(board)

    def test_insufficient_annular_ring_is_rejected(self):
        board = routed_board()
        pad = jack_pads(board)[0]
        pad.SetSize(pad.GetDrillSize())
        with self.assertRaisesRegex(AssertionError, 'annular ring below OSH Park minimum'):
            build.check_oshpark_drills(board)

    def test_nano_and_cable_corridors(self):
        self.assertAlmostEqual(build.NANO_BOUNDS[2] - build.NANO_BOUNDS[0], 54.04)
        self.assertAlmostEqual(build.NANO_BOUNDS[3] - build.NANO_BOUNDS[1], 22.55)
        self.assertEqual(build.USB_CLEARANCE[0], 0)
        self.assertEqual(build.HDMI_CLEARANCE[2], 100)
        self.assertFalse(build.overlaps(build.NANO_BOUNDS, build.USB_CLEARANCE))
        self.assertFalse(build.overlaps(build.NANO_BOUNDS, build.HDMI_CLEARANCE))
        self.assertTrue(build.overlaps(build.USB_CLEARANCE, (1, 25, 10, 35)))
        board = routed_board()
        for fp in board.GetFootprints():
            if fp.GetReference() in ('J5', 'J6'):
                continue
            box = build.bounds(fp)
            for keepout in (build.NANO_BOUNDS, build.USB_CLEARANCE, build.HDMI_CLEARANCE):
                self.assertFalse(build.overlaps(box, keepout), fp.GetReference())

    def test_jack_faces_rear(self):
        self.assertEqual(build.AUDIO_PARTS['J3'][2:5], (50, 4.5, 180))


if __name__ == '__main__':
    unittest.main()

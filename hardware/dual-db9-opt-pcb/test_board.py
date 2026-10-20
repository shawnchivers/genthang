"""Mutation tests prove the independent board audit catches wiring/fit errors."""
import shutil
import tempfile
import unittest
from pathlib import Path

import pcbnew as p
import build_board as builder


class BoardAuditTests(unittest.TestCase):
    def setUp(self):
        self.real = builder.HERE
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for name in [builder.NAME + '.kicad_pcb', 'connectivity.json']:
            shutil.copyfile(self.real / name, self.root / name)
        (self.root / 'reference').mkdir()
        shutil.copyfile(self.real / 'reference/built-pinout.cst', self.root / 'reference/built-pinout.cst')
        self.board = p.LoadBoard(str(self.root / (builder.NAME + '.kicad_pcb')))

    def tearDown(self):
        builder.HERE = self.real
        self.temp.cleanup()

    def fp(self, ref):
        return next(f for f in self.board.GetFootprints() if f.GetReference() == ref)

    def pad(self, ref, number):
        return next(v for v in self.fp(ref).Pads() if v.GetNumber() == number)

    def reject(self):
        p.SaveBoard(str(self.root / (builder.NAME + '.kicad_pcb')), self.board)
        builder.HERE = self.root
        with self.assertRaises(AssertionError):
            builder.check()

    def test_wire_map_comes_from_constraints(self):
        # Player 1 on J6, player 2 on J5, no LED/HDMI/BL616/SD/I2S-config pins.
        for (player, dbpin), (net, ref, contact) in builder.WIRES.items():
            self.assertEqual(ref, builder.POWER[player][dbpin][1] if dbpin in (5, 8)
                             else builder.PLAYER_HEADER[player])
        self.assertEqual(len(builder.WIRES), 18)

    def test_wrong_db9_net_rejected(self):
        self.pad('J1', '1').SetNetCode(self.pad('J1', '2').GetNetCode())
        self.reject()

    def test_cross_player_net_swap_rejected(self):
        a, b = self.pad('J1', '3'), self.pad('J2', '3')
        code = a.GetNetCode()
        a.SetNetCode(b.GetNetCode())
        b.SetNetCode(code)
        self.reject()

    def test_unused_5v_contact_connection_rejected(self):
        self.pad('J5', '1').SetNetCode(self.pad('J6', '20').GetNetCode())
        self.reject()

    def test_unused_led_pin_connection_rejected(self):
        # J6.15 is GPIO17 (LED-loaded); it must stay unconnected.
        self.pad('J6', '15').SetNetCode(self.pad('J6', '12').GetNetCode())
        self.reject()

    def test_wrong_socket_drill_rejected(self):
        next(iter(self.fp('J6').Pads())).SetDrillSize(builder.xy(1, 1))
        self.reject()

    def test_wrong_boardlock_drill_rejected(self):
        self.pad('J2', '0').SetDrillSize(builder.xy(3.2, 3.2))
        self.reject()

    def test_reversed_connector_rejected(self):
        self.fp('J2').SetOrientationDegrees(180)
        self.reject()

    def test_unapproved_connector_name_rejected(self):
        self.fp('J1').SetFPID(p.LIB_ID(builder.LIBNAME, 'ConnectorPro_033020130020_UNVERIFIED'))
        self.reject()

    def test_moved_connector_rejected(self):
        pos = self.fp('J1').GetPosition()
        self.fp('J1').SetPosition(p.VECTOR2I(pos.x + builder.mm(2), pos.y))
        self.reject()


if __name__ == '__main__':
    unittest.main(verbosity=2)

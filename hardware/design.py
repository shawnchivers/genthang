"""Reviewable connectivity and placement source. Units: mm, top view, USB up.

Shared by the board generators (O1, L1, split P1/P2, crescent M1): Nano socket tables, part numbers and the
Design connectivity container. These are engineering drafts, NOT released fabrication designs. See README.md.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT.parent
REVISION = "A1"

# Physical socket contacts: numbered from USB toward HDMI, on BOTH rows.
# These match J6 (left) and J5 (right) in Sipeed's v3921 schematic, sheet 2.
LEFT = [73, 74, 75, 85, 77, 15, 16, 27, 28, 25,
        26, 29, 30, 31, 17, 20, 19, 18, "3V3", "GND"]
RIGHT = ["5V", "GND", 76, 80, 42, 41, 56, 54, 51, 48,
         55, 49, 86, 79, "GND", "3V3", 72, 71, 53, 52]
SOCKET_PITCH = 2.54
SOCKET_SPACING = 20.32
HDMI_SIDEBAND = {25: "CEC via R51", 26: "HPD via R47/R46",
                 52: "DDC SDA via Q1B", 53: "DDC SCL via Q1A"}

# btn_n bit order of the GT_PAD=raw build, used by the crescent M1 handheld board.
BUTTONS = ["B", "A", "MODE", "START", "UP", "DOWN", "LEFT", "RIGHT",
           "C", "Y", "X", "Z"]
SOCKET_MPN = "Harwin M20-7822046"
DB9_MPN = "Kycon K22X-E9P-N"

R0805 = "Resistor_SMD:R_0805_2012Metric"
C0805 = "Capacitor_SMD:C_0805_2012Metric"
SOCKET = "GenThang:Harwin_M20-7822046_1x20"
DSUB = "GenThang:Kycon_K22X-E9P-N"


def gpio(pin):
    return f"GPIO{pin}"


def socket_contact(pin):
    for ref, row in [("J6", LEFT), ("J5", RIGHT)]:
        if pin in row:
            return f"{ref}.{row.index(pin) + 1}"
    raise ValueError(f"FPGA pin {pin} not on sockets")


class Design:
    def __init__(self, name, width, height, mapping, socket_x, socket_y):
        self.name, self.width, self.height = name, width, height
        self.mapping, self.components = mapping, []
        self.socket_x, self.socket_y = socket_x, socket_y
        self.notes = ["DRAFT - NOT FOR FABRICATION", "Matching genthang-hw constraints required"]
        for ref, row, x in [("J6", LEFT, socket_x),
                            ("J5", RIGHT, socket_x + SOCKET_SPACING)]:
            nets = {str(i): (gpio(p) if isinstance(p, int) and p in mapping.values()
                             else p if isinstance(p, str) else None)
                    for i, p in enumerate(row, 1)}
            labels = {str(i): f"FPGA_{p}" if isinstance(p, int) else p
                      for i, p in enumerate(row, 1)}
            self.add(ref, "Nano_socket_1x20", SOCKET, x, socket_y, nets,
                     mpn=SOCKET_MPN,
                     labels=labels)
        for i, (x, y) in enumerate([(5, 5), (width - 5, 5),
                                    (5, height - 5), (width - 5, height - 5)], 1):
            self.add(f"H{i}", "M2.5_clearance", "MountingHole:MountingHole_2.7mm_M2.5",
                     x, y, {}, mpn="M2.5 nonconductive standoff; enclosure TBD")

    def add(self, ref, value, footprint, x, y, nets, mpn="", rotation=0, labels=None):
        assert ref not in {c["ref"] for c in self.components}, ref
        self.components.append(dict(ref=ref, value=value, footprint=footprint,
                                    x=x, y=y, rotation=rotation, nets=nets,
                                    mpn=mpn, labels=labels or {}))

    def r(self, ref, value, x, y, a, b, rotation=0):
        self.add(ref, value, R0805, x, y, {"1": a, "2": b},
                 mpn=f"0805 {value} 1% >=0.125W", rotation=rotation)

    def c(self, ref, value, x, y, a, b="GND", rotation=0):
        self.add(ref, value, C0805, x, y, {"1": a, "2": b},
                 mpn=f"0805 {value} X7R >=10V", rotation=rotation)

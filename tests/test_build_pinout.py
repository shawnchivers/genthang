"""Validate build selection and the DB9 / raw pin contracts."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import shutil
import unittest

ROOT = Path(__file__).resolve().parents[1]


def select(pad=None, pinout=None):
    env = {k:v for k,v in os.environ.items() if k not in ('GT_PAD','GT_PINOUT','GT_SERIAL_UPLOAD','GT_PICTURE')}
    if pad is not None: env['GT_PAD'] = pad
    if pinout is not None: env['GT_PINOUT'] = pinout
    return subprocess.run(['tclsh'], cwd=ROOT, env=env, text=True, capture_output=True,
        input='if {[catch {source build_config.tcl} err]} {puts stderr $err; exit 1}\n'
              'puts "$pad|$pinout|$pad_cst|$output_base"\n')


class PinoutTests(unittest.TestCase):
    def test_defaults_and_existing_options(self):
        for pad in [None,'','db9','raw']:
            for pinout in [None,'','stock']:
                result=select(pad,pinout)
                self.assertEqual(result.returncode,0,result.stderr)
                p=pad or 'db9'
                self.assertEqual(result.stdout.strip(),
                                 f'{p}|stock|src/boards/nano20k_{p}.cst|genthang_nano20k_{p}')

    def test_dualshock_build_removed(self):
        self.assertNotEqual(select('ds').returncode,0)
        self.assertFalse((ROOT/'src/boards/nano20k_ds.cst').exists())
        self.assertFalse((ROOT/'src/iosys/dualshock_controller.v').exists())

    def test_deprecated_aliases_and_invalid_combinations(self):
        for alias in ('breadboard','breadboard-rev1'):
            for pad in ('db9',None):
                result=select(pad,alias)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(result.stdout.strip(),
                    'db9|stock|src/boards/nano20k_db9.cst|genthang_nano20k_db9')
                self.assertIn(f'GT_PINOUT={alias} is deprecated',result.stderr)
        for pad,pinout in [('raw','breadboard'),('raw','breadboard-rev1'),
                           ('db9','typo'),('invalid','stock')]:
            self.assertNotEqual(select(pad,pinout).returncode,0)

    def test_canonical_db9_pins(self):
        text=(ROOT/'src/boards/nano20k_db9.cst').read_text()
        pattern=r'IO_LOC\s+"([^"]+)"\s+([^;]+);'
        pins=dict(re.findall(pattern,text))
        expected={'db9_d[0]':73,'db9_d[1]':74,'db9_d[2]':77,'db9_d[3]':27,
                  'db9_d[4]':28,'db9_d[5]':30,'db9_th':29,
                  'db9b_d[0]':42,'db9b_d[1]':41,'db9b_d[2]':51,'db9b_d[3]':48,
                  'db9b_d[4]':49,'db9b_d[5]':71,'db9b_th':72}
        for signal,pin in expected.items():
            self.assertEqual(int(pins[signal]),pin)
        assigned=[int(v) for value in pins.values() for v in value.replace(',',' ').split()]
        self.assertEqual(len(assigned),len(set(assigned)))
        ports=dict(re.findall(r'IO_PORT\s+"([^"]+)"\s+([^;]+);',text))
        for bus in ['db9_d','db9b_d']:
            for i in range(6):
                self.assertIn('PULL_MODE=UP',ports[f'{bus}[{i}]'])

    def test_raw_handheld_pinout(self):
        pattern=r'IO_LOC\s+"([^"]+)"\s+([^;]+);'
        text=(ROOT/'src/boards/nano20k_raw.cst').read_text()
        raw={k:v.strip() for k,v in re.findall(pattern,text)}
        ports=dict(re.findall(r'IO_PORT\s+"([^"]+)"\s+([^;]+);',text))
        # B, A, Mode, Start, Up, Down, Left, Right, C, Y, X, Z
        self.assertEqual([int(raw[f'btn_n[{i}]']) for i in range(12)],
                         [49,41,86,76,27,28,25,26,71,48,42,72])
        for i in range(12):
            self.assertIn('PULL_MODE=UP',ports[f'btn_n[{i}]'])
        self.assertEqual({k:int(raw[k]) for k in ('audio_jack_l','audio_jack_r','hp_det',
                          'i2s_bclk','i2s_lrck','i2s_din','spk_en')},
                         {'audio_jack_l':31,'audio_jack_r':30,'hp_det':29,
                          'i2s_bclk':56,'i2s_lrck':55,'i2s_din':54,'spk_en':51})
        self.assertIn('PULL_MODE=UP',ports['hp_det'])
        used=[p for v in raw.values() for p in v.split(',')]
        self.assertEqual(len(used),len(set(used)))
        # header pins wired on the board to other parts: WS2812, EDID, LEDs 2-5
        self.assertFalse({'79','52','53','17','18','19','20'} & set(used))

    def test_full_build_script_uses_selected_profile(self):
        # Run the actual build.tcl with Gowin commands stubbed; real file/glob
        # operations occur in a disposable source tree, never the live checkout.
        for pad,pinout in [('db9','stock'),('raw','stock'),
                           ('db9','breadboard'),('db9','breadboard-rev1')]:
            with tempfile.TemporaryDirectory() as temp:
                root=Path(temp)
                shutil.copytree(ROOT/'src',root/'src')
                for name in ['build.tcl','build_config.tcl']:
                    shutil.copyfile(ROOT/name,root/name)
                script='''
proc set_device {args} {}
proc add_file {args} {
    if {[lindex $args 1] eq "cst"} {puts "CST=[lindex $args 2]"}
}
proc set_option {name value} {
    if {$name eq "-output_base_name"} {puts "OUTPUT=$value"}
    if {$name eq "-place_option"} {puts "PLACE=$value"}
    if {$name eq "-route_option"} {puts "ROUTE=$value"}
}
proc run {args} {puts "RUN=$args"}
if {[catch {source build.tcl} err]} {puts stderr $err; exit 1}
'''
                result=subprocess.run(['tclsh'],cwd=root,text=True,input=script,capture_output=True,
                                      env={**{k:v for k,v in os.environ.items() if k not in ('GT_SERIAL_UPLOAD','GT_PICTURE')},
                                           'GT_PAD':pad,'GT_PINOUT':pinout})
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn(f'CST=src/boards/nano20k_{pad}.cst',result.stdout)
                self.assertIn(f'OUTPUT=genthang_nano20k_{pad}',result.stdout)
                self.assertIn('PLACE=2',result.stdout)
                self.assertIn('ROUTE=1',result.stdout)
                self.assertIn('RUN=all',result.stdout)
                vh=(root/'src/pad_config.vh').read_text().split('\n')
                self.assertEqual(vh[0],f'`define GT_PAD_{pad.upper()}')
                self.assertNotIn('`define PICTURE_OPTS', vh)

    def test_picture_options_off_by_default(self):
        def picture(pad, value=None):
            env={k:v for k,v in os.environ.items() if k not in ('GT_PAD','GT_PINOUT','GT_PICTURE')}
            env['GT_PAD']=pad
            if value is not None: env['GT_PICTURE']=value
            return subprocess.run(['tclsh'],cwd=ROOT,env=env,text=True,capture_output=True,
                input='if {[catch {source build_config.tcl} err]} {puts stderr $err; exit 1}\n'
                      'puts $picture\n')
        for pad,value,want in [('raw',None,'0'),('db9',None,'0'),('raw','','0'),('db9','','0'),
                               ('raw','0','0'),('db9','1','1')]:
            result=picture(pad,value)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(result.stdout.strip(),want,(pad,value))
        self.assertNotEqual(picture('raw','yes').returncode,0)


if __name__=='__main__':
    unittest.main(verbosity=2)
"""Validate build selection and the consolidated non-DualShock pin contract."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import shutil
import unittest

ROOT = Path(__file__).resolve().parents[1]


def select(pad=None, pinout=None):
    env = {k:v for k,v in os.environ.items() if k not in ('GT_PAD','GT_PINOUT')}
    if pad is not None: env['GT_PAD'] = pad
    if pinout is not None: env['GT_PINOUT'] = pinout
    return subprocess.run(['tclsh'], cwd=ROOT, env=env, text=True, capture_output=True,
        input='if {[catch {source build_config.tcl} err]} {puts stderr $err; exit 1}\n'
              'puts "$pad|$pinout|$pad_cst|$output_base"\n')


class PinoutTests(unittest.TestCase):
    def test_defaults_and_existing_options(self):
        for pad in [None,'','ds','db9','raw']:
            for pinout in [None,'','stock']:
                result=select(pad,pinout)
                self.assertEqual(result.returncode,0,result.stderr)
                p=pad or 'db9'
                output='genthang_nano20k' if p == 'ds' else f'genthang_nano20k_{p}'
                self.assertEqual(result.stdout.strip(),
                                 f'{p}|stock|src/boards/nano20k_{p}.cst|{output}')
                if p == 'ds':
                    self.assertIn('GT_PAD=ds is deprecated',result.stderr)

    def test_deprecated_aliases_and_invalid_combinations(self):
        for alias in ('breadboard','breadboard-rev1'):
            for pad in ('db9',None):
                result=select(pad,alias)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(result.stdout.strip(),
                    'db9|stock|src/boards/nano20k_db9.cst|genthang_nano20k_db9')
                self.assertIn(f'GT_PINOUT={alias} is deprecated',result.stderr)
        for pad,pinout in [('ds','breadboard'),('raw','breadboard'),
                           ('ds','breadboard-rev1'),('raw','breadboard-rev1'),
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

    def test_raw_uses_canonical_db9_data_pins(self):
        pattern=r'IO_LOC\s+"([^"]+)"\s+([^;]+);'
        db9=dict(re.findall(pattern,(ROOT/'src/boards/nano20k_db9.cst').read_text()))
        raw=dict(re.findall(pattern,(ROOT/'src/boards/nano20k_raw.cst').read_text()))
        db9_data=[int(db9[f'{bus}[{i}]']) for bus in ('db9_d','db9b_d') for i in range(6)]
        raw_buttons=[int(raw[f'btn_n[{i}]']) for i in range(12)]
        self.assertEqual(raw_buttons,db9_data)

    def test_dualshock_pinout_is_distinct_and_unchanged(self):
        text=(ROOT/'src/boards/nano20k_ds.cst').read_text()
        pins=dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+([^;]+);',text))
        self.assertEqual({name:int(pins[name]) for name in
                          ('ds_clk','ds_cs','ds_mosi','ds_miso','ds2_clk','ds2_cs',
                           'ds2_mosi','ds2_miso')},
                         {'ds_clk':17,'ds_cs':18,'ds_mosi':20,'ds_miso':19,
                          'ds2_clk':52,'ds2_cs':72,'ds2_mosi':53,'ds2_miso':71})

    def test_full_build_script_uses_selected_profile(self):
        # Run the actual build.tcl with Gowin commands stubbed; real file/glob
        # operations occur in a disposable source tree, never the live checkout.
        for pad,pinout in [('ds','stock'),('db9','stock'),('raw','stock'),
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
                                      env={**os.environ,'GT_PAD':pad,'GT_PINOUT':pinout})
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn(f'CST=src/boards/nano20k_{pad}.cst',result.stdout)
                output='genthang_nano20k' if pad == 'ds' else f'genthang_nano20k_{pad}'
                self.assertIn(f'OUTPUT={output}',result.stdout)
                self.assertIn('PLACE=2',result.stdout)
                self.assertIn('ROUTE=1',result.stdout)
                self.assertIn('RUN=all',result.stdout)
                self.assertEqual((root/'src/pad_config.vh').read_text().strip(),f'`define GT_PAD_{pad.upper()}')


if __name__=='__main__':
    unittest.main(verbosity=2)
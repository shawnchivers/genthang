"""Validate selection in plain Tcl and the exact nine-wire breadboard contract."""
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
                p=pad or 'ds'
                self.assertEqual(result.stdout.strip(),f'{p}|stock|src/boards/nano20k_{p}.cst|genthang_nano20k')

    def test_opt_in_and_invalid_combinations(self):
        result=select('db9','breadboard')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout.strip(),
            'db9|breadboard|src/boards/nano20k_db9_breadboard.cst|genthang_nano20k_db9_breadboard')
        for pad,pinout in [('ds','breadboard'),('raw','breadboard'),(None,'breadboard'),
                           ('db9','typo'),('invalid','stock')]:
            self.assertNotEqual(select(pad,pinout).returncode,0)

    def test_exact_pins_and_other_peripherals_unchanged(self):
        old=(ROOT/'src/boards/nano20k_db9.cst').read_text()
        new=(ROOT/'src/boards/nano20k_db9_breadboard.cst').read_text()
        pattern=r'IO_LOC\s+"([^"]+)"\s+([^;]+);'
        before,after=dict(re.findall(pattern,old)),dict(re.findall(pattern,new))
        expected={'db9_d[0]':31,'db9_d[1]':41,'db9_d[2]':27,'db9_d[3]':28,
                  'db9_d[4]':29,'db9_d[5]':30,'db9_th':42,
                  'db9b_d[0]':17,'db9b_d[1]':18,'db9b_d[2]':19,'db9b_d[3]':20,
                  'db9b_d[4]':48,'db9b_d[5]':71,'db9b_th':72}
        for signal,pin in expected.items():
            self.assertEqual(int(after.pop(signal)),pin)
            before.pop(signal)
        self.assertEqual(before,after)
        assigned=[int(v) for text in dict(re.findall(pattern,new)).values()
                  for v in text.replace(',',' ').split()]
        self.assertEqual(len(assigned),len(set(assigned)))
        ports=r'IO_PORT\s+"([^"]+)"\s+([^;]+);'
        self.assertEqual(dict(re.findall(ports,old)),dict(re.findall(ports,new)))
        for bus in ['db9_d','db9b_d']:
            for i in range(6):
                self.assertIn('PULL_MODE=UP',dict(re.findall(ports,new))[f'{bus}[{i}]'])

    def test_full_build_script_uses_selected_profile(self):
        # Run the actual build.tcl with Gowin commands stubbed; real file/glob
        # operations occur in a disposable source tree, never the live checkout.
        for pad,pinout in [('ds','stock'),('db9','stock'),('raw','stock'),('db9','breadboard')]:
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
                suffix='_breadboard' if pinout=='breadboard' else ''
                self.assertIn(f'CST=src/boards/nano20k_{pad}{suffix}.cst',result.stdout)
                output='genthang_nano20k_db9_breadboard' if suffix else 'genthang_nano20k'
                self.assertIn(f'OUTPUT={output}',result.stdout)
                if pad != 'db9' or pinout == 'breadboard':
                    self.assertIn('PLACE=2',result.stdout)
                    self.assertIn('ROUTE=1',result.stdout)
                else:
                    self.assertNotIn('PLACE=',result.stdout)
                    self.assertNotIn('ROUTE=',result.stdout)
                self.assertIn('RUN=all',result.stdout)
                self.assertEqual((root/'src/pad_config.vh').read_text().strip(),f'`define GT_PAD_{pad.upper()}')


if __name__=='__main__':
    unittest.main(verbosity=2)
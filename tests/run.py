from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / '.tools' / 'python'))
from lupa.lua54 import LuaRuntime
root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path = '" + root.as_posix() + "/Scripts/?.lua;' .. package.path")
check = lua.eval('function(s,n) local f,e=load(s,n); return f~=nil,e end')
for p in (root / 'Scripts').glob('*.lua'):
    ok, err = check(p.read_text(encoding='utf-8-sig'), str(p))
    assert ok, err
print('All Lua modules parse under Lua 5.4')
lua.execute((root / 'tests' / 'spec.lua').read_text(encoding='utf-8'))
for suite in ('native_tab.lua', 'workstation.lua', 'auto_eat.lua', 'automation.lua', 'production_controls.lua'):
    native = LuaRuntime(unpack_returned_tuples=True)
    native.execute("package.path = '" + root.as_posix() + "/Scripts/?.lua;' .. package.path")
    native.execute((root / 'tests' / suite).read_text(encoding='utf-8'))

"""Exercise the shipped streaming tar parser, including allocation boundaries."""
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[1]
PARSER = ROOT/'profiles/k2p/payload/starts/core_stream_extract.lua'


@unittest.skipUnless(LuaRuntime, 'Lua 5.1 runtime unavailable')
class StreamCoreArchive(unittest.TestCase):
    def archive(self, name='CrashCore', size=1048576, kind=tarfile.REGTYPE, extra=False):
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode='w', format=tarfile.USTAR_FORMAT) as tar:
            info = tarfile.TarInfo(name)
            info.mode, info.size, info.type = 0o700, size, kind
            tar.addfile(info, io.BytesIO(b'X'*size) if kind == tarfile.REGTYPE else None)
            if extra:
                other = tarfile.TarInfo('other')
                tar.addfile(other)
        return out.getvalue()

    def parse(self, data, available=50000):
        lua = LuaRuntime(encoding=None)
        stream = io.BytesIO(data)
        lua.globals()._read = lambda n: stream.read(n) or None
        lua.globals()._memory = f'MemAvailable: {available} kB\n'.encode()
        lua.execute(b'''local original=io.open
io.stdin={read=function(self,n)return _read(n)end}
io.open=function(p,m)
 if p=='/proc/meminfo' then return {read=function()return _memory end} end
 return original(p,m)
end''')
        with tempfile.TemporaryDirectory() as tmp:
            output, receipt = Path(tmp)/'binary', Path(tmp)/'receipt'
            lua.globals().arg = lua.table_from([str(output).encode(), str(receipt).encode()])
            lua.execute(PARSER.read_bytes())
            return output.read_bytes(), receipt.read_text()

    def test_exact_binary_and_receipt(self):
        binary, receipt = self.parse(self.archive())
        self.assertEqual(binary, b'X'*1048576)
        self.assertEqual(receipt, 'binary_size=1048576\n')

    def test_reserve_boundary(self):
        self.parse(self.archive(), available=24576+1024)
        with self.assertRaisesRegex(Exception, 'core_memory_insufficient'):
            self.parse(self.archive(), available=24576+1023)

    def test_bad_checksum_truncation_and_end_markers(self):
        data = self.archive()
        for bad in [b'Z'+data[1:], data[:100], data[:512+100], data[:512+1048576],
                    data[:512+1048576]+bytes(512), data+bytes(65536)]:
            with self.subTest(length=len(bad)), self.assertRaises(Exception):
                self.parse(bad)

    def test_paths_links_multiple_members_and_size_bounds(self):
        for data in [self.archive('../CrashCore'), self.archive('other'),
                     self.archive(kind=tarfile.SYMTYPE), self.archive(extra=True),
                     self.archive(size=999999)]:
            with self.assertRaises(Exception):
                self.parse(data)


if __name__ == '__main__':
    unittest.main()

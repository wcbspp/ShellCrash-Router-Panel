"""HTTP framing/auth contracts for the existing-nixio low-memory transport."""
import base64
from pathlib import Path
import unittest
try:
    from lupa.lua51 import LuaRuntime, LuaError
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipIf(LuaRuntime is None, 'Optional Lua 5.1 test runtime unavailable')
class CoreHTTP(unittest.TestCase):
    def exercise(self, response, auth='user = "user:password"\n',
                 url='http://192.168.5.22:83/dav/objects/core-abc.tar.gz'):
        lua = LuaRuntime()
        lua.globals().response = response
        lua.globals().auth_record = auth
        lua.globals().encode64 = lambda s: base64.b64encode(s.encode()).decode()
        lua.execute('''
request='';closed=false;created=false
socket={setopt=function()return true end,connect=function()return true end,
write=function(_,s)request=request..s;return #s end,
read=function(_,count)local s=response:sub(1,count);response=response:sub(count+1);return s end,
setblocking=function()return true end,close=function()closed=true end}
n={socket=function()created=true;return socket end,bin={b64encode=encode64}}
io.open=function()return {read=function()return auth_record end,close=function()end}end
''')
        function = lua.execute((ROOT/'profiles/k2p/payload/starts/core_http.lua').read_text())
        return lua, lambda: function(lua.globals().n, url, '/private/auth', 123)

    def test_exact_length_and_auth_leave_body_unread(self):
        lua, run = self.exercise('HTTP/1.1 200 OK\r\nContent-Length: 123\r\n\r\nbody')
        self.assertIsNotNone(run())
        self.assertEqual(lua.globals().response, 'body')
        self.assertIn('Authorization: Basic dXNlcjpwYXNzd29yZA==\r\n', lua.globals().request)
        self.assertIn('Connection: close\r\n', lua.globals().request)
        self.assertFalse(lua.globals().closed)

    def test_generator_quote_and_backslash_escapes(self):
        lua, run = self.exercise('HTTP/1.0 200 OK\r\nContent-Length: 123\r\n\r\n',
                                 'user = "u:p\\\\a\\"b"\n')
        run()
        encoded = base64.b64encode(b'u:p\\a"b').decode()
        self.assertIn('Basic '+encoded, lua.globals().request)

    def test_redirect_length_transfer_encoding_and_framing_fail_closed(self):
        responses = [
            'HTTP/1.1 302 Found\r\nLocation: http://other.invalid/\r\nContent-Length: 123\r\n\r\n',
            'HTTP/1.1 200 OK\r\nContent-Length: 124\r\n\r\n',
            'HTTP/1.1 200 OK\r\nContent-Length: 123\r\nContent-Length: 123\r\n\r\n',
            'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 123\r\n\r\n',
            'HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: 123\r\n\r\n',
            'HTTP/1.1 200 OK\r\nFolded invalid header\r\n\r\n',
            'HTTP/1.1 200 OK\r\nX-Large: '+'a'*8192,
            'HTTP/1.1 200 OK\r\nContent-Length: 123\r\n',
        ]
        for response in responses:
            with self.subTest(response=response[:60]):
                lua, run = self.exercise(response)
                with self.assertRaises(LuaError):
                    run()
                self.assertTrue(lua.globals().closed)

    def test_hostname_and_https_leave_existing_curl_path(self):
        for url in ('https://192.168.5.22/dav/a', 'http://repo.invalid/dav/a',
                    'http://.192.168.5.22/dav/a', 'http://999.168.5.22/dav/a'):
            lua, run = self.exercise('', url=url)
            self.assertIsNone(run())
            self.assertFalse(lua.globals().created)

    def test_malformed_auth_never_opens_socket(self):
        for auth in ('user = "u:p"\nurl = "http://other.invalid"',
                     'user = "u:p\\n"', 'user = "missing-colon"', 'x'*8193):
            lua, run = self.exercise('', auth=auth)
            with self.assertRaises(LuaError):
                run()
            self.assertFalse(lua.globals().created)

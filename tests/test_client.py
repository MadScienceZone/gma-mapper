"""Unit tests for gma_mapper.net.client.ProtocolSession."""

import base64
import unittest
from typing import Any

from gma_mapper.net.client import ProtocolSession


class TestProtocolSession(unittest.TestCase):
    def test_login_handshake_and_command_queueing(self) -> None:
        sent_lines: list[str] = []
        dispatched: list[tuple[str, dict[str, Any]]] = []
        login_ok = False

        def on_login() -> None:
            nonlocal login_ok
            login_ok = True

        session = ProtocolSession(
            send_line_cb=sent_lines.append,
            dispatch_cb=lambda c, p: dispatched.append((c, p)),
            login_success_cb=on_login,
        )
        session.reset_for_connection("localhost", 2323, "alice", "hunter2")

        # Queue a command while login is still pending: should be held back
        session.mark(100.0, 200.0)
        self.assertEqual(sent_lines, [])

        # Server greeting
        session.receive_line("PROTOCOL 428")
        self.assertEqual(session.protocol, 428)

        challenge_b64 = base64.b64encode(b"\x02\x00abcdef").decode("ascii")
        session.receive_line(
            f'OK {{"Protocol":428,"Challenge":"{challenge_b64}","Iterations":2,"ServerVersion":"4.42"}}'
        )
        # AUTH should have been sent immediately even while pending_login is True
        self.assertEqual(len(sent_lines), 1)
        self.assertTrue(sent_lines[0].startswith("AUTH "))

        session.receive_line('GRANTED {"User":"alice"}')
        session.receive_line('WORLD {"Calendar":"golarion"}')
        self.assertEqual(len(dispatched), 1)
        self.assertEqual(dispatched[0][0], "WORLD")

        # READY completes login, sends ECHO watch_operation, and flushes held MARK
        session.receive_line("READY")
        self.assertTrue(login_ok)
        self.assertTrue(session.is_ready())
        self.assertTrue(any(l.startswith("ECHO ") for l in sent_lines))
        self.assertTrue(any(l.startswith("MARK ") for l in sent_lines))

        # Incoming command after READY
        session.receive_line('MARK {"X":50.0,"Y":75.0}')
        self.assertEqual(dispatched[-1][0], "MARK")
        self.assertEqual(dispatched[-1][1]["X"], 50.0)

    def test_newline_sanitization_and_redirect_limits(self) -> None:
        sent_lines: list[str] = []
        redirects: list[tuple[str, int, str]] = []
        session = ProtocolSession(
            send_line_cb=sent_lines.append,
            redirect_cb=lambda h, p, r: redirects.append((h, p, r)),
        )
        session.reset_for_connection("localhost", 2323)
        session.receive_line("PROTOCOL 428")
        session.receive_line("READY")
        sent_lines.clear()

        # Embedded CR/LF in comment cannot inject another command line
        session.comment("hello\nCLR {\"ObjID\":\"*\"}\r\nworld")
        self.assertEqual(len(sent_lines), 1)
        self.assertNotIn("\n", sent_lines[0])
        self.assertNotIn("\r", sent_lines[0])
        self.assertTrue(sent_lines[0].startswith("// hello "))

        # Test redirect validation and loop limit
        session.reset_for_connection("localhost", 2323)
        session.receive_line("PROTOCOL 428")
        with self.assertRaises(ValueError):
            session.receive_line('REDIRECT {"Host":"","Port":2323}')
        with self.assertRaises(ValueError):
            session.receive_line('REDIRECT {"Host":"example.com","Port":70000}')

        for i in range(5):
            if i > 0:
                session.receive_line("PROTOCOL 428")
            session.receive_line(f'REDIRECT {{"Host":"host{i}.example.com","Port":2323,"Reason":"hop"}}')
        self.assertEqual(len(redirects), 5)
        session.receive_line("PROTOCOL 428")
        with self.assertRaises(RuntimeError):
            session.receive_line('REDIRECT {"Host":"host6.example.com","Port":2323,"Reason":"loop"}')

        # Test MARCO during login and mid-session DENIED / REDIRECT after READY
        sent_lines.clear()
        redirects.clear()
        session.reset_for_connection("localhost", 2323)
        session.receive_line("PROTOCOL 428")
        session.receive_line("MARCO")
        self.assertEqual(sent_lines, ["POLO"])
        session.receive_line("READY")
        sent_lines.clear()
        session.filter_audio("^test.*", keep_matching=True)
        session.filter_images("^img.*", keep_matching=False)
        session.update_clock(3600.0, 60.0, True)
        self.assertIn('AA/ {"Filter":"^test.*","KeepMatching":true}', sent_lines)
        self.assertIn('AI/ {"Filter":"^img.*"}', sent_lines)
        self.assertIn('CS {"Absolute":3600,"Relative":60,"Running":true}', sent_lines)

        with self.assertRaises(PermissionError):
            session.receive_line('DENIED {"Reason":"Kicked by GM"}')

        session.receive_line('REDIRECT {"Host":"backup.example.com","Port":2325,"Reason":"failover"}')
        self.assertEqual(redirects[-1], ("backup.example.com", 2325, "failover"))
        self.assertTrue(session.pending_login)


if __name__ == "__main__":
    unittest.main()


"""Unit tests for gma_mapper.net.protocol (ported from bin/gmaproto_test.tcl)."""

import base64
import struct
import unittest

from gma_mapper.net.protocol import (
    BatchCollector,
    GMATypeToObjType,
    GMATypeToProtocolCommand,
    MESSAGE_PAYLOAD,
    ObjTypeToGMAType,
    _construct,
    _encode_payload,
    _parse_data_packet,
    _protocol_encode,
    auth_response,
    encode_with_batching,
    from_enum,
    normalize_dict,
    to_enum,
)


class TestProtocol(unittest.TestCase):
    def test_construct_echo(self) -> None:
        actual = _construct({"foo": "bar"}, MESSAGE_PAYLOAD["ECHO"])
        self.assertEqual(
            actual,
            {"foo": "bar", "s": "", "i": 0, "b": False, "o": {}, "ReceivedTime": "", "SentTime": ""},
        )

    def test_parse_data_packet_suite(self) -> None:
        self.assertEqual(_parse_data_packet("PROTOCOL 42"), ("PROTOCOL", "42"))
        self.assertEqual(
            _parse_data_packet("//this is a comment"),
            ("//", "//this is a comment"),
        )
        self.assertEqual(
            _parse_data_packet('ECHO {"foo":"bar"}'),
            ("ECHO", {"foo": "bar", "s": "", "i": 0, "b": False, "o": {}, "ReceivedTime": "", "SentTime": ""}),
        )
        self.assertEqual(
            _parse_data_packet('DD {"For":"spam","Presets":null}'),
            ("DD", {"Global": False, "For": "spam", "Presets": []}),
        )
        self.assertEqual(
            _parse_data_packet('DD {"For":"spam","Presets":[]}'),
            ("DD", {"Global": False, "For": "spam", "Presets": []}),
        )
        self.assertEqual(
            _parse_data_packet(
                'DD {"For":"spam","Presets":[{"Name":"p1"},{"Name":"p2","Description":"d2"}]}'
            ),
            (
                "DD",
                {
                    "Global": False,
                    "For": "spam",
                    "Presets": [
                        {"Name": "p1", "Description": "", "DieRollSpec": ""},
                        {"Name": "p2", "Description": "d2", "DieRollSpec": ""},
                    ],
                },
            ),
        )

        cmd, ps = _parse_data_packet("PS {}")
        self.assertEqual(cmd, "PS")
        self.assertEqual(ps["ID"], "")
        self.assertEqual(ps["Health"], {})
        self.assertEqual(ps["Gx"], 0.0)
        self.assertEqual(ps["Skin"], 0)
        self.assertEqual(ps["SkinSize"], [])
        self.assertFalse(ps["PolyGM"])
        self.assertEqual(ps["AoE"], {})
        self.assertEqual(ps["CustomReach"], {})
        self.assertEqual(ps["Targets"], [])
        self.assertEqual(ps["TargetedModifiers"], {})

        cmd, ps2 = _parse_data_packet('PS {"Health":null,"AoE":{"Radius":1.23},"CustomReach":null}')
        self.assertEqual(cmd, "PS")
        self.assertEqual(ps2["Health"], {})
        self.assertEqual(ps2["AoE"], {"Radius": 1.23, "Color": ""})
        self.assertEqual(ps2["CustomReach"], {})

        self.assertEqual(
            _parse_data_packet('OA {"ObjID":"@foo","NewAttrs":{"Health":null}}'),
            ("OA", {"ObjID": "@foo", "NewAttrs": {"Health": ""}}),
        )
        self.assertEqual(
            _parse_data_packet('OA {"ObjID":"@foo","NewAttrs":null}'),
            ("OA", {"ObjID": "@foo", "NewAttrs": {}}),
        )
        self.assertEqual(
            _parse_data_packet('OA+ {"ObjID":"123456xyz","AttrName":"myattr","Values":null}'),
            ("OA+", {"ObjID": "123456xyz", "AttrName": "myattr", "Values": []}),
        )
        self.assertEqual(
            _parse_data_packet('OA+ {"ObjID":"123456xyz","AttrName":"myattr","Values":["a","b"]}'),
            ("OA+", {"ObjID": "123456xyz", "AttrName": "myattr", "Values": ["a", "b"]}),
        )

    def test_enums_and_type_conversions(self) -> None:
        self.assertEqual(to_enum("Dash", "-."), 4)
        self.assertEqual(from_enum("Dash", 4), "-.")
        self.assertEqual(to_enum("Arrow", "both"), 3)
        self.assertEqual(from_enum("Arrow", 3), "both")
        self.assertEqual(ObjTypeToGMAType("rect"), "RECT")
        self.assertEqual(ObjTypeToGMAType("rect", protocol=True), "LS-RECT")
        self.assertEqual(GMATypeToObjType("LS-SAOE"), "aoe")
        self.assertEqual(GMATypeToProtocolCommand("CREATURE"), "PS")

    def test_encode_and_batching(self) -> None:
        d = {
            "ID": "rect1",
            "X": 100.0,
            "Y": 200.0,
            "Points": [{"X": 100.0, "Y": 200.0}, {"X": 300.0, "Y": 400.0}],
            "Z": 5,
            "Line": "#ffffff",
            "Width": 2,
            "Hidden": False,
        }
        packets = encode_with_batching("LS-RECT", d, max_len=60, frag_size=30)
        self.assertGreater(len(packets), 1)
        collector = BatchCollector()
        final_res = None
        for pkt in packets:
            cmd, params = _parse_data_packet(pkt)
            self.assertEqual(cmd, "BATCH")
            res = collector.process_batch(params)
            if res is not None:
                final_res = res
        self.assertIsNotNone(final_res)
        assert final_res is not None
        self.assertEqual(final_res[0], "LS-RECT")
        self.assertEqual(final_res[1]["ID"], "rect1")
        self.assertEqual(len(final_res[1]["Points"]), 2)

    def test_auth_response(self) -> None:
        challenge = struct.pack(">H", 3) + b"123456"
        resp = auth_response(challenge, "secret", passes=0)
        self.assertEqual(len(resp), 32)
        resp_explicit = auth_response(challenge, "secret", passes=3)
        self.assertEqual(resp, resp_explicit)
        with self.assertRaises(ValueError):
            auth_response(challenge, "secret", passes=2_000_000)

        # Verify AA/, AI/, and CS int64 encoding
        self.assertEqual(
            _protocol_encode("AA/", {"Filter": "^goblin.*", "KeepMatching": True}),
            'AA/ {"Filter":"^goblin.*","KeepMatching":true}',
        )
        self.assertEqual(
            _protocol_encode("AI/", {"Filter": "^token.*", "KeepMatching": False}),
            'AI/ {"Filter":"^token.*"}',
        )
        self.assertEqual(
            _protocol_encode("CS", {"Absolute": 120, "Relative": 60, "Running": True}),
            'CS {"Absolute":120,"Relative":60,"Running":true}',
        )

    def test_health_attribute_encoding_and_multibyte_batching(self) -> None:
        from gma_mapper.net.protocol import _attribute_encode

        encoded_health = _attribute_encode(
            "Health",
            {
                "MaxHP": 50,
                "LethalDamage": 10,
                "TmpHP": 15,
                "TmpDamage": 5,
                "AC": 21,
                "FlatFootedAC": 18,
                "TouchAC": 13,
                "CMD": 24,
                "IsFlatFooted": True,
            },
        )
        self.assertEqual(encoded_health["TmpHP"], 15)
        self.assertEqual(encoded_health["TmpDamage"], 5)
        self.assertEqual(encoded_health["AC"], 21)
        self.assertEqual(encoded_health["FlatFootedAC"], 18)
        self.assertEqual(encoded_health["TouchAC"], 13)
        self.assertEqual(encoded_health["CMD"], 24)
        self.assertTrue(encoded_health["IsFlatFooted"])

        # Multi-byte UTF-8 characters split across very small batch fragments
        d = {"ID": "t1", "Text": "🔥🐉⚔️🧙‍♂️" * 10, "X": 10.0, "Y": 20.0}
        packets = encode_with_batching("LS-TEXT", d, max_len=20, frag_size=7)
        self.assertGreater(len(packets), 3)
        collector = BatchCollector()
        final_res = None
        for pkt in packets:
            cmd, params = _parse_data_packet(pkt)
            self.assertEqual(cmd, "BATCH")
            res = collector.process_batch(params)
            if res is not None:
                final_res = res
        self.assertIsNotNone(final_res)
        assert final_res is not None
        self.assertEqual(final_res[0], "LS-TEXT")
        self.assertEqual(final_res[1]["Text"], d["Text"])

        # Reject non-finite floats in _construct
        with self.assertRaises(ValueError):
            _construct({"X": float("nan"), "Y": 0.0}, MESSAGE_PAYLOAD["MARK"])
        with self.assertRaises(ValueError):
            _construct({"X": float("inf"), "Y": 0.0}, MESSAGE_PAYLOAD["MARK"])


if __name__ == "__main__":
    unittest.main()


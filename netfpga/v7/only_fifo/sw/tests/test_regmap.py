import os
import sys
import unittest


THIS_DIR = os.path.dirname(os.path.abspath(__file__))
SW_DIR = os.path.dirname(THIS_DIR)
ONLY_FIFO_DIR = os.path.dirname(SW_DIR)
if SW_DIR not in sys.path:
    sys.path.insert(0, SW_DIR)


from packetlib.regmap import (  # noqa: E402
    default_reg_defines_path,
    load_only_fifo_regmap,
    load_user_pre_debug_regmap,
    load_user_top_regmap,
    resolve_register,
)


class RegMapTest(unittest.TestCase):
    def test_default_regmap_path_resolves_generated_header(self):
        path = default_reg_defines_path()
        self.assertTrue(os.path.isfile(path))
        self.assertEqual(os.path.abspath(path), os.path.abspath(os.path.join(ONLY_FIFO_DIR, "reg_defines_onlyfifo.h")))

    def test_user_top_debug_addresses_match_generated_header(self):
        regmap = load_user_top_regmap()
        self.assertEqual(regmap["base_addr"], 0x2000100)
        self.assertEqual(resolve_register("debug_ctrl", regmap)["addr"], 0x2000100)
        self.assertEqual(resolve_register("hw_last_action", regmap)["addr"], 0x2000104)
        self.assertEqual(resolve_register("hw_offload_match_count", regmap)["addr"], 0x2000108)
        self.assertEqual(resolve_register("hw_last_rewrite_word_lo", regmap)["addr"], 0x200012c)

    def test_user_pre_debug_addresses_match_generated_header(self):
        regmap = load_user_pre_debug_regmap()
        self.assertEqual(regmap["base_addr"], 0x2000140)
        self.assertEqual(resolve_register("debug_ctrl", regmap)["addr"], 0x2000140)
        self.assertEqual(resolve_register("hw_status", regmap)["addr"], 0x2000144)
        self.assertEqual(resolve_register("hw_last_word5_lo", regmap)["addr"], 0x200017c)

    def test_combined_regmap_supports_group_qualified_names(self):
        regmap = load_only_fifo_regmap()
        self.assertEqual(resolve_register("post.debug_ctrl", regmap)["addr"], 0x2000100)
        self.assertEqual(resolve_register("pre.debug_ctrl", regmap)["addr"], 0x2000140)
        self.assertEqual(resolve_register("hw_last_action", regmap)["addr"], 0x2000104)

    def test_unknown_address_still_resolves_to_numeric_entry(self):
        regmap = load_only_fifo_regmap()
        entry = resolve_register("0x20001fc", regmap)
        self.assertEqual(entry["symbol"], None)
        self.assertEqual(entry["access"], "unknown")
        self.assertEqual(entry["addr"], 0x20001fc)


if __name__ == "__main__":
    unittest.main()

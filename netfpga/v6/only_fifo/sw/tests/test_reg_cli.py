import io
import os
import stat
import sys
import tempfile
import unittest


THIS_DIR = os.path.dirname(os.path.abspath(__file__))
SW_DIR = os.path.dirname(THIS_DIR)
if SW_DIR not in sys.path:
    sys.path.insert(0, SW_DIR)


from packetlib.reg_cli import main_pktctl  # noqa: E402


HEADER_TEXT = """#define USER_TOP_BASE_ADDR       0x2000100
#define USER_PRE_DEBUG_BASE_ADDR 0x2000140
#define USER_TOP_DEBUG_CTRL_REG                0x2000100
#define USER_TOP_HW_LAST_ACTION_REG            0x2000104
#define USER_TOP_HW_OFFLOAD_MATCH_COUNT_REG    0x2000108
#define USER_TOP_HW_REWRITE_FIRE_COUNT_REG     0x200010c
#define USER_TOP_HW_LAST_UDP_DST_PORT_REG      0x2000110
#define USER_TOP_HW_LAST_PAYLOAD_MAGIC_REG     0x2000114
#define USER_TOP_HW_LAST_HEADER_WORD5_HI_REG   0x2000118
#define USER_TOP_HW_LAST_HEADER_WORD5_LO_REG   0x200011c
#define USER_TOP_HW_LAST_HEADER_WORD6_HI_REG   0x2000120
#define USER_TOP_HW_LAST_HEADER_WORD6_LO_REG   0x2000124
#define USER_TOP_HW_LAST_REWRITE_WORD_HI_REG   0x2000128
#define USER_TOP_HW_LAST_REWRITE_WORD_LO_REG   0x200012c
#define USER_PRE_DEBUG_DEBUG_CTRL_REG          0x2000140
#define USER_PRE_DEBUG_HW_STATUS_REG           0x2000144
#define USER_PRE_DEBUG_HW_LAST_CTRL_PACK_0_REG 0x2000148
#define USER_PRE_DEBUG_HW_LAST_CTRL_PACK_1_REG 0x200014c
#define USER_PRE_DEBUG_HW_LAST_WORD0_HI_REG    0x2000150
#define USER_PRE_DEBUG_HW_LAST_WORD0_LO_REG    0x2000154
#define USER_PRE_DEBUG_HW_LAST_WORD1_HI_REG    0x2000158
#define USER_PRE_DEBUG_HW_LAST_WORD1_LO_REG    0x200015c
#define USER_PRE_DEBUG_HW_LAST_WORD2_HI_REG    0x2000160
#define USER_PRE_DEBUG_HW_LAST_WORD2_LO_REG    0x2000164
#define USER_PRE_DEBUG_HW_LAST_WORD3_HI_REG    0x2000168
#define USER_PRE_DEBUG_HW_LAST_WORD3_LO_REG    0x200016c
#define USER_PRE_DEBUG_HW_LAST_WORD4_HI_REG    0x2000170
#define USER_PRE_DEBUG_HW_LAST_WORD4_LO_REG    0x2000174
#define USER_PRE_DEBUG_HW_LAST_WORD5_HI_REG    0x2000178
#define USER_PRE_DEBUG_HW_LAST_WORD5_LO_REG    0x200017c
"""


REGREAD_SCRIPT = """#!/bin/sh
case "$1" in
  0x02000100) value=0x00000000 ;;
  0x02000104) value=0x00000002 ;;
  0x02000108) value=0x00000003 ;;
  0x0200010c) value=0x00000002 ;;
  0x02000110) value=0x000088b5 ;;
  0x02000114) value=0x0000a11e ;;
  0x02000118) value=0xc0a80102 ;;
  0x0200011c) value=0x400188b5 ;;
  0x02000120) value=0x00200000 ;;
  0x02000124) value=0xa11e1234 ;;
  0x02000128) value=0x00200000 ;;
  0x0200012c) value=0xf11e1234 ;;
  0x02000140) value=0x00000000 ;;
  0x02000144) value=0x00010605 ;;
  0x02000148) value=0x000000ff ;;
  0x0200014c) value=0x00008000 ;;
  0x02000150) value=0x11112222 ;;
  0x02000154) value=0x33334444 ;;
  0x02000158) value=0x55556666 ;;
  0x0200015c) value=0x77778888 ;;
  0x02000160) value=0x9999aaaa ;;
  0x02000164) value=0xbbbbcccc ;;
  0x02000168) value=0xddddeeee ;;
  0x0200016c) value=0xffff0000 ;;
  0x02000170) value=0x12345678 ;;
  0x02000174) value=0x9abcdef0 ;;
  0x02000178) value=0x0fedcba9 ;;
  0x0200017c) value=0x87654321 ;;
  *) value=0x00000000 ;;
esac
echo "Found net device: nf2c0"
echo "Reg $1 (0):   $value (0)"
"""


REGWRITE_SCRIPT = """#!/bin/sh
echo "$1 $2" >> "$REGWRITE_LOG"
"""


class PktCtlCliTest(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="only_fifo_pktctl_")
        self.reg_defines = os.path.join(self.tmpdir, "reg_defines_onlyfifo.h")
        self.regread_bin = os.path.join(self.tmpdir, "fake_regread.sh")
        self.regwrite_bin = os.path.join(self.tmpdir, "fake_regwrite.sh")
        self.regwrite_log = os.path.join(self.tmpdir, "regwrite.log")

        self._write_file(self.reg_defines, HEADER_TEXT)
        self._write_file(self.regread_bin, REGREAD_SCRIPT)
        self._write_file(self.regwrite_bin, REGWRITE_SCRIPT)
        os.chmod(self.regread_bin, stat.S_IRWXU)
        os.chmod(self.regwrite_bin, stat.S_IRWXU)
        os.environ["REGWRITE_LOG"] = self.regwrite_log

    def tearDown(self):
        for root, dirs, files in os.walk(self.tmpdir, topdown=False):
            for name in files:
                os.unlink(os.path.join(root, name))
            for name in dirs:
                os.rmdir(os.path.join(root, name))
        os.rmdir(self.tmpdir)
        if "REGWRITE_LOG" in os.environ:
            del os.environ["REGWRITE_LOG"]

    def _write_file(self, path, text):
        handle = open(path, "w")
        try:
            handle.write(text)
        finally:
            handle.close()

    def _run_pktctl(self, argv):
        buffer = io.StringIO()
        old_stdout = sys.stdout
        sys.stdout = buffer
        try:
            rc = main_pktctl(argv)
        finally:
            sys.stdout = old_stdout
        return rc, buffer.getvalue()

    def _base_args(self):
        return [
            "--reg-defines", self.reg_defines,
            "--regread-bin", self.regread_bin,
            "--regwrite-bin", self.regwrite_bin,
        ]

    def test_regs_list_shows_pre_and_post_symbols(self):
        rc, output = self._run_pktctl(["regs", "list"] + self._base_args())
        self.assertEqual(rc, 0)
        self.assertIn("USER_TOP_DEBUG_CTRL_REG", output)
        self.assertIn("USER_PRE_DEBUG_HW_LAST_WORD5_LO_REG", output)

    def test_stats_clear_writes_both_control_registers(self):
        rc, output = self._run_pktctl(["stats", "clear"] + self._base_args())
        self.assertEqual(rc, 0)
        self.assertIn("cleared only_fifo debug stats", output)

        handle = open(self.regwrite_log, "r")
        try:
            lines = [line.strip() for line in handle.readlines()]
        finally:
            handle.close()
        self.assertEqual(
            lines,
            [
                "0x02000100 0x00000001",
                "0x02000100 0x00000000",
                "0x02000140 0x00000001",
                "0x02000140 0x00000000",
            ],
        )

    def test_stats_snapshot_decodes_post_snapshot(self):
        rc, output = self._run_pktctl(["stats", "snapshot", "--dump-json"] + self._base_args())
        self.assertEqual(rc, 0)
        self.assertIn('"name": "offload"', output)
        self.assertIn('"offload_match_count": 3', output)
        self.assertIn('"rewrite_fire_count": 2', output)
        self.assertIn('"0x000088b5"', output)
        self.assertIn('"last_header_word6": "0x00200000a11e1234"', output)
        self.assertIn('"last_rewrite_word": "0x00200000f11e1234"', output)

    def test_pre_snapshot_decodes_pre_words_and_ctrls(self):
        rc, output = self._run_pktctl(["pre", "snapshot", "--dump-json"] + self._base_args())
        self.assertEqual(rc, 0)
        self.assertIn('"snapshot_valid": 1', output)
        self.assertIn('"capture_done": 1', output)
        self.assertIn('"last_word_count": 6', output)
        self.assertIn('"pkt_seen_count": 1', output)
        self.assertIn('"last_words"', output)
        self.assertIn('"0x1111222233334444"', output)
        self.assertIn('"0x0fedcba987654321"', output)

    def test_snapshot_all_groups_output(self):
        rc, output = self._run_pktctl(["snapshot", "all", "--dump-json"] + self._base_args())
        self.assertEqual(rc, 0)
        self.assertIn('"pre"', output)
        self.assertIn('"post"', output)
        self.assertIn('"last_action"', output)
        self.assertIn('"last_words"', output)


if __name__ == "__main__":
    unittest.main()

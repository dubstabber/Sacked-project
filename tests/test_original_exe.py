import unittest

from tools.original_exe import FADD, FMUL, IMAGE_BASE, pin_readers


CONSTANT_VA = IMAGE_BASE + 0x20


def _image() -> bytes:
    """fmul dword ptr [constant] at the image base and fadd dword ptr [constant] 16 bytes on."""
    data = bytearray(0x40)
    data[0x00:0x06] = FMUL + CONSTANT_VA.to_bytes(4, "little")
    data[0x10:0x16] = FADD + CONSTANT_VA.to_bytes(4, "little")
    return bytes(data)


class PinReadersTests(unittest.TestCase):
    def test_readers_that_are_what_they_are_said_to_be_pass(self):
        failures = []
        pin_readers(_image(), "k", CONSTANT_VA, [(IMAGE_BASE, FMUL), (IMAGE_BASE + 0x10, FADD)], failures)
        self.assertEqual(failures, [])

    def test_the_right_address_behind_the_wrong_opcode_fails(self):
        # An operand check alone would pass this: the dword is the address, the instruction is not
        # the one named.
        failures = []
        pin_readers(_image(), "k", CONSTANT_VA, [(IMAGE_BASE + 0x10, FMUL)], failures)
        self.assertEqual(failures, [f"0x{IMAGE_BASE + 0x10:X} is not d8 0d, the read of k"])

    def test_the_right_opcode_reading_another_address_fails(self):
        failures = []
        pin_readers(_image(), "k", CONSTANT_VA + 4, [(IMAGE_BASE, FMUL)], failures)
        self.assertEqual(failures, [f"the instruction at 0x{IMAGE_BASE:X} does not read k at 0x{CONSTANT_VA + 4:X}"])


if __name__ == "__main__":
    unittest.main()

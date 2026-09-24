import io
import sys
import unittest
from contextlib import redirect_stdout
from unittest import mock

from tools import run_checks
from tools.run_checks import FAILURE_LINE, run


def fake_step(stderr_text: str, exit_code: int = 0, stdout_text: str = "") -> list:
    """A command that writes like a headless Godot check: its report on stdout, errors on stderr."""
    code = (
        "import sys\n"
        f"sys.stdout.write({stdout_text!r}); sys.stdout.flush()\n"
        f"sys.stderr.write({stderr_text!r}); sys.stderr.flush()\n"
        f"sys.exit({exit_code})\n"
    )
    return [sys.executable, "-c", code]


def run_quietly(command: list, script_check: bool = True, verbose: bool = False) -> tuple:
    printed = io.StringIO()
    with redirect_stdout(printed):
        ok, _elapsed = run("fake", command, verbose, script_check)
    return ok, printed.getvalue()


class FailureLineTest(unittest.TestCase):
    """What counts as a GDScript failure in a check's log, whatever its exit code."""

    def test_script_errors_count(self):
        for line in [
            "SCRIPT ERROR: Cannot call method 'get_viewport' on a null value.",
            'SCRIPT ERROR: Parse Error: Identifier "undefined_identifier" not declared in the current scope.',
            "SCRIPT ERROR: Compile Error: Failed to compile depended scripts.",
            "SCRIPT ERROR: Assertion failed.",
        ]:
            self.assertTrue(FAILURE_LINE.search(line), line)

    def test_a_colour_coded_script_error_counts(self):
        # Under a terminal Godot wraps the prefix in ANSI colour codes.
        self.assertTrue(FAILURE_LINE.search("\x1b[1;35mSCRIPT ERROR:\x1b[0;95m Assertion failed.\x1b[0m"))

    def test_undispatched_signals_and_deferred_calls_count(self):
        # Godot reports these as engine errors with no SCRIPT ERROR line.
        for line in [
            "ERROR: Error calling from signal 'ping' to callable: 'SceneTree::_no_args': "
            "Method expected 0 argument(s), but called with 1.",
            "ERROR: Error calling deferred method: 'SceneTree::does_not_exist': Method not found.",
        ]:
            self.assertTrue(FAILURE_LINE.search(line), line)

    def test_engine_noise_does_not_count(self):
        for line in [
            "ERROR: 4 resources still in use at exit (run with --verbose for details).",
            "WARNING: 3 ObjectDB instances were leaked at exit (run with --verbose for details).",
            "WARNING: NPC action animation is not available, using idle: special-1",
            "Grid collision: original clearance, sliding and 400 deterministic motion cases passed",
            "   at: emit_signalp (core/object/object.cpp:1311) Error calling",
        ]:
            self.assertFalse(FAILURE_LINE.search(line), line)


class RunTest(unittest.TestCase):
    """run() judges a check by its log as well as its exit code, and never waits forever."""

    def test_a_clean_check_passes(self):
        ok, printed = run_quietly(fake_step("", stdout_text="Checks passed\n"))
        self.assertTrue(ok)
        self.assertTrue(printed.startswith("PASS  fake"), printed)

    def test_a_script_error_fails_a_check_that_exits_zero(self):
        # A parse error in a preloaded game script: the check still prints its success line.
        ok, printed = run_quietly(fake_step(
            'SCRIPT ERROR: Parse Error: Identifier "nope" not declared in the current scope.\n'
            "          at: GDScript::reload (res://scenes/shared/grid_collision.gd:56)\n",
            stdout_text="Grid collision: 400 deterministic motion cases passed\n",
        ))
        self.assertFalse(ok)
        self.assertIn("FAIL  fake", printed)
        self.assertIn("exited 0, but logged 1 error line(s)", printed)

    def test_an_undispatched_signal_fails_a_check_that_exits_zero(self):
        ok, _printed = run_quietly(fake_step(
            "ERROR: Error calling from signal 'timeout' to callable: 'SceneTree::_one_arg': "
            "Method expected 1 argument(s), but called with 0.\n"
        ))
        self.assertFalse(ok)

    def test_a_colour_coded_script_error_fails_the_check(self):
        ok, _printed = run_quietly(fake_step("\x1b[1;35mSCRIPT ERROR:\x1b[0;95m Assertion failed.\x1b[0m\n"))
        self.assertFalse(ok)

    def test_leaked_resources_at_exit_do_not_fail_the_check(self):
        ok, _printed = run_quietly(fake_step(
            "WARNING: 2 ObjectDB instances were leaked at exit (run with --verbose for details).\n"
            "ERROR: 4 resources still in use at exit (run with --verbose for details).\n"
        ))
        self.assertTrue(ok)

    def test_a_nonzero_exit_still_fails(self):
        ok, _printed = run_quietly(fake_step("", exit_code=1))
        self.assertFalse(ok)

    def test_only_check_steps_are_scanned(self):
        # The unittest and exporter steps judge themselves; their output may quote these lines.
        ok, _printed = run_quietly(fake_step("SCRIPT ERROR: quoted in a test\n"), script_check=False)
        self.assertTrue(ok)

    def test_a_check_that_never_quits_times_out(self):
        # An error directly in _run or _init unwinds it before quit(), and Godot idles on.
        command = [sys.executable, "-c", (
            "import sys, time\n"
            "sys.stderr.write('SCRIPT ERROR: Assertion failed.\\n'); sys.stderr.flush()\n"
            "time.sleep(30)\n"
        )]
        with mock.patch.object(run_checks, "CHECK_TIMEOUT", 0.5):
            ok, printed = run_quietly(command)
        self.assertFalse(ok)
        self.assertIn("timed out after 0.5s", printed)
        # What the check logged before it hung is still reported.
        self.assertIn("SCRIPT ERROR: Assertion failed.", printed)

    def test_the_timeout_covers_check_steps_only(self):
        # A Python step exits on an uncaught error; only a Godot --script run idles on.
        command = [sys.executable, "-c", "import time; time.sleep(0.5)"]
        with mock.patch.object(run_checks, "CHECK_TIMEOUT", 0.1):
            ok, _printed = run_quietly(command, script_check=False)
        self.assertTrue(ok)

    def test_an_error_above_the_tail_is_listed_once_with_its_location(self):
        early = "SCRIPT ERROR: Invalid call. Nonexistent function 'constrain_motion' in base 'GDScript'."
        late = "SCRIPT ERROR: Cannot call method 'get_viewport' on a null value."
        stderr = (
            f"{early}\n          at: _check_clearance (res://tests/check_grid_collision.gd:35)\n"
            + "".join(f"noise {n}\n" for n in range(run_checks.TAIL_LINES + 10))
            + f"{late}\n          at: _boom (res://tests/check_x.gd:6)\n"
        )
        ok, printed = run_quietly(fake_step(stderr))
        self.assertFalse(ok)
        self.assertEqual(printed.count(early), 1)
        self.assertEqual(printed.count(late), 1)
        self.assertIn("res://tests/check_grid_collision.gd:35", printed)
        self.assertNotIn("noise 0\n", printed)
        self.assertIn("exited 0, but logged 2 error line(s)", printed)
        # The early error comes first, then the tail, in the order they were logged.
        self.assertLess(printed.index(early), printed.index("..."))
        self.assertLess(printed.index("..."), printed.index(late))

    def test_verbose_prints_all_of_a_passing_step(self):
        stdout = "".join(f"line {n}\n" for n in range(run_checks.TAIL_LINES + 10))
        ok, printed = run_quietly(fake_step("", stdout_text=stdout), verbose=True)
        self.assertTrue(ok)
        self.assertIn("line 0\n", printed)
        self.assertIn(f"line {run_checks.TAIL_LINES + 9}\n", printed)
        self.assertNotIn("...", printed)


if __name__ == "__main__":
    unittest.main()

"""Behavioural harness for the lock screen authenticator.

Runs the real AuthHandler.qml against mock_auth.MockAuthenticator, which mirrors
kscreenlocker's PAM semantics. The only edits to the component under test are
mechanical: i18ndc() calls are resolved to their source string (KLocalizedContext
only exists inside kscreenlocker_greet) and the kscreenlocker enum namespace is
inlined as its numeric value.

Every scenario asserts on the user-visible symptom: "I typed the correct password
and the session did not unlock".

Usage: python3 run.py [A B C F D]
"""

import re
import shutil
import sys
import tempfile
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

from mock_auth import MockAuthenticator

REPO_ROOT = Path(__file__).resolve().parents[3]
AUTH_HANDLER = (
    REPO_ROOT
    / "src/kde/shells/caelestia.desktop/contents/lockscreen/components/AuthHandler.qml"
)

HARNESS_QML = """import QtQuick

// Mirrors LockScreenUi: it owns an AuthHandler, calls startLogin() on Enter and
// ensureAuthenticating() on every key press.
Item {
    id: harness

    property string password: ""
    property int attempt: 0
    property int keypress: 0
    property bool authing: h.isAuthenticating
    property bool blocked: h.graceLocked
    property string message: h.authMessage

    onAttemptChanged: if (harness.password.length > 0) h.startLogin(harness.password)
    onKeypressChanged: h.ensureAuthenticating()

    AuthHandler {
        id: h

        authenticatorTarget: authenticator
    }
}
"""

I18N_CALL = re.compile(r"i18ndc\((?:[^()]*)\)", re.DOTALL)
KSCREENLOCKER_IMPORT = re.compile(r"^import org\.kde\.kscreenlocker.*\n", re.MULTILINE)

KEEP_ALIVE = []


class Driver:
    def __init__(self, root):
        self.root = root

    def attempt(self, password):
        self.root.setProperty("password", password)
        self.root.setProperty("attempt", self.root.property("attempt") + 1)

    def keypress(self):
        self.root.setProperty("keypress", self.root.property("keypress") + 1)

    @property
    def blocked(self):
        return self.root.property("blocked")

    @property
    def message(self):
        return self.root.property("message")


def build_harness(directory: Path) -> Path:
    source = AUTH_HANDLER.read_text(encoding="utf-8")
    resolved = I18N_CALL.sub(
        lambda match: '"%s"' % re.findall(r'"([^"]*)"', match.group(0))[-1], source
    )
    resolved = resolved.replace("ScreenLocker.Authenticator.Fingerprint", "1")
    resolved = KSCREENLOCKER_IMPORT.sub("", resolved)
    (directory / "AuthHandler.qml").write_text(resolved, encoding="utf-8")
    (directory / "Harness.qml").write_text(HARNESS_QML, encoding="utf-8")
    return directory / "Harness.qml"


def load(build_qml: Path, mock):
    engine = QQmlEngine()
    engine.rootContext().setContextProperty("authenticator", mock)
    KEEP_ALIVE.append(engine)
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(build_qml)))
    KEEP_ALIVE.append(component)
    if component.isError():
        raise RuntimeError("; ".join(error.toString() for error in component.errors()))
    root = component.create()
    if root is None:
        raise RuntimeError("; ".join(error.toString() for error in component.errors()))
    KEEP_ALIVE.append(root)
    return Driver(root)


def report(title, mock, driver):
    print(f"  {title}")
    print(f"    startAuthenticating calls : {mock.start_calls}")
    print(f"    real PAM conversations    : {mock.real_conversations}")
    print(f"    refused attempts          : {mock.bogus_failures}")
    print(f"    authenticator unavailable : {mock.unavailable}")
    print(f"    passwords delivered       : {len(mock.delivered_passwords)}")
    print(f"    passwords dropped         : {len(mock.dropped_passwords)}")
    print(f"    greeter blocked           : {driver.blocked}")
    print(f"    unlocked                  : {mock.unlocked}")
    for event in mock.events:
        print(f"      {event}")


def idle(build_qml):
    """An idle lock screen must not restart a prompt that is already waiting."""
    mock = MockAuthenticator()
    driver = load(build_qml, mock)
    QTest.qWait(4500)
    report("idle lock screen, no typing", mock, driver)
    return mock.bogus_failures == 0 and not driver.blocked


def verdict(mock, driver):
    """One verdict per scenario: unlocked, and nothing was restarted behind its back."""
    return mock.unlocked and mock.bogus_failures == 0 and not mock.dropped_passwords


def first_attempt(build_qml):
    """The first attempt with the correct password unlocks."""
    mock = MockAuthenticator()
    driver = load(build_qml, mock)
    QTest.qWait(300)
    driver.attempt("correct")
    QTest.qWait(1000)
    report("first attempt, correct password", mock, driver)
    return verdict(mock, driver)


def retry_after_typo(build_qml):
    """A correct password after one typo unlocks."""
    mock = MockAuthenticator()
    driver = load(build_qml, mock)
    QTest.qWait(300)
    driver.attempt("wrong")
    QTest.qWait(3500)
    driver.attempt("correct")
    QTest.qWait(2000)
    report("correct password after one typo", mock, driver)
    return verdict(mock, driver)


def typing(build_qml):
    """LockScreenUi calls ensureAuthenticating() on every key press, so typing must
    not disturb the prompt that is waiting."""
    mock = MockAuthenticator()
    driver = load(build_qml, mock)
    QTest.qWait(300)
    for _ in range(8):
        driver.keypress()
        QTest.qWait(60)
    driver.attempt("correct")
    QTest.qWait(1000)
    report("typing the correct password", mock, driver)
    return verdict(mock, driver)


def fingerprint_failure(build_qml):
    """A failed scan runs beside the password prompt, so it must not discard it."""
    mock = MockAuthenticator()
    driver = load(build_qml, mock)
    # Let the greeter's heartbeat start the password conversation, so the scan fails
    # while the prompt is genuinely waiting.
    QTest.qWait(1500)
    mock.fingerprint_failure()
    for _ in range(4):
        driver.keypress()
        QTest.qWait(60)
    driver.attempt("correct")
    QTest.qWait(1000)
    report("failed fingerprint scan, then the correct password", mock, driver)
    return verdict(mock, driver) and mock.prompt_count == 1


def authenticator_reset(build_qml):
    """The greeter starts with a prompt-less promptForSecretChanged; that must not
    stop the first conversation from being started."""
    mock = MockAuthenticator()
    driver = load(build_qml, mock)
    mock.reset_prompt()
    QTest.qWait(1500)
    driver.attempt("correct")
    QTest.qWait(1000)
    report("prompt-less prompt change, then the correct password", mock, driver)
    return verdict(mock, driver) and mock.prompt_count == 1


def echo_prompt(build_qml):
    """An echo-on prompt is answered with the same field, so it has to hold the guard
    too -- otherwise the heartbeat restarts the conversation it is waiting on."""
    mock = MockAuthenticator(prompt_kind="echo")
    driver = load(build_qml, mock)
    QTest.qWait(1500)
    for _ in range(4):
        driver.keypress()
        QTest.qWait(60)
    driver.attempt("correct")
    QTest.qWait(1000)
    report("echo-on prompt, then the correct password", mock, driver)
    return verdict(mock, driver) and mock.prompt_count == 1


def after_idle(build_qml):
    """Sitting on the lock screen must not stop the next attempt from unlocking."""
    mock = MockAuthenticator()
    driver = load(build_qml, mock)
    QTest.qWait(15000)
    blocked_after_idle = driver.blocked
    driver.attempt("correct")
    QTest.qWait(2000)
    report(
        f"correct password after 15 s idle (blocked before: {blocked_after_idle})",
        mock,
        driver,
    )
    return verdict(mock, driver)


SCENARIOS = {
    "A": idle,
    "B": first_attempt,
    "C": retry_after_typo,
    "F": typing,
    "G": fingerprint_failure,
    "H": authenticator_reset,
    "I": echo_prompt,
    "D": after_idle,
}


def main(argv):
    selected = [arg.upper() for arg in argv[1:]] or ["A", "B", "C", "F", "G", "H", "I"]
    unknown = [name for name in selected if name not in SCENARIOS]
    if unknown:
        print(f"unknown scenario(s): {', '.join(unknown)}", file=sys.stderr)
        return 2

    build_dir = Path(tempfile.mkdtemp(prefix="caelestia-lock-auth-"))
    try:
        build_qml = build_harness(build_dir)
        app = QGuiApplication([argv[0]])
        results = {}
        for name in selected:
            results[name] = SCENARIOS[name](build_qml)
            print(f"    -> {'ok' if results[name] else 'FAILED'}")
        del app
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)

    failed = [name for name, ok in results.items() if not ok]
    if failed:
        print(
            "lock screen authenticator: "
            f"{len(failed)} scenario(s) failed: {', '.join(failed)}"
        )
        return 1
    print("lock screen authenticator: all scenarios passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

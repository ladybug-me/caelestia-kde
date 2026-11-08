"""A stand-in for kscreenlocker's `authenticator` (PamAuthenticators).

Semantics mirrored from kscreenlocker master
(greeter/pamauthenticators.cpp, greeter/pamauthenticator.cpp, greeter/worker/main.cpp):

* `startAuthenticating()` always calls `tryUnlock()`; since the 6.7 PAM rework it has
  no "already authenticating" guard.
* `tryUnlock()` bails when `busy`, otherwise sets busy and runs `Authenticate()`.
* The PAM worker answers a second `Authenticate()` with an immediate `Failure` while it
  is already inside `pam_authenticate` (`Worker::authenticate()`).
* When a prompt arrives, `PamAuthenticator::promptInternal()` sets busy back to false
  and keeps the D-Bus reply, so `busy` is false while a prompt waits for the password.
* `promptForSecret` is sticky: `respond()` clears only the pending reply, never the
  string, so `Boolean(promptForSecret || prompt)` stays true for the rest of the session.
* `respond()` without a pending prompt drops the password (qCWarning only).
* Failures arriving within 2 s of each other mark the authenticator unavailable.
"""

from PySide6.QtCore import Property, QDateTime, QObject, QTimer, Signal, Slot


class MockAuthenticator(QObject):
    promptChanged = Signal()
    promptForSecretChanged = Signal()
    infoMessageChanged = Signal()
    errorMessageChanged = Signal()
    busyChanged = Signal()
    succeeded = Signal()
    failed = Signal(int, object)
    noninteractiveError = Signal(int, object)
    loginFailedDelayStarted = Signal(int, object, int)

    Idle = 0
    Authenticating = 1

    def __init__(
        self,
        password="correct",
        prompt_delay_ms=10,
        verify_delay_ms=10,
        prompt_kind="secret",
        parent=None,
    ):
        super().__init__(parent)
        self.password = password
        self.prompt_delay_ms = prompt_delay_ms
        self.verify_delay_ms = verify_delay_ms
        # "secret" is PAM_PROMPT_ECHO_OFF (the password), "echo" is PAM_PROMPT_ECHO_ON,
        # which reaches the greeter through `prompt` instead of `promptForSecret`.
        self.prompt_kind = prompt_kind

        self._busy = False
        self._prompt = ""
        self._prompt_for_secret = ""
        self._info_message = ""
        self._error_message = ""
        self._unlocked = False
        self._state = self.Idle
        self._had_prompt = False

        self._pending = False
        self._in_authenticate = False
        self._unavailable = False
        self._failed_count = 0
        self._last_failed_ms = None

        self.events = []
        self._t0 = QDateTime.currentMSecsSinceEpoch()
        self.start_calls = 0
        self.real_conversations = 0
        self.bogus_failures = 0
        self.dropped_passwords = []
        self.delivered_passwords = []
        self.prompt_count = 0

    # ---- properties kscreenlocker exposes -------------------------------

    def _set_busy(self, value):
        if self._busy != value:
            self._busy = value
            self.busyChanged.emit()

    busy = Property(bool, lambda self: self._busy, notify=busyChanged)
    prompt = Property(str, lambda self: self._prompt, notify=promptChanged)
    promptForSecret = Property(
        str, lambda self: self._prompt_for_secret, notify=promptForSecretChanged
    )
    infoMessage = Property(str, lambda self: self._info_message, notify=infoMessageChanged)
    errorMessage = Property(str, lambda self: self._error_message, notify=errorMessageChanged)
    unlocked = Property(bool, lambda self: self._unlocked, notify=succeeded)
    state = Property(int, lambda self: self._state)
    hadPrompt = Property(bool, lambda self: self._had_prompt)
    inPasswordDelay = Property(bool, lambda self: False)
    authenticatorTypes = Property(int, lambda self: 0)

    @property
    def unavailable(self):
        return self._unavailable

    # ---- invokables -----------------------------------------------------

    @Slot()
    def startAuthenticating(self):
        self.start_calls += 1
        self._event(
            f"startAuthenticating #{self.start_calls} "
            f"(conversation in flight: {self._in_authenticate}, "
            f"prompt pending: {self._pending})"
        )
        self._try_unlock()

    @Slot()
    def stopAuthenticating(self):
        self._pending = False
        self._prompt = ""
        self._prompt_for_secret = ""
        self._info_message = ""
        self._error_message = ""
        self._in_authenticate = False
        self._set_busy(False)
        self._state = self.Idle
        self.promptChanged.emit()
        self.promptForSecretChanged.emit()

    @Slot()
    def cancel(self):
        self.stopAuthenticating()

    @Slot(str)
    def respond(self, response):
        if not self._pending:
            self.dropped_passwords.append(response)
            self._event("respond -> DROPPED (no pending prompt)")
            return
        self.delivered_passwords.append(response)
        self._event(f"respond -> delivered ({len(response)} chars)")
        self._pending = False
        QTimer.singleShot(self.verify_delay_ms, lambda: self._verify(response))

    # ---- internals ------------------------------------------------------

    def fingerprint_failure(self):
        """A scan that did not match: failed(Fingerprint, auth), and the interactive
        conversation it runs beside is left alone."""
        self._event("failed(Fingerprint): password prompt stays open")
        self.failed.emit(1, self)

    def reset_prompt(self):
        """What PamAuthenticators::onAuthenticatorChanged() does before it starts
        authenticating: the prompt members are empty and the change signals fire with
        no prompt behind them."""
        self._event("promptForSecretChanged('') after an authenticator reset")
        self._prompt = ""
        self._prompt_for_secret = ""
        self.promptChanged.emit()
        self.promptForSecretChanged.emit()

    def _event(self, what):
        self.events.append(f"{QDateTime.currentMSecsSinceEpoch() - self._t0:6d} ms  {what}")

    def _try_unlock(self):
        if self._busy or self._unavailable:
            return
        self._set_busy(True)
        if self._in_authenticate:
            QTimer.singleShot(0, self._authenticate_failed)
            return
        self._in_authenticate = True
        self.real_conversations += 1
        QTimer.singleShot(self.prompt_delay_ms, self._prompt_for_password)

    def _authenticate_failed(self):
        self._set_busy(False)
        self.bogus_failures += 1
        self._event(f"refused #{self.bogus_failures} (conversation in flight)")
        self._record_failure()
        self._state = self.Idle
        self.failed.emit(0, self)

    def _record_failure(self):
        now_ms = QDateTime.currentMSecsSinceEpoch()
        if self._last_failed_ms is not None and now_ms - self._last_failed_ms < 2000:
            self._failed_count += 1
            if self._failed_count > 3:
                self._unavailable = True
        else:
            self._failed_count = 0
        self._last_failed_ms = now_ms

    def _prompt_for_password(self):
        self._set_busy(False)
        self._pending = True
        self.prompt_count += 1
        self._had_prompt = True
        if self.prompt_kind == "echo":
            self._prompt = "Password: "
            self._event("prompt('Password: '): echo-on")
            self.promptChanged.emit()
            return
        self._prompt_for_secret = "Password: "
        self._event("promptForSecret('Password: ')")
        self.promptForSecretChanged.emit()

    def _verify(self, password):
        self._in_authenticate = False
        self._state = self.Idle
        if password == self.password:
            self._unlocked = True
            self._event("verify -> SUCCESS")
            self.succeeded.emit()
            return
        self._event("verify -> failure")
        self._record_failure()
        self.failed.emit(0, self)

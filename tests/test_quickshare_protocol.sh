#!/usr/bin/env bash
# suite: fast
#
# Quick Share takes connections from anything on the LAN, so the parts of the protocol
# that run before anything is authenticated are asserted here: the frame checks, the
# consent a transfer is bound to, and the deadlines that give a stalled peer's slot back.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$REPO_ROOT/shell/plugin/src/Caelestia/Services/QuickShare"
CRYPTO="$DIR/QuickShareCrypto.cpp"
CONNECTION="$DIR/QuickShareConnection.cpp"
SERVICE="$DIR/quickshare_service.cpp"
QML="$REPO_ROOT/shell/services/QuickShare.qml"

test_a_frame_whose_iv_is_not_one_block_is_refused() {
    assert_file_contains "$CRYPTO" 'iv.size() != ivLength' \
        "AES-256-CBC reads a whole block of IV, and the header is the peer's"
    assert_file_contains "$CRYPTO" 'EVP_CIPHER_iv_length(EVP_aes_256_cbc())' \
        "the length comes from the cipher rather than a second copy of 16 here"
    assert_file_contains "$CRYPTO" 'ciphertext.size() % EVP_CIPHER_block_size(EVP_aes_256_cbc()) != 0' \
        "a body that is not whole blocks was not produced by this cipher"
}

test_only_root_owned_protocol_code_is_elevated() {
    local elevated
    elevated="$(grep -rn 'pkexec' "$REPO_ROOT/shell" --include='*.qml' || true)"
    assert_not_contains "$elevated" 'Quickshell.shellPath' \
        "polkit must never be handed a file this user can rewrite"
}

test_a_transfer_is_bound_to_the_request_the_user_answered() {
    assert_file_contains "$CONNECTION" 'if (m_finished || m_incomingAccepted || m_incomingAnnounced)' \
        "a second request on one connection is refused, not asked about again"
    assert_file_contains "$CONNECTION" 'm_acceptedFileName = m_incomingFileName;' \
        "the name is frozen at acceptance"
    assert_file_contains "$CONNECTION" 'm_acceptedFileSize = m_incomingFileSize;' \
        "and so is the size"
    assert_file_contains "$CONNECTION" 'm_incomingOffset + body.size() > m_acceptedFileSize' \
        "every chunk is measured against what was agreed to"
    assert_file_contains "$CONNECTION" 'if (m_finished || !m_incomingAccepted)' \
        "a chunk that arrives after the transfer ended is not written"
}

test_a_request_naming_no_size_is_refused_before_it_is_shown() {
    assert_file_contains "$CONNECTION" 'if (size <= 0 || size > maxIncomingFileSize)' \
        "a size nobody would agree to is not put in front of the user"
}

test_a_peer_that_stops_talking_gives_its_slot_back() {
    assert_file_contains "$CONNECTION" 'constexpr int handshakeTimeoutMs' \
        "an unauthenticated host that connects and says nothing must not hold a slot"
    assert_file_contains "$CONNECTION" 'constexpr int consentTimeoutMs' \
        "a person deciding is a different wait from a peer stalling"
    assert_file_contains "$CONNECTION" 'constexpr int transferIdleTimeoutMs' \
        "and so is a transfer that has stopped moving"
    assert_file_contains "$CONNECTION" 'm_idleTimer->start(idleTimeoutMs())' \
        "the deadline is restarted by progress"
    assert_file_contains "$CONNECTION" 'm_buffer.append(m_socket->readAll());' \
        "which starts with the bytes that arrived"
}

test_a_file_only_leaves_after_both_ends_agree() {
    assert_file_contains "$CONNECTION" 'if (!m_sendConfirmed || !m_peerAccepted)' \
        "the peer accepting is not the user agreeing"
    assert_file_contains "$SERVICE" 'emit outgoingTransferPinReady(deviceId, deviceName' \
        "the sender is shown its own code so the two can be compared"
    assert_file_contains "$QML" 'root.sendPromptBody()' \
        "and is told to compare it with the receiving device"
    assert_file_contains "$QML" 'Check that %1 shows this code before accepting' \
        "the receiver is told the same thing"
}

run_tests

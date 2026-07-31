"""Tests for the optional 1Password Python Keyring backend."""

from __future__ import annotations

import json
import subprocess
import unittest

from keyring.errors import KeyringError, PasswordDeleteError

from onepassword_keyring import OnePasswordKeyring


class FakeOp:
    def __init__(self) -> None:
        self.document: dict | None = None
        self.calls: list[tuple[list[str], str | None]] = []

    def __call__(self, command: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
        input_text = kwargs.get("input")
        self.calls.append((command, input_text))
        operation = command[1:3]
        if operation == ["item", "list"]:
            items = (
                []
                if self.document is None
                else [{"id": "item-id", "title": self.document["title"]}]
            )
            return self._result(items)
        if operation == ["item", "template"]:
            return self._result(
                {
                    "title": "",
                    "category": "PASSWORD",
                    "fields": [
                        {
                            "id": "password",
                            "type": "CONCEALED",
                            "purpose": "PASSWORD",
                            "label": "password",
                            "value": "",
                        }
                    ],
                }
            )
        if operation == ["item", "get"]:
            return self._result(self.document)
        if operation in (["item", "create"], ["item", "edit"]):
            self.document = json.loads(input_text)
            return self._result(self.document)
        return subprocess.CompletedProcess(command, 1, "", "unexpected fake command")

    @staticmethod
    def _result(value) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(["op"], 0, json.dumps(value), "")


class OnePasswordKeyringTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fake = FakeOp()
        self.backend = OnePasswordKeyring(
            vault="Test Vault",
            executable="/test/bin/op",
            process_runner=self.fake,
        )

    def test_create_and_read_keep_secret_out_of_arguments(self) -> None:
        secret = '{"access_token":"top-secret","refresh_token":"also-secret"}'
        self.backend.set_password("dd-cli", "oauth-tokens", secret)
        self.assertEqual(self.backend.get_password("dd-cli", "oauth-tokens"), secret)
        self.assertTrue(
            any("top-secret" in (input_text or "") for _, input_text in self.fake.calls)
        )
        self.assertFalse(
            any(secret in argument for command, _ in self.fake.calls for argument in command)
        )

    def test_update_and_delete_keep_dedicated_item(self) -> None:
        self.backend.set_password("dd-cli", "oauth-tokens", "first")
        self.backend.set_password("dd-cli", "oauth-tokens", "second")
        self.assertEqual(self.backend.get_password("dd-cli", "oauth-tokens"), "second")
        self.backend.delete_password("dd-cli", "oauth-tokens")
        self.assertIsNone(self.backend.get_password("dd-cli", "oauth-tokens"))
        self.assertIsNotNone(self.fake.document)

    def test_delete_missing_credentials_raises_keyring_error(self) -> None:
        with self.assertRaises(PasswordDeleteError):
            self.backend.delete_password("dd-cli", "oauth-tokens")

    def test_backend_is_restricted_to_dd_cli_token_document(self) -> None:
        self.assertIsNone(self.backend.get_password("another-service", "oauth-tokens"))
        with self.assertRaises(KeyringError):
            self.backend.set_password("another-service", "oauth-tokens", "secret")

    def test_cli_error_does_not_echo_sensitive_input(self) -> None:
        secret = "never-echo-this"

        def failing_runner(command, **kwargs):
            return subprocess.CompletedProcess(command, 1, "", f"failed with {secret}")

        backend = OnePasswordKeyring(
            vault="Test Vault",
            executable="/test/bin/op",
            process_runner=failing_runner,
        )
        with self.assertRaises(KeyringError) as raised:
            backend.set_password("dd-cli", "oauth-tokens", secret)
        self.assertNotIn(secret, str(raised.exception))


if __name__ == "__main__":
    unittest.main()

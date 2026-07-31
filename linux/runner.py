"""Linux PyInstaller entry point for the extracted DoorDash CLI package."""

from onepassword_keyring import configure_from_environment

configure_from_environment()

from dd_cli.cli import cli


if __name__ == "__main__":
    cli()

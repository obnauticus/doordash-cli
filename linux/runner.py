"""Linux PyInstaller entry point for the extracted DoorDash CLI package."""

from dd_cli.cli import cli


if __name__ == "__main__":
    cli()

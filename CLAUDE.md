# Claude Code Memory & Guidelines

## General Principles
- **First Step**: When first encountering this project, ALWAYS read `README.md` and linked documentation (e.g., `docs/CONTRIBUTING.md`, `docs/INTEGRATION.md`) to understand the project's operational rules and workflows.
- **Service Management**: Ensure install scripts (`.install`) provide clear, standardized instructions for both User Level and System Level service management.

## Project Specifics
- **Type**: AUR Packages Monorepo
- **Platform**: Arch Linux

## Common Commands

### Local Testing & Updates
- **Install Dependencies**: `sudo ./scripts/ci_manager.sh install`
- **Setup User**: `sudo ./scripts/ci_manager.sh setup_user`
- **Update Package (Dry Run)**: `./scripts/ci_manager.sh run_update <package_name> --dry-run`
- **Force Update & Build**: `./scripts/ci_manager.sh run_update <package_name> --force --dry-run`

### Git & Workflow
- **Update Strategy**: Check `scripts/auto_update.sh` and package-specific `update_strategy.sh`.
- **CI/CD**: Workflows are in `.github/workflows/aur-publish.yml`.

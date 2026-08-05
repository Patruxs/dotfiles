# Contributing

Thanks for helping improve this project. Bug reports, documentation fixes, platform support, and focused feature changes are welcome.

## Before You Start

- Search existing issues before opening a new one.
- Do not include passwords, tokens, private keys, private hostnames, or other sensitive machine data.
- Open an issue before making a large behavior or architecture change.
- Keep changes focused and preserve cross-platform behavior where applicable.

## Development Workflow

1. Fork the repository and create a branch from `main`.
2. Make the smallest complete change that solves the problem.
3. Update documentation when behavior or setup steps change.
4. Run the fast test suite:

   ```sh
   ./test/test_harness.sh
   ```

5. If your change affects bootstrap behavior, test the relevant operating system and profile as closely as possible to a real installation.
6. Open a pull request and explain the problem, solution, platforms tested, and any remaining limitations.

## Pull Request Checklist

- [ ] No secrets or private machine data are included.
- [ ] Shell, Ansible, PowerShell, and Chezmoi changes remain idempotent.
- [ ] Relevant tests pass locally.
- [ ] User-facing behavior is documented.
- [ ] The pull request contains one focused change.

## Reporting Security Problems

Do not report vulnerabilities or exposed credentials in a public issue. Follow [SECURITY.md](SECURITY.md).

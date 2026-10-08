# Self-hosted CI runners

Tests and static analysis (`Run Tests` sections and `Code Analysis` in
`.github/workflows/ci.yml`) can run on our own machines. Builds stay on GitHub:
`build-linux-release` in `ci.yml` and everything in `release.yml` (Windows,
macOS with signing, Linux packages) use GitHub-hosted runners.

## How a job picks its runner

Each of the two jobs has

```yaml
runs-on: ${{ <pull request from a fork> && 'ubuntu-latest' || fromJSON(vars.CI_RUNS_ON || '"ubuntu-latest"') }}
```

- **Pull requests from forks always run on GitHub-hosted runners**, never on
  ours, whatever the variable says.
- Otherwise the repository variable `CI_RUNS_ON` decides. Unset (or deleted) means
  `ubuntu-latest`. Set it to move the jobs to our runners:

```bash
gh variable set CI_RUNS_ON --repo QueryaHub/Querya-Desktop \
  --body '["self-hosted","linux","querya-ci"]'
# back to GitHub-hosted:
gh variable delete CI_RUNS_ON --repo QueryaHub/Querya-Desktop
```

That switch is the first thing to flip if our machine is down or being serviced.

On a self-hosted runner the apt step is skipped (the native packages are
installed by `scripts/ci/setup-runner.sh`) and `flutter test` runs with
`--concurrency=2`, because several runners share one machine.

## Repository settings

The repository is public, so under Settings -> Actions -> General keep
**Fork pull request workflows from outside collaborators** on *Require approval
for all external contributors*. Do not add `pull_request_target` workflows that
check out and run PR code on these runners.

## Setting up the machine

The runners live in an Ubuntu 24.04 container or VM (here: LXC `querya-ci` on
Proxmox: 8 cores, 16 GiB RAM, 80 GiB disk, outbound access only). Inside it, as
root:

```bash
TOKEN=$(gh api -X POST repos/QueryaHub/Querya-Desktop/actions/runners/registration-token --jq .token)
RUNNER_URL=https://github.com/QueryaHub/Querya-Desktop \
RUNNER_TOKEN="$TOKEN" \
RUNNER_COUNT=4 \
./scripts/ci/setup-runner.sh
```

The script installs the packages the test jobs need, creates an unprivileged
`runner` user without sudo, and registers `RUNNER_COUNT` runners
(`querya-ci-1..N`, label `querya-ci`) as systemd services. Re-running it skips
runners that already exist. The Flutter SDK is installed per job by
`subosito/flutter-action`, exactly as on GitHub-hosted runners, so the version is
pinned in one place (`ci.yml`).

## Operating notes

- Each runner runs one job at a time; four runners run four test sections in
  parallel. Queue is visible in the Actions tab; add runners by raising
  `RUNNER_COUNT` and re-running the script.
- Keep the machine updated (`apt upgrade`) and clean old workspaces under
  `/home/runner/actions-runner-*/_work` if the disk fills.
- The runners hold no secrets of ours; do not add any to the container.

## Dev Container and benchmarks

`.devcontainer/` provides a ready environment (Flutter 3.41.6, Linux desktop
toolchain, Docker CLI) for GitHub Codespaces or VS Code Dev Containers. On start
it runs `docker/docker-compose.yml` (PostgreSQL, MySQL, Redis, MongoDB,
ClickHouse) and forwards their ports.

`.github/workflows/benchmark.yml` runs `benchmark/grid_perf_bench.dart` under
Xvfb on the PR and on its base branch and comments when frame times are more
than 5% worse. It is informational and never blocks a merge.

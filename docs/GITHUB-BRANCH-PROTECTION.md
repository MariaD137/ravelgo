# GitHub Branch Protection Setup

Branch protection cannot be configured automatically from this session.
Follow these steps in the GitHub UI.

## Protect `main` (Production)

1. Go to **Settings** > **Branches** > **Add branch protection rule**
2. Branch name pattern: `main`
3. Enable:
   - [x] **Require a pull request before merging**
     - Required approvals: 1
   - [x] **Require status checks to pass before merging**
     - Required checks (add these after the first CI run):
       - `build-and-test` (from backend-ci.yml)
       - `analyze-and-test` (from flutter-ci.yml, if Flutter files changed)
       - `synth` (from infra-ci.yml, if infra files changed)
   - [x] **Require conversation resolution before merging**
   - [x] **Do not allow bypassing the above settings**
   - [x] **Block force pushes**
   - [x] **Block deletions**
4. Click **Create**

## Protect `develop` (Integration)

1. Add another branch protection rule
2. Branch name pattern: `develop`
3. Enable:
   - [x] **Require a pull request before merging**
     - Required approvals: 1
   - [x] **Require status checks to pass before merging**
     - Same checks as `main`
   - [x] **Block force pushes**
   - [x] **Block deletions**
4. Click **Create**

## Verify After Setup

- Try pushing directly to `main` — should be rejected
- Open a test PR to `develop` — CI should run and be required
- Confirm the required status check names match the actual CI job names

## Finding the Correct Status Check Names

After the first CI run completes on a PR:

1. Go to the PR's "Checks" tab
2. Note the exact check names (e.g., `build-and-test`, `analyze-and-test (user_app)`)
3. Use these exact names in the branch protection settings

# Git-flow with github actions CI/CD

### What's the difference

The `git-flow` workflow is made for _personal-usage_, hence adding CI/CD transform the same branching workflow convention to match with standard Pull Request workflows using github cli.

---

### Installation

##### git-flow

Windows - [Git for Windows](https://gitforwindows.org/)
MacOS - `brew install git-flow`
Linux - e.g. `sudo apt install git-flow` (based on your package manager)

##### github cli

Windows - e.g. `winget install GitHub.CLI` (based on your package manager)
MacOS - `brew install gh`
Linux - e.g. `sudo apt install github-cli` (based on your package manager)

---

### Setup

1. Run `git flow init` in your repository and complete the setup
2. Run `gh auth login` and complete the auth
3. Modify/Append [.zshrc](./.zshrc) tailored to your setup (optional)
4. Setup [github token](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets), name it as `TOKEN`

---

### How to start using

1. Run `git flow (branch) start (name_of_the_branch)` / `git checkout -b (name_of_the_branch)` (optional for refactor branch)
2. **DO NOT** complete with `git flow (branch) finish (name_of_the_branch)`, instead do `gh pr create --base (branch - follow git-flow convention)`
3. Follow the `gh cli` to complete the PR process
4. You should now see the _merged_ branch getting _deleted_

---

### Reference

- [git-flow official documentation](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow)
- [github actions plan limits](https://docs.github.com/en/actions/reference/limits)

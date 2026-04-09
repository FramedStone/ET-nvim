# git
alias gc="git commit"
alias gs="git status"
alias gS="git switch"
alias gP="git push"
alias gp="git pull"
alias gf="git fetch"
alias gco="git checkout"
alias gm="git merge"
alias gt="git tag"
alias gl="git log"
alias gw="git worktree"

# git flow
alias gflw="git flow"
alias gflwi="git flow init"
alias gflwfs="git flow feature start"
alias gflwrs="git flow release start"
alias gflwhs="git flow hotfix start"
alias gflwbs="git flow bugfix start"

# integrate with github cli to create pr
function gflwpr() {
  case "$1" in
    feature)
      gh pr create --base develop
      ;;
    bugfix)
      gh pr create --base develop
      ;;
    refactor)
      gh pr create --base develop
      ;;
    release)
      local branch=$(git branch --show-current)
      local version_num=${branch#release/}
      version_num=${version_num#v}
      local version="v${version_num}"
      local sha=$(git rev-parse HEAD)
      gh pr create --base main
      local repo_info=$(gh repo view --json owner,repository -q '.owner.login + "/" + .repository')
      gh api repos/$repo_info/git/refs -X POST -f ref=refs/tags/$version -f sha=$sha
      echo "Created tag: $version"
      ;;
    hotfix)
      gh pr create --base main
      ;;
    *)
      echo "Usage: gflwpr {feature|release|refactor|hotfix|bugfix}"
      ;;
  esac
}


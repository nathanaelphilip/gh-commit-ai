#!/usr/bin/env bash
# Bash completion for gh-commit-ai
# Install: gh commit-ai install-completion

_gh_commit_ai() {
    local cur prev words cword
    _init_completion || return

    # Main commands
    local commands="changelog review pr-description version semver install-hook uninstall-hook install-completion uninstall-completion"

    # Main flags
    local main_flags="--help -h --preview --dry-run --amend --options --type --max-lines --no-lowercase --verbose -v"

    # Subcommand flags
    local version_flags="--help -h --create-tag -t --prefix"
    local changelog_flags="--help -h --since --format"
    local review_flags="--help -h --all"
    local pr_flags="--help -h --base --output"

    # Get the command (first non-flag argument)
    local command=""
    local i
    for (( i=1; i < cword; i++ )); do
        if [[ "${words[i]}" != -* ]]; then
            command="${words[i]}"
            break
        fi
    done

    # If we're completing the first argument (after gh-commit-ai)
    if [[ $cword -eq 1 ]] || [[ -z "$command" ]]; then
        case "$cur" in
            -*)
                COMPREPLY=( $(compgen -W "$main_flags" -- "$cur") )
                ;;
            *)
                COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
                ;;
        esac
        return 0
    fi

    # Complete based on subcommand
    case "$command" in
        version|semver)
            case "$cur" in
                -*)
                    COMPREPLY=( $(compgen -W "$version_flags" -- "$cur") )
                    ;;
                *)
                    if [[ "$prev" == "--prefix" ]]; then
                        COMPREPLY=( $(compgen -W "v ver version release-" -- "$cur") )
                    fi
                    ;;
            esac
            ;;

        changelog)
            case "$cur" in
                -*)
                    COMPREPLY=( $(compgen -W "$changelog_flags" -- "$cur") )
                    ;;
                *)
                    if [[ "$prev" == "--since" ]]; then
                        # Suggest git tags or refs
                        local tags=$(git tag 2>/dev/null)
                        COMPREPLY=( $(compgen -W "$tags HEAD~1 HEAD~5 HEAD~10" -- "$cur") )
                    elif [[ "$prev" == "--format" ]]; then
                        COMPREPLY=( $(compgen -W "keepachangelog markdown" -- "$cur") )
                    fi
                    ;;
            esac
            ;;

        review)
            case "$cur" in
                -*)
                    COMPREPLY=( $(compgen -W "$review_flags" -- "$cur") )
                    ;;
            esac
            ;;

        pr-description)
            case "$cur" in
                -*)
                    COMPREPLY=( $(compgen -W "$pr_flags" -- "$cur") )
                    ;;
                *)
                    if [[ "$prev" == "--base" ]]; then
                        # Suggest common base branches
                        local branches=$(git branch -a 2>/dev/null | sed 's/^\s*\*\?\s*//' | sed 's/^remotes\/origin\///')
                        COMPREPLY=( $(compgen -W "main master develop $branches" -- "$cur") )
                    elif [[ "$prev" == "--output" ]]; then
                        # File completion
                        COMPREPLY=( $(compgen -f -- "$cur") )
                    fi
                    ;;
            esac
            ;;

        install-hook|uninstall-hook|install-completion|uninstall-completion)
            case "$cur" in
                -*)
                    COMPREPLY=( $(compgen -W "--help -h" -- "$cur") )
                    ;;
            esac
            ;;

        *)
            # For unknown commands or main command flags
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "$main_flags" -- "$cur") )
            fi
            ;;
    esac

    # Special handling for --type flag
    if [[ "$prev" == "--type" ]]; then
        COMPREPLY=( $(compgen -W "feat fix docs style refactor test chore perf build ci" -- "$cur") )
    fi

    return 0
}

# Register the completion function
complete -F _gh_commit_ai gh-commit-ai

# Also support when called as a gh extension
complete -F _gh_commit_ai gh commit-ai

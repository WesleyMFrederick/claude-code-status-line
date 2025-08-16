#!/bin/bash

# Debug flag - set to true to write JSON input to file
DEBUG=false

# Read Claude Code context from stdin
input=$(cat)

# Debug: Write JSON input to file if debug is enabled
if [[ "$DEBUG" == "true" ]]; then
    debug_dir="/Users/wesleyfrederick/Documents/ObsidianVault/0_SoftwareDevelopment/claude-code-status-line/json-return"
    if [[ ! -d "$debug_dir" ]]; then
        mkdir -p "$debug_dir"
    fi
    
    # Extract session_id from input for filename
    session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
    statusline_file="$debug_dir/${session_id}-statusline.jsonl"
    
    # Append input to JSONL file
    echo "$input" >> "$statusline_file"
fi

# Source configuration
CONFIG_FILE="$(dirname "$0")/config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    # Fallback if config doesn't exist
    BASE_PATH="$HOME/Documents/ObsidianVault/0_SoftwareDevelopment"
fi

# Extract relevant information using jq
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // ""')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // ""')

# Function to get project name with git-first detection
get_project_name() {
    local dir="$1"
    
    # Step 1: Check if .git exists in current directory
    if [[ -e "$dir/.git" ]]; then
        # Case A: .git is a file (worktree)
        if [[ -f "$dir/.git" ]]; then
            # Read the gitdir path from the .git file
            local gitdir=$(head -1 "$dir/.git" 2>/dev/null | cut -d' ' -f2)
            
            if [[ -n "$gitdir" ]]; then
                # Extract project name from path like:
                # /path/to/claude-code-web-ui/.git/worktrees/core-chat-functionality
                # We want "claude-code-web-ui" (the directory before /.git/)
                
                # Remove everything from /.git/ onwards
                local main_repo_path="${gitdir%/.git/*}"
                
                # Get the basename (project name)
                if [[ -n "$main_repo_path" ]]; then
                    echo "$(basename "$main_repo_path")"
                    return
                fi
            fi
        fi
        
        # Case B: .git is a directory (regular repo)
        if [[ -d "$dir/.git" ]]; then
            # Try git remote first
            local remote_url=$(git -C "$dir" remote get-url origin 2>/dev/null)
            if [[ -n "$remote_url" ]]; then
                local repo_name=$(basename "$remote_url" .git)
                echo "$repo_name"
                return
            fi
            
            # Fallback to git toplevel
            local toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
            if [[ -n "$toplevel" ]]; then
                echo "$(basename "$toplevel")"
                return
            fi
        fi
    fi
    
    # Step 2: No .git found - check if inside git repo anyway
    if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # Try git worktree list to get main worktree
        local main_worktree=$(git -C "$dir" worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')
        if [[ -n "$main_worktree" ]]; then
            echo "$(basename "$main_worktree")"
            return
        fi
        
        # Try git remote
        local remote_url=$(git -C "$dir" remote get-url origin 2>/dev/null)
        if [[ -n "$remote_url" ]]; then
            local repo_name=$(basename "$remote_url" .git)
            echo "$repo_name"
            return
        fi
        
        # Fallback to git toplevel
        local toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
        if [[ -n "$toplevel" ]]; then
            echo "$(basename "$toplevel")"
            return
        fi
    fi
    
    # Step 3: No git info available - use current folder name
    echo "$(basename "$dir")"
}

# Get project name
project_name=""
if [[ -n "$current_dir" ]]; then
    project_name="$(get_project_name "$current_dir")"
fi

# Calculate git relative path from repository root to current directory
git_relative_path=""
if [[ -n "$current_dir" ]]; then
    # Find the git repository root
    git_root=""
    if git -C "$current_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git_root=$(git -C "$current_dir" rev-parse --show-toplevel 2>/dev/null)
    fi
    
    if [[ -n "$git_root" ]]; then
        # Calculate relative path from git root to current directory
        if [[ "$current_dir" != "$git_root" ]]; then
            # Check if we're in a worktree
            if [[ -f "$current_dir/.git" ]]; then
                # Read gitdir from .git file for worktrees
                gitdir=$(head -1 "$current_dir/.git" 2>/dev/null | cut -d' ' -f2)
                if [[ -n "$gitdir" ]] && [[ "$gitdir" == *"/.git/worktrees/"* ]]; then
                    # Extract worktree name from path like:
                    # /path/to/repo/.git/worktrees/branch-name
                    worktree_name=$(basename "$gitdir")
                    git_relative_path="../worktrees/$worktree_name"
                fi
            else
                # Regular subdirectory - calculate relative path
                git_relative_path=$(realpath --relative-to="$git_root" "$current_dir" 2>/dev/null)
                if [[ -n "$git_relative_path" ]] && [[ "$git_relative_path" != "." ]]; then
                    git_relative_path="./$git_relative_path"
                else
                    git_relative_path=""
                fi
            fi
        fi
    fi
fi

# Check if we're in a git repository and get branch
branch=""
if [[ -d "$current_dir/.git" ]] || git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$current_dir" branch --show-current 2>/dev/null)
    
    # Handle detached HEAD case
    if [[ -z "$branch" ]]; then
        # Check if we're in detached HEAD state
        if git -C "$current_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
            # Get short commit hash for detached HEAD
            short_hash=$(git -C "$current_dir" rev-parse --short HEAD 2>/dev/null)
            if [[ -n "$short_hash" ]]; then
                branch="detached@$short_hash"
            else
                branch="detached"
            fi
        fi
    fi
fi

# Check for uncommitted changes (dirty state)
dirty=""
if [[ -n "$branch" ]]; then
    if ! git -C "$current_dir" diff --quiet 2>/dev/null || ! git -C "$current_dir" diff --cached --quiet 2>/dev/null; then
        dirty="*"
    fi
fi

# Build path display
path_display=""
if [[ -n "$current_dir" ]]; then
    # Check if current directory is under BASE_PATH
    if [[ "$current_dir" == "$BASE_PATH"* ]]; then
        # Remove BASE_PATH from current_dir to get relative path
        relative_path="${current_dir#$BASE_PATH}"
        # Remove leading slash if present
        relative_path="${relative_path#/}"
        
        if [[ -z "$relative_path" ]]; then
            # We're in the base directory
            path_display="...~/"
        else
            # We're in a subdirectory - show just the current directory name for cleaner display
            path_display="...~/$(basename "$current_dir")"
        fi
    else
        # Outside BASE_PATH, show basename for cleaner display
        path_display="$(basename "$current_dir")"
    fi
    
    # Add branch if available
    if [[ -n "$branch" ]]; then
        path_display="$path_display ($branch)"
    fi
fi

# Get Claude session time remaining
session_time=""
if [[ -f "$HOME/.claude/scripts/status-line/claude-session-time.js" ]]; then
    session_time_raw=$(node "$HOME/.claude/scripts/status-line/claude-session-time.js" --statusline 2>/dev/null)
    if [[ -n "$session_time_raw" ]] && [[ "$session_time_raw" != "--:--:--" ]]; then
        session_time="$session_time_raw"
    fi
fi

# Get context window usage with enhanced parsing
context_tokens=""
context_limit=""
context_percent=""
if [[ -f "$HOME/.claude/scripts/status-line/claude-context-tracker.js" ]]; then
    # Run context tracker and capture the output
    context_output=$(echo "$input" | node "$HOME/.claude/scripts/status-line/claude-context-tracker.js" 2>/dev/null)
    if [[ -n "$context_output" ]]; then
        # Extract tokens and percentage from output like "Context usage: 125.3K/1M tokens (13%)"
        # Parse: "Context usage: XXX/YYY tokens (ZZ%)"
        context_line=$(echo "$context_output" | grep "Context usage:")
        if [[ -n "$context_line" ]]; then
            # Extract tokens used (before the first /)
            context_tokens=$(echo "$context_line" | sed -n 's/.*Context usage: \([0-9.]*[KM]\).*/\1/p')
            # Extract limit (after / and before " tokens")
            context_limit=$(echo "$context_line" | sed -n 's/.*\/\([0-9.]*[KM]\) tokens.*/\1/p')
            # Extract percentage (between parentheses, without %)
            context_percent=$(echo "$context_line" | sed -n 's/.*(\([0-9]*\)%).*/\1/p')
        fi
    fi
fi

# Build final status line in required format: project-name (branch) | model | tokens/limit percentage%
final_output=""

# Start with project name
if [[ -n "$project_name" ]]; then
    final_output="$project_name"
fi

# Add branch if available
if [[ -n "$branch" ]]; then
    final_output="$final_output ($branch$dirty)"
fi

# Add separator and model
if [[ -n "$final_output" ]]; then
    final_output="$final_output | $model_name"
else
    final_output="$model_name"
fi

# Add context usage if available
if [[ -n "$context_tokens" ]] && [[ -n "$context_limit" ]] && [[ -n "$context_percent" ]]; then
    final_output="$final_output | ${context_tokens}/${context_limit} ${context_percent}%"
fi

# Add relative path if different from project root
if [[ -n "$git_relative_path" ]]; then
    final_output="$final_output | $git_relative_path"
fi

# Output the final result
printf "%s" "$final_output"
# Claude Code Status Line

A customizable status line for Claude Code that displays project information, git branch, model info, context window usage, and relative paths.

## Features

- **Project Detection**: Automatically detects project name from git repository
- **Git Branch**: Shows current branch or detached HEAD state  
- **Model Information**: Displays current Claude model (Opus 4.1, Sonnet 4, etc.)
- **Context Window Tracking**: Shows token usage and percentage (supports 1M context for Sonnet 4)
- **Relative Path Display**: Shows worktree or subdirectory paths when different from project root
- **Session Time**: Displays remaining time in current Claude session

## Project Structure

```
claude-code-status-line/
├── scripts/
│   ├── statusline-script.sh       (main status line script)
│   ├── claude-context-tracker.js  (context window analyzer)
│   └── claude-session-time.js     (session timer)
├── .gitignore                     (excludes personal config and debug files)
└── README.md
```

## Installation

### 1. Clone or Download

```bash
git clone https://github.com/WesleyMFrederick/claude-code-status-line.git
cd claude-code-status-line
```

### 2. Copy Scripts

```bash
# Create the directory if it doesn't exist
mkdir -p ~/.claude/scripts/status-line

# Copy all scripts
cp scripts/* ~/.claude/scripts/status-line/

# Make scripts executable
chmod +x ~/.claude/scripts/status-line/*.sh ~/.claude/scripts/status-line/*.js
```

### 3. Create Personal Config

Create your own `config.sh` file (this is gitignored):

```bash
# Create config with your preferred base path
cat > ~/.claude/scripts/status-line/config.sh << 'EOF'
#!/bin/bash
# Status line configuration
BASE_PATH="$HOME/Documents/Projects"  # Adjust to your projects directory
EOF
```

### 4. Configure Claude Code

Add the status line to your Claude Code settings by editing `~/.claude/settings.json` or `~/.claude/settings.local.json`:

```json
{
  "statusLine": {
    "enabled": true,
    "script": "~/.claude/scripts/status-line/statusline-script.sh"
  }
}
```

## Output Formats

### Basic Format
```
project-name (branch) | Model | tokens/limit percentage%
```

### With Relative Path
```
project-name (branch) | Model | tokens/limit percentage% | relative-path
```

### Examples

**Regular repository at root:**
```
my-app (main) | Sonnet 4 | 25.3K/1M 3%
```

**Git worktree:**
```
claude-code-web-ui (feature/new-ui) | Opus 4.1 | 150K/200K 75% | ../worktrees/feature-new-ui
```

**Subdirectory:**
```
my-project (main) | Sonnet 4 | 98.1K/1M 10% | ./src/components
```

## Key Features

### Context Window Support
- **Sonnet 4**: 1M token context window (displays as "1M" not "1.0M")
- **Opus 4.1**: 200K token context window
- Automatically detects model and shows appropriate limits

### Smart Path Detection
- Shows relative paths only when Claude is working in a different directory than the git repository root
- Supports git worktrees with `../worktrees/branch-name` format
- Shows subdirectories as `./folder/subfolder`

### Git Integration
- Works with regular repositories, worktrees, and detached HEAD states
- Detects project names from git remotes or repository structure
- Handles complex worktree setups automatically

## Configuration

The `config.sh` file allows customization of the base path for cleaner path displays:

```bash
#!/bin/bash
# Status line configuration
BASE_PATH="$HOME/Documents/MyProjects"  # Your projects directory
```

This affects how paths are displayed in the status line for a cleaner appearance.

## Debug Mode

To enable debug logging (creates JSON files in `json-return/` directory), edit the script:

```bash
# In statusline-script.sh, change line 4:
DEBUG=true  # Enable debug mode
DEBUG=false # Disable debug mode (default)
```

## Requirements

- **Claude Code**: Status line integration
- **Node.js**: Required for context tracking and session timer
- **jq**: JSON parsing (usually pre-installed on most systems)
- **Git**: Repository information detection

## Troubleshooting

1. **No status line appears**: 
   - Check that scripts are executable: `chmod +x ~/.claude/scripts/status-line/*`
   - Verify settings.json configuration

2. **Missing context info**: 
   - Ensure claude-context-tracker.js is in the correct location
   - Check that transcript files are accessible

3. **Wrong project detection**: 
   - Verify git repository setup and remote configuration
   - Check that you're in a git repository

4. **Path issues**: 
   - Verify config.sh exists and has correct BASE_PATH
   - Ensure realpath command is available (installed by default on most systems)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is open source. Feel free to use, modify, and distribute.
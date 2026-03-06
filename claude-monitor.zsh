# Claude Tab Monitor - Zsh integration
# Source this file in your .zshrc

# Wrap claude command to detect session exit
claude() {
    # Run the real claude command
    command claude "$@"
    local exit_code=$?

    # Notify plugin that this Claude session has ended
    if [ -n "$ZELLIJ" ] && [ -n "$ZELLIJ_PANE_ID" ]; then
        zellij pipe --name claude-status -- "{\"pane_id\":\"$ZELLIJ_PANE_ID\",\"state\":\"exit\"}"
    fi

    return $exit_code
}

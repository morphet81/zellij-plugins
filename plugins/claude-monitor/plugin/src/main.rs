use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};
use zellij_tile::prelude::*;

/// Pill icons prepended to tab names to indicate AI session state.
const PILL_WORKING: &str = "\u{1F535}"; // 🔵
const PILL_WAITING: &str = "\u{1F7E1}"; // 🟡
const PILL_IDLE: &str = "\u{1F7E2}"; // 🟢

/// Possible states for a tracked AI pane.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PaneState {
    Working,
    Waiting,
    Idle,
}

impl PaneState {
    fn pill(self) -> &'static str {
        match self {
            PaneState::Working => PILL_WORKING,
            PaneState::Waiting => PILL_WAITING,
            PaneState::Idle => PILL_IDLE,
        }
    }

    /// Priority for aggregation: higher wins. Waiting > Working > Idle.
    fn priority(self) -> u8 {
        match self {
            PaneState::Waiting => 3,
            PaneState::Working => 2,
            PaneState::Idle => 1,
        }
    }
}

/// Incoming pipe message payload.
#[derive(Debug, Deserialize)]
struct StatusPayload {
    pane_id: String,
    state: String,
}

/// Main plugin state.
#[derive(Default)]
struct State {
    /// Per-pane AI session state.
    pane_states: BTreeMap<u32, PaneState>,

    /// Original (clean) tab name, keyed by tab position.
    original_tab_names: BTreeMap<usize, String>,

    /// Pane ID -> tab position (0-based).
    pane_to_tab_position: BTreeMap<u32, usize>,

    /// Tab position -> current tab name from TabInfo (may include our pill).
    tab_names: BTreeMap<usize, String>,

    /// Tab position -> last name we asked rename_tab() to set.
    /// This is the stable guard against event cascades — never cleared by TabUpdate.
    desired_tab_names: BTreeMap<usize, String>,
}

impl State {
    /// Strip all pill prefixes we may have added (handles stacked pills).
    fn strip_pill(name: &str) -> &str {
        let mut current = name;
        loop {
            let mut stripped = false;
            for pill in [PILL_WORKING, PILL_WAITING, PILL_IDLE] {
                if let Some(rest) = current.strip_prefix(pill) {
                    current = rest.strip_prefix(' ').unwrap_or(rest);
                    stripped = true;
                    break;
                }
            }
            if !stripped {
                return current;
            }
        }
    }

    /// Get the aggregate state for a tab (by position).
    fn aggregate_tab_state(&self, tab_position: usize) -> Option<PaneState> {
        let mut best: Option<PaneState> = None;
        for (&pane_id, &state) in &self.pane_states {
            if self.pane_to_tab_position.get(&pane_id) == Some(&tab_position) {
                best = Some(match best {
                    None => state,
                    Some(prev) if state.priority() > prev.priority() => state,
                    Some(prev) => prev,
                });
            }
        }
        best
    }

    /// Recompute and apply tab names for all tracked tabs (those with or
    /// previously-with Claude panes). This ensures tabs that lost their last
    /// pane get their original name restored.
    fn update_all_tab_names(&mut self) {
        let mut affected_tabs: BTreeSet<usize> = BTreeSet::new();
        // Tabs with active Claude panes.
        for (&pane_id, _) in &self.pane_states {
            if let Some(&tab_pos) = self.pane_to_tab_position.get(&pane_id) {
                affected_tabs.insert(tab_pos);
            }
        }
        // Tabs we previously tracked (may need pill removed).
        for &tab_pos in self.original_tab_names.keys() {
            affected_tabs.insert(tab_pos);
        }
        for &tab_pos in &affected_tabs {
            self.update_tab_name(tab_pos);
        }
    }

    /// Update a single tab's name based on its aggregate pane state.
    fn update_tab_name(&mut self, tab_position: usize) {
        let original = match self.original_tab_names.get(&tab_position) {
            Some(name) => name,
            None => return,
        };

        let desired = match self.aggregate_tab_state(tab_position) {
            Some(state) => format!("{} {}", state.pill(), original),
            None => original.clone(),
        };

        // Guard: skip if the tab already shows the desired name.
        if self.tab_names.get(&tab_position) == Some(&desired) {
            self.desired_tab_names.insert(tab_position, desired);
            return;
        }

        // Guard: skip if we already asked rename_tab() for this exact name.
        if self.desired_tab_names.get(&tab_position) == Some(&desired) {
            return;
        }

        self.desired_tab_names.insert(tab_position, desired.clone());
        self.tab_names.insert(tab_position, desired.clone());
        // rename_tab expects 1-based tab index, but tab_position is 0-based.
        rename_tab(tab_position as u32 + 1, &desired);
    }
}

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
        subscribe(&[
            EventType::TabUpdate,
            EventType::PaneUpdate,
            EventType::PermissionRequestResult,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::TabUpdate(tabs) => {
                self.tab_names.clear();
                let mut valid_positions: BTreeSet<usize> = BTreeSet::new();

                for tab in &tabs {
                    self.tab_names.insert(tab.position, tab.name.clone());
                    valid_positions.insert(tab.position);

                    // Only update original name for tabs we're already tracking
                    // (i.e., tabs that have or had Claude sessions).
                    if self.original_tab_names.contains_key(&tab.position) {
                        let clean = Self::strip_pill(&tab.name).to_string();
                        self.original_tab_names.insert(tab.position, clean);
                    }
                }

                // Clean up entries for tabs that no longer exist.
                self.original_tab_names
                    .retain(|pos, _| valid_positions.contains(pos));
                self.desired_tab_names
                    .retain(|pos, _| valid_positions.contains(pos));

                // Note: pane_to_tab_position may now reference old tab positions.
                // Pipe messages arriving before PaneUpdate will harmlessly skip
                // any pane whose position lookup fails.
            }
            Event::PaneUpdate(manifest) => {
                self.pane_to_tab_position.clear();
                for (&tab_position, panes) in &manifest.panes {
                    for pane in panes {
                        if pane.is_plugin || pane.is_suppressed {
                            continue;
                        }
                        self.pane_to_tab_position.insert(pane.id, tab_position);
                    }
                }

                if !self.pane_states.is_empty() {
                    // Capture original tab names for any newly-mapped panes.
                    for (&pane_id, _) in &self.pane_states {
                        if let Some(&tab_pos) = self.pane_to_tab_position.get(&pane_id) {
                            if !self.original_tab_names.contains_key(&tab_pos) {
                                if let Some(current_name) = self.tab_names.get(&tab_pos) {
                                    let clean = Self::strip_pill(current_name).to_string();
                                    self.original_tab_names.insert(tab_pos, clean);
                                }
                            }
                        }
                    }
                    self.update_all_tab_names();
                }
            }
            Event::PermissionRequestResult(_) => {}
            _ => {}
        }
        false
    }

    fn pipe(&mut self, pipe_message: PipeMessage) -> bool {
        // Unblock the CLI pipe so `zellij pipe` returns immediately.
        unblock_cli_pipe_input(&pipe_message.name);

        if pipe_message.name != "claude-status" {
            return false;
        }

        let payload_str = match &pipe_message.payload {
            Some(p) => p,
            None => return false,
        };

        let payload: StatusPayload = match serde_json::from_str(payload_str) {
            Ok(p) => p,
            Err(_) => return false,
        };

        let pane_id: u32 = match payload.pane_id.parse() {
            Ok(id) => id,
            Err(_) => return false,
        };

        match payload.state.as_str() {
            "exit" => {
                self.pane_states.remove(&pane_id);
                if let Some(&tab_pos) = self.pane_to_tab_position.get(&pane_id) {
                    let has_remaining = self.pane_states.keys().any(|&pid| {
                        self.pane_to_tab_position.get(&pid) == Some(&tab_pos)
                    });
                    if has_remaining {
                        self.update_tab_name(tab_pos);
                    } else {
                        // Restore original name and stop tracking.
                        if let Some(original) = self.original_tab_names.get(&tab_pos) {
                            let original = original.clone();
                            self.desired_tab_names.insert(tab_pos, original.clone());
                            self.tab_names.insert(tab_pos, original.clone());
                            rename_tab(tab_pos as u32 + 1, &original);
                        }
                    }
                }
            }
            state_str => {
                let state = match state_str {
                    "working" => PaneState::Working,
                    "waiting" => PaneState::Waiting,
                    "idle" => PaneState::Idle,
                    _ => return false,
                };

                self.pane_states.insert(pane_id, state);

                if let Some(&tab_pos) = self.pane_to_tab_position.get(&pane_id) {
                    // Capture the original tab name on first track.
                    if !self.original_tab_names.contains_key(&tab_pos) {
                        if let Some(current_name) = self.tab_names.get(&tab_pos) {
                            let clean = Self::strip_pill(current_name).to_string();
                            self.original_tab_names.insert(tab_pos, clean);
                        }
                    }
                    self.update_tab_name(tab_pos);
                }
            }
        }

        false
    }
}

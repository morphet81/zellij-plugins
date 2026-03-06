use serde::Deserialize;
use std::collections::BTreeMap;
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
}

impl State {
    /// Strip any pill prefix we may have added.
    fn strip_pill(name: &str) -> &str {
        for pill in [PILL_WORKING, PILL_WAITING, PILL_IDLE] {
            if let Some(rest) = name.strip_prefix(pill) {
                if let Some(rest) = rest.strip_prefix(' ') {
                    return rest;
                }
            }
        }
        name
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

    /// Recompute and apply tab names for all tabs that have tracked panes
    /// or had tracked panes (need restoration).
    fn update_all_tab_names(&self) {
        let mut affected_tabs: BTreeMap<usize, ()> = BTreeMap::new();
        for (&pane_id, _) in &self.pane_states {
            if let Some(&tab_pos) = self.pane_to_tab_position.get(&pane_id) {
                affected_tabs.insert(tab_pos, ());
            }
        }
        for (&tab_pos, _) in &self.original_tab_names {
            affected_tabs.insert(tab_pos, ());
        }
        for &tab_pos in affected_tabs.keys() {
            self.update_tab_name(tab_pos);
        }
    }

    /// Update a single tab's name based on its aggregate pane state.
    fn update_tab_name(&self, tab_position: usize) {
        let original = match self.original_tab_names.get(&tab_position) {
            Some(name) => name,
            None => return,
        };

        let desired = match self.aggregate_tab_state(tab_position) {
            Some(state) => format!("{} {}", state.pill(), original),
            None => original.clone(),
        };

        // Only rename if the current name differs from desired.
        if let Some(current) = self.tab_names.get(&tab_position) {
            if *current == desired {
                return;
            }
        }

        rename_tab(tab_position as u32, &desired);
    }

    /// Record the original tab name for a tab position if not already captured.
    fn capture_original_name(&mut self, tab_position: usize) {
        if self.original_tab_names.contains_key(&tab_position) {
            return;
        }
        if let Some(current_name) = self.tab_names.get(&tab_position) {
            let clean = Self::strip_pill(current_name).to_string();
            self.original_tab_names.insert(tab_position, clean);
        }
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
                for tab in &tabs {
                    self.tab_names.insert(tab.position, tab.name.clone());
                }
                self.update_all_tab_names();
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
                self.update_all_tab_names();
            }
            Event::PermissionRequestResult(_) => {}
            _ => {}
        }
        false
    }

    fn pipe(&mut self, pipe_message: PipeMessage) -> bool {
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
                        if let Some(original) = self.original_tab_names.remove(&tab_pos) {
                            rename_tab(tab_pos as u32, &original);
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

                // Capture original tab name on first interaction with this tab.
                if let Some(&tab_pos) = self.pane_to_tab_position.get(&pane_id) {
                    self.capture_original_name(tab_pos);
                }

                self.pane_states.insert(pane_id, state);

                if let Some(&tab_pos) = self.pane_to_tab_position.get(&pane_id) {
                    self.update_tab_name(tab_pos);
                }
            }
        }

        false
    }
}

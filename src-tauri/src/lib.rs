mod codex;
mod config;
mod model;
mod parser;
mod pricing;
mod store;

use model::Dashboard;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::WindowEvent;
use tauri::{
    menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager,
};
use tauri_plugin_autostart::ManagerExt;

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn refresh(app: &tauri::AppHandle) {
    let dash = parser::build_dashboard();
    if let Some(tray) = app.tray_by_id("main") {
        let label = fmt_tokens_m(dash.today_tokens);
        let _ = tray.set_title(Some(label.clone()));
        let _ = tray.set_tooltip(Some(format!("CraftMeter · today {}", label)));
    }
    check_milestones(app, &dash);
    let _ = app.emit("dashboard-updated", &dash);
}

#[derive(Clone, serde::Serialize, serde::Deserialize)]
struct MilestoneState {
    week_id: String,
    week_floor: i64,
    month_id: String,
    month_floor: i64,
}

struct Celebration {
    state: std::sync::Mutex<Option<MilestoneState>>,
    active: AtomicBool,
}

fn milestones_path() -> Option<std::path::PathBuf> {
    let dir = dirs::data_dir()?.join("craftmeter");
    let _ = std::fs::create_dir_all(&dir);
    Some(dir.join("milestones.json"))
}

fn load_milestones() -> Option<MilestoneState> {
    let t = std::fs::read_to_string(milestones_path()?).ok()?;
    serde_json::from_str(&t).ok()
}

fn save_milestones(m: &MilestoneState) {
    if let Some(p) = milestones_path() {
        if let Ok(t) = serde_json::to_string(m) {
            let _ = std::fs::write(p, t);
        }
    }
}

fn autostart_pref_path() -> Option<std::path::PathBuf> {
    let dir = dirs::data_dir()?.join("craftmeter");
    let _ = std::fs::create_dir_all(&dir);
    Some(dir.join("autostart.json"))
}

fn load_autostart_pref() -> Option<bool> {
    let t = std::fs::read_to_string(autostart_pref_path()?).ok()?;
    serde_json::from_str(&t).ok()
}

fn save_autostart_pref(on: bool) {
    if let Some(p) = autostart_pref_path() {
        if let Ok(t) = serde_json::to_string(&on) {
            let _ = std::fs::write(p, t);
        }
    }
}

fn reconcile_autostart(app: &tauri::AppHandle) -> bool {
    let pref = match load_autostart_pref() {
        Some(p) => p,
        None => {
            save_autostart_pref(true);
            true
        }
    };
    let mgr = app.autolaunch();
    let cur = mgr.is_enabled().unwrap_or(false);
    if pref && !cur {
        let _ = mgr.enable();
    } else if !pref && cur {
        let _ = mgr.disable();
    }
    pref
}

fn period_ids() -> (String, String) {
    use chrono::Datelike;
    let d = chrono::Local::now().date_naive();
    let iso = d.iso_week();
    (
        format!("{}-W{:02}", iso.year(), iso.week()),
        format!("{}-{:02}", d.year(), d.month()),
    )
}

fn milestone_fire(prev: Option<&MilestoneState>, cur: &MilestoneState) -> bool {
    match prev {
        None => false,
        Some(p) => {
            (p.week_id == cur.week_id && cur.week_floor > p.week_floor)
                || (p.month_id == cur.month_id && cur.month_floor > p.month_floor)
        }
    }
}

fn check_milestones(app: &tauri::AppHandle, dash: &Dashboard) {
    let Some(state) = app.try_state::<Celebration>() else {
        return;
    };
    let (week_id, month_id) = period_ids();
    let cur = MilestoneState {
        week_id,
        week_floor: (dash.week.metrics.total_tokens / 100.0).floor() as i64,
        month_id,
        month_floor: (dash.month.metrics.total_tokens / 100.0).floor() as i64,
    };

    let mut g = state.state.lock().unwrap();
    let fire = milestone_fire(g.as_ref(), &cur);
    let mut next = cur.clone();
    if let Some(prev) = g.as_ref() {
        if prev.week_id == next.week_id && prev.week_floor > next.week_floor {
            next.week_floor = prev.week_floor;
        }
        if prev.month_id == next.month_id && prev.month_floor > next.month_floor {
            next.month_floor = prev.month_floor;
        }
    }
    *g = Some(next.clone());
    save_milestones(&next);
    drop(g);
    if fire {
        celebrate(app);
    }
}

fn celebrate(app: &tauri::AppHandle) {
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || show_celebration(&handle));
}

fn show_celebration(app: &tauri::AppHandle) {
    let Some(state) = app.try_state::<Celebration>() else {
        return;
    };
    if state.active.swap(true, Ordering::SeqCst) {
        return;
    }

    let (pos, size) = match app.primary_monitor() {
        Ok(Some(m)) => (*m.position(), *m.size()),
        _ => {
            state.active.store(false, Ordering::SeqCst);
            return;
        }
    };

    let win = match app.get_webview_window("confetti") {
        Some(w) => w,
        None => {
            match tauri::WebviewWindowBuilder::new(
                app,
                "confetti",
                tauri::WebviewUrl::App("confetti.html".into()),
            )
            .title("CraftMeter Celebration")
            .inner_size(size.width as f64, size.height as f64)
            .decorations(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .focused(false)
            .resizable(false)
            .visible(false)
            .build()
            {
                Ok(w) => w,
                Err(_) => {
                    state.active.store(false, Ordering::SeqCst);
                    return;
                }
            }
        }
    };

    let _ = win.set_position(pos);
    let _ = win.set_size(size);
    let _ = win.set_ignore_cursor_events(true);
    let _ = win.eval("window.__burst&&window.__burst()");
    let _ = win.show();

    let app2 = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(4200));
        let app3 = app2.clone();
        let _ = app2.run_on_main_thread(move || {
            if let Some(w) = app3.get_webview_window("confetti") {
                let _ = w.hide();
            }
            if let Some(st) = app3.try_state::<Celebration>() {
                st.active.store(false, Ordering::SeqCst);
            }
        });
    });
}

struct TrayAnchor(std::sync::Mutex<Option<(f64, f64, f64, f64)>>);
struct DragGuard(AtomicI64);

#[tauri::command]
fn begin_drag(window: tauri::Window) -> Result<(), String> {
    if let Some(g) = window.try_state::<DragGuard>() {
        g.0.store(now_ms(), Ordering::Relaxed);
    }
    window.start_dragging().map_err(|e| e.to_string())
}

fn popover_pos_path() -> Option<std::path::PathBuf> {
    let dir = dirs::data_dir()?.join("craftmeter");
    let _ = std::fs::create_dir_all(&dir);
    Some(dir.join("popover_pos.json"))
}

#[cfg(not(target_os = "macos"))]
fn load_popover_pos() -> Option<(i32, i32)> {
    let t = std::fs::read_to_string(popover_pos_path()?).ok()?;
    serde_json::from_str(&t).ok()
}

fn save_popover_pos(x: i32, y: i32) {
    if let Some(p) = popover_pos_path() {
        if let Ok(t) = serde_json::to_string(&(x, y)) {
            let _ = std::fs::write(p, t);
        }
    }
}

fn position_popover(app: &tauri::AppHandle) {
    const POPOVER_W: f64 = 420.0;
    const POPOVER_H: f64 = 660.0;
    const MARGIN: f64 = 12.0;

    let Some(w) = app.get_webview_window("main") else {
        return;
    };
    let fit = |scale: f64| {
        let _ = w.set_size(tauri::PhysicalSize::new(
            (POPOVER_W * scale).round() as u32,
            (POPOVER_H * scale).round() as u32,
        ));
    };

    #[cfg(not(target_os = "macos"))]
    if let Some((sx, sy)) = load_popover_pos() {
        if let Ok(Some(m)) = w.monitor_from_point(sx as f64 + 20.0, sy as f64 + 20.0) {
            let _ = w.set_position(tauri::PhysicalPosition::new(sx, sy));
            fit(m.scale_factor());
            return;
        }
    }

    let anchor = app
        .try_state::<TrayAnchor>()
        .and_then(|s| *s.0.lock().unwrap());

    #[cfg(target_os = "macos")]
    if let Some((tx, ty, tw, th)) = anchor {
        let monitor = w
            .monitor_from_point(tx, ty)
            .ok()
            .flatten()
            .or_else(|| w.current_monitor().ok().flatten())
            .or_else(|| app.primary_monitor().ok().flatten());
        if let Some(m) = monitor {
            let scale = m.scale_factor();
            fit(scale);
            let win_w = POPOVER_W * scale;
            let x = tx + tw / 2.0 - win_w / 2.0;
            let y = ty + th;
            let _ = w.set_position(tauri::PhysicalPosition::new(
                x.round() as i32,
                y.round() as i32,
            ));
            return;
        }
    }

    let monitor = anchor
        .and_then(|(tx, ty, _, _)| w.monitor_from_point(tx, ty).ok().flatten())
        .or_else(|| w.current_monitor().ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());

    if let Some(m) = monitor {
        let area = m.work_area();
        let scale = m.scale_factor();
        let margin = MARGIN * scale;
        let win_w = POPOVER_W * scale;
        let right = area.position.x as f64 + area.size.width as f64;
        let x = right - win_w - margin;
        let y = area.position.y as f64 + margin;
        let _ = w.set_position(tauri::PhysicalPosition::new(x as i32, y as i32));
        fit(scale);
    }
}

fn show_popover(app: &tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        position_popover(app);
        let _ = w.show();
        let _ = w.set_focus();
        let _ = w.eval(
            "(function(){var e=document.querySelector('.om-scroll');if(e){e.scrollTop=0;}else{window.scrollTo(0,0);}})()",
        );
    }
}

#[tauri::command]
async fn get_dashboard(
    app: tauri::AppHandle,
    day_offset: Option<i32>,
    week_offset: Option<i32>,
    month_offset: Option<i32>,
) -> Dashboard {
    let offsets = parser::PeriodOffsets {
        day: day_offset.unwrap_or(0),
        week: week_offset.unwrap_or(0),
        month: month_offset.unwrap_or(0),
    };
    let dash =
        tauri::async_runtime::spawn_blocking(move || parser::build_dashboard_with_offsets(offsets))
            .await
            .unwrap_or_else(|_| parser::build_dashboard_with_offsets(offsets));
    if let Some(tray) = app.tray_by_id("main") {
        let label = fmt_tokens_m(dash.today_tokens);
        let _ = tray.set_title(Some(label.clone()));
        let _ = tray.set_tooltip(Some(format!("CraftMeter · today {}", label)));
    }
    check_milestones(&app, &dash);
    dash
}

#[tauri::command]
fn save_screenshot(data_url: String) -> Result<String, String> {
    use base64::Engine;
    let body = data_url
        .strip_prefix("data:image/png;base64,")
        .ok_or_else(|| "expected a data:image/png;base64,... URL".to_string())?;
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(body.trim())
        .map_err(|e| format!("invalid base64: {e}"))?;

    let dir =
        dirs::desktop_dir().ok_or_else(|| "could not resolve the Desktop directory".to_string())?;
    let stamp = chrono::Local::now().format("CraftMeter %Y-%m-%d at %H.%M.%S.png");
    let path = dir.join(stamp.to_string());

    std::fs::write(&path, &bytes).map_err(|e| format!("failed to write file: {e}"))?;
    Ok(path.to_string_lossy().into_owned())
}

pub fn dashboard_json() -> String {
    serde_json::to_string_pretty(&parser::build_dashboard()).unwrap_or_default()
}

fn fmt_tokens_m(m: f64) -> String {
    if m >= 1.0 {
        format!("{:.2}M", m)
    } else {
        let k = (m * 1000.0).round() as i64;
        if k <= 0 {
            "Ready".to_string()
        } else {
            format!("{k}K")
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let last_hidden = Arc::new(AtomicI64::new(0));

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            show_popover(app);
        }))
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .invoke_handler(tauri::generate_handler![
            get_dashboard,
            save_screenshot,
            begin_drag
        ])
        .setup(move |app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            app.manage(TrayAnchor(std::sync::Mutex::new(None)));
            app.manage(DragGuard(AtomicI64::new(0)));
            app.manage(Celebration {
                state: std::sync::Mutex::new(load_milestones()),
                active: AtomicBool::new(false),
            });

            let autostart_on = reconcile_autostart(app.handle());

            if let Some(win) = app.get_webview_window("main") {
                let w = win.clone();
                let lh = last_hidden.clone();
                win.on_window_event(move |e| match e {
                    WindowEvent::CloseRequested { api, .. } => {
                        api.prevent_close();
                        lh.store(now_ms(), Ordering::Relaxed);
                        if let Ok(p) = w.outer_position() {
                            save_popover_pos(p.x, p.y);
                        }
                        let _ = w.hide();
                    }
                    WindowEvent::Focused(false) => {
                        if !w.is_visible().unwrap_or(false) {
                            return;
                        }
                        let dragging = w
                            .try_state::<DragGuard>()
                            .map(|g| now_ms() - g.0.load(Ordering::Relaxed) < 700)
                            .unwrap_or(false);
                        if dragging {
                            return;
                        }
                        lh.store(now_ms(), Ordering::Relaxed);
                        if let Ok(p) = w.outer_position() {
                            save_popover_pos(p.x, p.y);
                        }
                        let _ = w.hide();
                    }
                    _ => {}
                });
            }

            let dash = parser::build_dashboard();
            let label = fmt_tokens_m(dash.today_tokens);

            let open_i = MenuItem::with_id(app, "open", "Open CraftMeter", true, None::<&str>)?;
            let refresh_i = MenuItem::with_id(app, "refresh", "Refresh", true, None::<&str>)?;
            let autostart_i = CheckMenuItem::with_id(
                app,
                "autostart",
                "Launch at Login",
                true,
                autostart_on,
                None::<&str>,
            )?;
            let quit_i = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(
                app,
                &[
                    &open_i,
                    &refresh_i,
                    &PredefinedMenuItem::separator(app)?,
                    &autostart_i,
                    &PredefinedMenuItem::separator(app)?,
                    &quit_i,
                ],
            )?;

            let lh_tray = last_hidden.clone();
            let _tray = TrayIconBuilder::with_id("main")
                .icon(tauri::include_image!("icons/tray-icon.png"))
                .icon_as_template(true)
                .title(&label)
                .tooltip(format!("CraftMeter · today {}", label))
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_tray_icon_event(move |tray, event| {
                    let app = tray.app_handle();
                    if let TrayIconEvent::Click { rect, .. } = &event {
                        if let Some(anchor) = app.try_state::<TrayAnchor>() {
                            let p = rect.position.to_physical::<f64>(1.0);
                            let s = rect.size.to_physical::<f64>(1.0);
                            *anchor.0.lock().unwrap() = Some((p.x, p.y, s.width, s.height));
                        }
                    }
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let just_hidden = now_ms() - lh_tray.load(Ordering::Relaxed) < 250;
                        let visible = app
                            .get_webview_window("main")
                            .and_then(|w| w.is_visible().ok())
                            .unwrap_or(false);
                        if visible {
                            if let Some(w) = app.get_webview_window("main") {
                                let _ = w.hide();
                            }
                        } else if !just_hidden {
                            show_popover(app);
                        }
                    }
                })
                .on_menu_event(move |app, event| match event.id.as_ref() {
                    "open" => show_popover(app),
                    "refresh" => refresh(app),
                    "autostart" => {
                        let mgr = app.autolaunch();
                        let enabled = mgr.is_enabled().unwrap_or(false);
                        let _ = if enabled { mgr.disable() } else { mgr.enable() };
                        let now_on = mgr.is_enabled().unwrap_or(!enabled);
                        let _ = autostart_i.set_checked(now_on);
                        save_autostart_pref(now_on);
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .build(app)?;

            std::thread::spawn(|| {
                pricing::Pricing::reload_shared();
                loop {
                    std::thread::sleep(Duration::from_secs(24 * 60 * 60));
                    pricing::Pricing::reload_shared();
                }
            });

            let handle = app.handle().clone();
            std::thread::spawn(move || loop {
                std::thread::sleep(Duration::from_secs(30));
                refresh(&handle);
            });

            let watch_roots = dirs::home_dir().map(|h| {
                vec![
                    h.join(".claude").join("projects"),
                    h.join(".codex").join("sessions"),
                ]
            });
            if let Some(roots) = watch_roots {
                let handle = app.handle().clone();
                std::thread::spawn(move || {
                    use notify::{RecursiveMode, Watcher};
                    let (tx, rx) = std::sync::mpsc::channel();
                    let mut watcher = match notify::recommended_watcher(
                        move |res: notify::Result<notify::Event>| {
                            if res.is_ok() {
                                let _ = tx.send(());
                            }
                        },
                    ) {
                        Ok(w) => w,
                        Err(_) => return,
                    };
                    let mut watching = false;
                    for root in roots {
                        let _ = std::fs::create_dir_all(&root);
                        if watcher.watch(&root, RecursiveMode::Recursive).is_ok() {
                            watching = true;
                        }
                    }
                    if !watching {
                        return;
                    }
                    while rx.recv().is_ok() {
                        while rx.recv_timeout(Duration::from_millis(400)).is_ok() {}
                        refresh(&handle);
                    }
                });
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ms(wk: &str, wf: i64, mo: &str, mf: i64) -> MilestoneState {
        MilestoneState {
            week_id: wk.into(),
            week_floor: wf,
            month_id: mo.into(),
            month_floor: mf,
        }
    }

    #[test]
    fn first_ever_observation_baselines_without_firing() {
        assert!(!milestone_fire(None, &ms("2026-W24", 3, "2026-06", 3)));
    }

    #[test]
    fn no_change_does_not_fire() {
        let prev = ms("2026-W24", 1, "2026-06", 3);
        assert!(!milestone_fire(
            Some(&prev),
            &ms("2026-W24", 1, "2026-06", 3)
        ));
    }

    #[test]
    fn month_crossing_fires() {
        let prev = ms("2026-W24", 1, "2026-06", 3);
        assert!(milestone_fire(
            Some(&prev),
            &ms("2026-W24", 1, "2026-06", 4)
        ));
    }

    #[test]
    fn week_crossing_fires_even_when_month_flat() {
        let prev = ms("2026-W24", 0, "2026-06", 0);
        assert!(milestone_fire(
            Some(&prev),
            &ms("2026-W24", 1, "2026-06", 0)
        ));
    }

    #[test]
    fn multi_boundary_jump_is_a_single_fire() {
        let prev = ms("2026-W24", 1, "2026-06", 3);
        assert!(milestone_fire(
            Some(&prev),
            &ms("2026-W24", 1, "2026-06", 7)
        ));
    }

    #[test]
    fn new_month_rebaselines_silently() {
        let prev = ms("2026-W24", 1, "2026-06", 3);
        assert!(!milestone_fire(
            Some(&prev),
            &ms("2026-W27", 0, "2026-07", 0)
        ));
    }

    #[test]
    fn new_week_does_not_fire_on_reset() {
        let prev = ms("2026-W24", 2, "2026-06", 3);
        assert!(!milestone_fire(
            Some(&prev),
            &ms("2026-W25", 0, "2026-06", 3)
        ));
    }
}

use std::fs;
use std::io::{self, Write};
use std::path::Path;
use std::process::Command;
use crate::storage::Storage;

const DEFAULT_REPO: &str = "THARUN-BART/linlink";
const CURRENT_VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Debug, Clone)]
pub struct ReleaseAsset {
    pub name: String,
    pub download_url: String,
    pub size: u64,
}

#[derive(Debug, Clone)]
pub struct ReleaseInfo {
    pub tag_name: String,
    pub version: String,
    pub name: String,
    pub body: String,
    pub html_url: String,
    pub published_at: String,
    pub assets: Vec<ReleaseAsset>,
}

pub async fn run_update(
    check_only: bool,
    force: bool,
    download_apk: bool,
    non_interactive: bool,
    repo: &str,
) {
    let repo_name = if repo.is_empty() { DEFAULT_REPO } else { repo };

    println!();
    println!("  ┌────────────────────────────────────────────────────────┐");
    println!("  │  🚀 LinLink Online Software Updater                    │");
    println!("  └────────────────────────────────────────────────────────┘");
    println!("    Current Version: \x1b[1;36mv{}\x1b[0m", CURRENT_VERSION);
    println!("    Online Source:   https://github.com/{}", repo_name);
    println!();

    print!("  🔍 Checking online repository for updates... ");
    let _ = io::stdout().flush();

    let release_res = fetch_latest_release(repo_name).await;

    let release = match release_res {
        Ok(rel) => {
            println!("\x1b[1;32mDone\x1b[0m\n");
            rel
        }
        Err(err) => {
            println!("\x1b[1;31mFailed\x1b[0m\n");
            println!("  ❌ Could not check for updates online: {}", err);
            println!("     Please check your internet connection or repository settings.\n");
            return;
        }
    };

    let is_newer = is_version_newer(CURRENT_VERSION, &release.version);

    println!("  ┌────────────────────────────────────────────────────────┐");
    println!("  │  Online Release: \x1b[1;32m{:<37}\x1b[0m │", release.tag_name);
    if !release.published_at.is_empty() {
        println!("  │  Published At:   {:<37} │", release.published_at);
    }
    println!("  │  URL:            {:<37} │", release.html_url);
    println!("  └────────────────────────────────────────────────────────┘");

    if !release.body.is_empty() {
        println!("\n  📋 \x1b[1mRelease Highlights / Changelog:\x1b[0m");
        for line in release.body.lines().take(10) {
            println!("     {}", line);
        }
        if release.body.lines().count() > 10 {
            println!("     ... (see {} for full release notes)", release.html_url);
        }
        println!();
    }

    if check_only {
        if is_newer {
            println!(
                "  ✨ \x1b[1;32mA new update is available!\x1b[0m (\x1b[1;33mv{}\x1b[0m -> \x1b[1;32m{}\x1b[0m)",
                CURRENT_VERSION, release.tag_name
            );
            println!("     Run `linlink update` to download and install.\n");
        } else {
            println!(
                "  ✨ \x1b[1;32mYou are already running the latest version\x1b[0m (v{}).\n",
                CURRENT_VERSION
            );
        }
        return;
    }

    if download_apk {
        handle_apk_download(&release, non_interactive).await;
        return;
    }

    if !is_newer && !force {
        println!(
            "  ✨ \x1b[1;32mYou are already running the latest version\x1b[0m (v{}).",
            CURRENT_VERSION
        );
        println!("     Use `linlink update --force` to force reinstall, or `linlink update --apk` for Android.\n");
        return;
    }

    if is_newer {
        println!(
            "  🎉 \x1b[1;32mNew version available:\x1b[0m \x1b[1;33mv{}\x1b[0m ➔ \x1b[1;32m{}\x1b[0m",
            CURRENT_VERSION, release.tag_name
        );
    } else {
        println!("  ⚠️  Force update requested for current version v{}.", CURRENT_VERSION);
    }

    if !non_interactive {
        print!("\n  Do you want to download and install this update now? [Y/n] ");
        let _ = io::stdout().flush();
        let mut input = String::new();
        if io::stdin().read_line(&mut input).is_ok() {
            let trimmed = input.trim().to_lowercase();
            if !trimmed.is_empty() && trimmed != "y" && trimmed != "yes" {
                println!("\n  Update cancelled.\n");
                return;
            }
        }
    }

    println!();
    perform_linux_binary_update(&release).await;
}

/// Download Android APK from online release
async fn handle_apk_download(release: &ReleaseInfo, non_interactive: bool) {
    let apk_asset = release
        .assets
        .iter()
        .find(|a| a.name.ends_with(".apk") || a.name.contains("android"));

    let target_dir = Storage::transfers_dir();
    let _ = fs::create_dir_all(&target_dir);

    let default_name = format!("linlink-{}.apk", release.tag_name.trim_start_matches('v'));
    let download_name = apk_asset
        .map(|a| a.name.clone())
        .unwrap_or(default_name);
    let output_path = target_dir.join(&download_name);

    println!("  📱 Downloading Android APK: \x1b[1m{}\x1b[0m", download_name);
    println!("     Destination: {}", output_path.display());

    let download_url = if let Some(asset) = apk_asset {
        asset.download_url.clone()
    } else {
        // Fallback to standard release asset URL format
        format!(
            "https://github.com/{}/releases/download/{}/app-release.apk",
            DEFAULT_REPO, release.tag_name
        )
    };

    if !download_file_with_progress(&download_url, &output_path).await {
        println!("  ❌ Failed to download Android APK from {}", download_url);
        println!("     You can download it manually from: {}\n", release.html_url);
        return;
    }

    println!("\n  ✅ \x1b[1;32mAndroid APK successfully downloaded!\x1b[0m");
    println!("     Saved to: {}\n", output_path.display());

    // Check if phone is currently linked and prompt to send it
    if let Some(dev) = crate::device::DeviceManager::get_current_device() {
        if dev.state == "connected" {
            let send_prompt = if non_interactive {
                false
            } else {
                print!("  📱 Send this update APK directly to connected phone '{}'? [Y/n] ", dev.name);
                let _ = io::stdout().flush();
                let mut input = String::new();
                if io::stdin().read_line(&mut input).is_ok() {
                    let t = input.trim().to_lowercase();
                    t.is_empty() || t == "y" || t == "yes"
                } else {
                    false
                }
            };

            if send_prompt {
                send_apk_to_phone(&output_path, &dev).await;
            }
        }
    }
}

async fn send_apk_to_phone(apk_path: &Path, dev: &crate::device::CurrentDevice) {
    let client_ip = dev.client_ip.clone().unwrap_or_else(|| "127.0.0.1".into());
    let agent_port = dev.agent_port.unwrap_or(7879);
    let token = dev.token.clone();
    let filename = apk_path.file_name().unwrap_or_default().to_string_lossy().to_string();

    println!("  ⬆️  Sending APK to Android device ({}:{})...", client_ip, agent_port);

    if let Ok(bytes) = fs::read(apk_path) {
        let base_url = format!("http://{}:{}", client_ip, agent_port);
        let url = format!(
            "{}/fs/upload?token={}&path=/storage/emulated/0/Download&filename={}",
            base_url,
            token,
            filename
        );
        let client = crate::cli::shell::reqwest_compat::Client::new();
        match client.post(&url).body(bytes).send().await {
            Ok(res) if res.status() == 200 => {
                println!("  ✅ APK sent to phone's Download folder: /storage/emulated/0/Download/{}", filename);
                println!("     You can open and install it directly from your phone's notification or file manager.\n");
            }
            _ => {
                println!("  ⚠️  Could not auto-transfer APK to phone. Please copy {} manually.\n", apk_path.display());
            }
        }
    }
}

/// Download and perform atomic self-replacement of the Linux companion binary
async fn perform_linux_binary_update(release: &ReleaseInfo) {
    let current_exe = match std::env::current_exe() {
        Ok(path) => path,
        Err(e) => {
            println!("  ❌ Could not determine current executable path: {}", e);
            return;
        }
    };

    println!("  🎯 Target executable: {}", current_exe.display());

    // Look for a Linux binary in release assets
    let linux_asset = release.assets.iter().find(|a| {
        let n = a.name.to_lowercase();
        (n.contains("linux") || n.contains("x86_64") || n == "linlink") && !n.ends_with(".apk")
    });

    let temp_dir = std::env::temp_dir().join("linlink_update");
    let _ = fs::create_dir_all(&temp_dir);
    let temp_bin_path = temp_dir.join("linlink_new");

    let download_url = if let Some(asset) = linux_asset {
        asset.download_url.clone()
    } else {
        // Fallback to standard release asset binary URL
        format!(
            "https://github.com/{}/releases/download/{}/linlink-linux-x86_64",
            DEFAULT_REPO, release.tag_name
        )
    };

    println!("  ⬇️  Downloading updated binary from GitHub...");
    if !download_file_with_progress(&download_url, &temp_bin_path).await {
        // Fallback: If direct binary asset is not attached (e.g. tag-based source), offer git / cargo build
        println!("  ⚠️  Direct binary download failed. Checking for local git repository source...");
        if try_git_source_update() {
            return;
        }

        println!("  ❌ Could not download binary from {}", download_url);
        println!("     Please download the latest release manually from: {}\n", release.html_url);
        return;
    }

    // Set executable permissions on Unix
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&temp_bin_path).unwrap().permissions();
        perms.set_mode(0o755);
        let _ = fs::set_permissions(&temp_bin_path, perms);
    }

    // Verify the downloaded binary works
    print!("  🧪 Verifying downloaded binary... ");
    let _ = io::stdout().flush();
    let verify_output = Command::new(&temp_bin_path).arg("--version").output();

    match verify_output {
        Ok(out) if out.status.success() => {
            let ver_str = String::from_utf8_lossy(&out.stdout).trim().to_string();
            println!("\x1b[1;32mOK\x1b[0m ({})", ver_str);
        }
        _ => {
            println!("\x1b[1;31mFailed\x1b[0m");
            println!("  ❌ Downloaded binary failed verification. Update aborted to preserve current installation.\n");
            let _ = fs::remove_file(&temp_bin_path);
            return;
        }
    }

    // Replace current executable atomically
    // On Linux, to replace a currently running binary without ETXTBSY:
    // 1. Rename current_exe to current_exe.old
    // 2. Copy/move new binary to current_exe
    // 3. Remove current_exe.old
    let old_backup = current_exe.with_extension("old_version");
    let _ = fs::remove_file(&old_backup);

    if let Err(e) = fs::rename(&current_exe, &old_backup) {
        println!("  ❌ Could not backup current binary: {}", e);
        return;
    }

    if let Err(e) = fs::copy(&temp_bin_path, &current_exe) {
        println!("  ❌ Could not install new binary: {}. Rolling back...", e);
        let _ = fs::rename(&old_backup, &current_exe);
        return;
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(meta) = fs::metadata(&current_exe) {
            let mut perms = meta.permissions();
            perms.set_mode(0o755);
            let _ = fs::set_permissions(&current_exe, perms);
        }
    }

    let _ = fs::remove_file(&old_backup);
    let _ = fs::remove_file(&temp_bin_path);

    println!("\n  🎉 \x1b[1;32mLinLink has been successfully updated to {}!\x1b[0m", release.tag_name);
    println!("     Run `linlink --version` or `linlink status` to test the new version.\n");
}

fn try_git_source_update() -> bool {
    // Check if current directory or workspace has git
    let git_check = Command::new("git")
        .args(["rev-parse", "--is-inside-work-tree"])
        .output();

    if let Ok(out) = git_check {
        if out.status.success() {
            println!("  📦 Detected Git repository workspace. Updating via git pull & cargo build...");
            let pull_status = Command::new("git").args(["pull", "origin", "main"]).status();
            if let Ok(ps) = pull_status {
                if ps.success() {
                    println!("  🔨 Recompiling LinLink companion...");
                    let build_status = Command::new("cargo")
                        .args(["build", "--release", "--manifest-path", "linux-companion/Cargo.toml"])
                        .status();
                    if let Ok(bs) = build_status {
                        if bs.success() {
                            println!("\n  🎉 \x1b[1;32mLinLink successfully updated and compiled from latest online source!\x1b[0m\n");
                            return true;
                        }
                    }
                }
            }
        }
    }
    false
}

/// Fetch latest release from GitHub API using curl / system tools
async fn fetch_latest_release(repo: &str) -> Result<ReleaseInfo, String> {
    let api_url = format!("https://api.github.com/repos/{}/releases/latest", repo);

    // Call curl to fetch the GitHub releases JSON
    let output = Command::new("curl")
        .args([
            "-s",
            "-L",
            "-H",
            "User-Agent: LinLink-Updater",
            "-H",
            "Accept: application/vnd.github.v3+json",
            "--connect-timeout",
            "10",
            &api_url,
        ])
        .output()
        .map_err(|e| format!("Failed to run curl: {}", e))?;

    if !output.status.success() {
        return Err("Curl request to GitHub API failed".into());
    }

    let raw_str = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&raw_str)
        .map_err(|_| "Failed to parse GitHub API response. No release found or rate limit exceeded.".to_string())?;

    if let Some(msg) = json.get("message").and_then(|m| m.as_str()) {
        if msg.contains("Not Found") {
            // If no official release yet, construct from repository tags/commits
            return fetch_latest_git_tag(repo).await;
        }
        return Err(format!("GitHub API message: {}", msg));
    }

    let tag_name = json["tag_name"].as_str().unwrap_or("v0.1.0").to_string();
    let version = tag_name.trim_start_matches('v').to_string();
    let name = json["name"].as_str().unwrap_or(&tag_name).to_string();
    let body = json["body"].as_str().unwrap_or("").to_string();
    let html_url = json["html_url"].as_str().unwrap_or("https://github.com/THARUN-BART/linlink").to_string();
    let published_at = json["published_at"].as_str().unwrap_or("").to_string();

    let mut assets = Vec::new();
    if let Some(assets_arr) = json["assets"].as_array() {
        for a in assets_arr {
            let aname = a["name"].as_str().unwrap_or("").to_string();
            let durl = a["browser_download_url"].as_str().unwrap_or("").to_string();
            let size = a["size"].as_u64().unwrap_or(0);
            if !aname.is_empty() && !durl.is_empty() {
                assets.push(ReleaseAsset {
                    name: aname,
                    download_url: durl,
                    size,
                });
            }
        }
    }

    Ok(ReleaseInfo {
        tag_name,
        version,
        name,
        body,
        html_url,
        published_at,
        assets,
    })
}

/// Fallback to fetch latest tag via GitHub tags API
async fn fetch_latest_git_tag(repo: &str) -> Result<ReleaseInfo, String> {
    let api_url = format!("https://api.github.com/repos/{}/tags", repo);
    let output = Command::new("curl")
        .args([
            "-s",
            "-L",
            "-H",
            "User-Agent: LinLink-Updater",
            "--connect-timeout",
            "10",
            &api_url,
        ])
        .output()
        .map_err(|e| format!("Curl error: {}", e))?;

    let raw_str = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&raw_str)
        .map_err(|_| "Failed to query tags".to_string())?;

    if let Some(arr) = json.as_array() {
        if let Some(first) = arr.first() {
            let tag_name = first["name"].as_str().unwrap_or("v0.1.0").to_string();
            let version = tag_name.trim_start_matches('v').to_string();
            return Ok(ReleaseInfo {
                tag_name: tag_name.clone(),
                version,
                name: format!("LinLink {}", tag_name),
                body: "Latest git release tag from online repository.".to_string(),
                html_url: format!("https://github.com/{}/tree/{}", repo, tag_name),
                published_at: "".to_string(),
                assets: Vec::new(),
            });
        }
    }

    // If repository exists but has no tags, return online repo main state
    Ok(ReleaseInfo {
        tag_name: format!("v{}", CURRENT_VERSION),
        version: CURRENT_VERSION.to_string(),
        name: format!("LinLink v{}", CURRENT_VERSION),
        body: "Latest version from GitHub repository.".to_string(),
        html_url: format!("https://github.com/{}", repo),
        published_at: "".to_string(),
        assets: Vec::new(),
    })
}

/// Download a file with progress output using curl
async fn download_file_with_progress(url: &str, output_path: &Path) -> bool {
    print!("     Downloading from {} ...\n", url);
    let status = Command::new("curl")
        .args([
            "-L",
            "--progress-bar",
            "-o",
            output_path.to_str().unwrap_or("download"),
            url,
        ])
        .status();

    match status {
        Ok(s) => s.success() && output_path.exists() && fs::metadata(output_path).map(|m| m.len() > 0).unwrap_or(false),
        Err(_) => false,
    }
}

/// Compare two semver-like version strings
pub fn is_version_newer(current: &str, candidate: &str) -> bool {
    let parse_nums = |v: &str| -> Vec<u32> {
        v.trim_start_matches('v')
            .split('.')
            .filter_map(|s| s.split('-').next().and_then(|num| num.parse::<u32>().ok()))
            .collect()
    };

    let curr_nums = parse_nums(current);
    let cand_nums = parse_nums(candidate);

    for (c, cand) in curr_nums.iter().zip(cand_nums.iter()) {
        if cand > c {
            return true;
        } else if cand < c {
            return false;
        }
    }

    cand_nums.len() > curr_nums.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_comparison() {
        assert!(is_version_newer("0.1.0", "0.2.0"));
        assert!(is_version_newer("0.1.0", "1.0.0"));
        assert!(is_version_newer("1.0.0", "1.0.1"));
        assert!(is_version_newer("0.1.0", "v0.1.1"));
        assert!(!is_version_newer("1.0.0", "1.0.0"));
        assert!(!is_version_newer("1.2.0", "1.1.9"));
        assert!(!is_version_newer("2.0.0", "1.9.9"));
    }
}

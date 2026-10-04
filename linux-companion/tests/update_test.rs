use linux_companion::cli::update::is_version_newer;

#[test]
fn test_version_semver_checks() {
    assert!(is_version_newer("0.1.0", "0.2.0"));
    assert!(is_version_newer("0.1.0", "v0.1.1"));
    assert!(is_version_newer("0.1.0", "1.0.0"));
    assert!(!is_version_newer("1.0.0", "1.0.0"));
    assert!(!is_version_newer("2.0.0", "1.9.9"));
    assert!(!is_version_newer("0.2.0", "0.1.9"));
}

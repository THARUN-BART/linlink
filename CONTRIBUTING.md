# Contributing to LinLink 🤝

Thank you for your interest in contributing to LinLink! We welcome bug reports, feature suggestions, documentation updates, and code contributions.

---

## 🛠 Getting Started

### 1. Fork & Clone the Repository
```bash
git clone https://github.com/THARUN-BART/linlink.git
cd linlink
```

### 2. Create a Feature Branch
Always create a new branch for your changes rather than working directly on `master`:
```bash
git checkout -b feat/your-feature-name
# or for bug fixes:
git checkout -b fix/your-bug-fix
```

---

## 💻 Development Workflow

### Flutter / Mobile Development
1. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```
2. Run static analysis and ensure 0 issues:
   ```bash
   flutter analyze
   ```
3. Run the automated test suite:
   ```bash
   flutter test
   ```

### Rust / Linux Companion Development
1. Navigate to the companion directory:
   ```bash
   cd linux-companion
   ```
2. Format code according to Rust standards:
   ```bash
   cargo fmt --all -- --check
   ```
3. Run Clippy lint checks:
   ```bash
   cargo clippy --all-targets -- -D warnings
   ```
4. Run Rust unit & integration tests:
   ```bash
   cargo test --locked
   ```

---

## 📝 Commit Guidelines

We use **Conventional Commits**:

- `feat(scope): ...` for new features
- `fix(scope): ...` for bug fixes
- `docs(scope): ...` for documentation changes
- `refactor(scope): ...` for code refactoring
- `test(scope): ...` for adding or updating tests
- `ci(scope): ...` for CI/CD workflow updates

Example:
```bash
git commit -m "feat(p2p): add batch file progress indicator"
```

---

## 🚀 Submitting a Pull Request (PR)

1. Push your branch to your fork:
   ```bash
   git push origin feat/your-feature-name
   ```
2. Open a Pull Request against the `master` branch of the main repository.
3. Provide a clear description of the changes, why they are needed, and how they were tested.
4. Ensure all CI checks (formatting, linter, and tests) pass.

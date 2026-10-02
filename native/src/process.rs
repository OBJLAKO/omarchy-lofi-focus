//! Linux pidfds pin process identity. Never signal a numeric PID from persisted data.
use std::{
    fs, io,
    os::fd::{AsRawFd, FromRawFd, OwnedFd},
    path::Path,
    thread,
    time::{Duration, Instant},
};

pub struct Process {
    pub pid: u32,
    fd: OwnedFd,
}
impl Process {
    pub fn pin(pid: u32) -> io::Result<Self> {
        let fd = unsafe { libc::syscall(libc::SYS_pidfd_open, pid as libc::pid_t, 0) } as i32;
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Self {
            pid,
            fd: unsafe { OwnedFd::from_raw_fd(fd) },
        })
    }
    pub fn try_clone(&self) -> io::Result<Self> {
        // Duplicate the pinned kernel identity, never resolve its numeric PID
        // again: the process may exit and its PID may already be reused.
        Ok(Self {
            pid: self.pid,
            fd: self.fd.try_clone()?,
        })
    }
    pub fn alive(&self) -> bool {
        let mut poll = libc::pollfd {
            fd: self.fd.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        unsafe { libc::poll(&mut poll, 1, 0) == 0 }
    }
    pub fn signal(&self, signal: i32) -> io::Result<()> {
        if unsafe {
            libc::syscall(
                libc::SYS_pidfd_send_signal,
                self.fd.as_raw_fd(),
                signal,
                std::ptr::null::<libc::siginfo_t>(),
                0,
            )
        } < 0
        {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }
    fn wait(&self, ms: i32) -> bool {
        let mut poll = libc::pollfd {
            fd: self.fd.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        unsafe { libc::poll(&mut poll, 1, ms) > 0 }
    }
    pub fn terminate(&self) {
        let _ = self.signal(libc::SIGTERM);
        if !self.wait(100) {
            let _ = self.signal(libc::SIGKILL);
            self.wait(100);
        }
    }
    pub fn terminate_tree(&self) -> io::Result<()> {
        self.terminate_tree_with_budget(64)
    }
    fn terminate_tree_with_budget(&self, budget: usize) -> io::Result<()> {
        if !self.alive() {
            return Ok(());
        }
        // Discovery is transactional: if any identity cannot be pinned/frozen,
        // roll back every SIGSTOP before killing anything. The owner can keep
        // this live tree paused and report that cancellation was refused.
        let mut children = Vec::new();
        if let Err(error) = self.freeze_children(&mut children, 0, budget) {
            for child in children.iter().rev() {
                let _ = child.signal(libc::SIGCONT);
            }
            let _ = self.signal(libc::SIGCONT);
            return Err(error);
        }
        for child in children.iter().rev() {
            let _ = child.signal(libc::SIGKILL);
        }
        let _ = self.signal(libc::SIGKILL);
        self.wait(100);
        Ok(())
    }
    fn freeze_children(
        &self,
        output: &mut Vec<Process>,
        depth: usize,
        budget: usize,
    ) -> io::Result<()> {
        if depth > budget || output.len() >= budget {
            return Err(io::Error::other("extractor tree exceeded limit"));
        }
        self.signal(libc::SIGSTOP)?;
        let deadline = Instant::now() + Duration::from_millis(200);
        while self.alive() {
            let status = fs::read_to_string(format!("/proc/{}/status", self.pid))?;
            if status.lines().any(|line| {
                line.starts_with("State:")
                    && matches!(line.split_whitespace().nth(1), Some("T" | "t"))
            }) {
                break;
            }
            if Instant::now() >= deadline {
                return Err(io::Error::other("could not freeze extractor"));
            }
            thread::sleep(Duration::from_millis(2));
        }
        let tasks = fs::read_dir(format!("/proc/{}/task", self.pid))?;
        let mut ids = std::collections::HashSet::new();
        for task in tasks {
            let task = task?;
            let text = match fs::read_to_string(task.path().join("children")) {
                Ok(text) => text,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(error),
            };
            ids.extend(
                text.split_whitespace()
                    .filter_map(|s| s.parse::<u32>().ok()),
            );
        }
        for pid in ids {
            let child = match Self::pin(pid) {
                Ok(child) => child,
                Err(error) if error.raw_os_error() == Some(libc::ESRCH) => continue,
                Err(error) => return Err(error),
            };
            let status = match fs::read_to_string(format!("/proc/{pid}/status")) {
                Ok(status) => status,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(error),
            };
            let parent = status
                .lines()
                .find(|l| l.starts_with("PPid:"))
                .and_then(|l| l.split_whitespace().nth(1))
                .and_then(|p| p.parse::<u32>().ok());
            if parent != Some(self.pid) || !self.alive() {
                continue;
            }
            // Retain the pinned identity before any operation can suspend it.
            // Preorder storage makes reverse cleanup terminate descendants first.
            output.push(Process {
                pid: child.pid,
                fd: child.fd.try_clone()?,
            });
            child.freeze_children(output, depth + 1, budget)?;
        }
        Ok(())
    }
}
pub fn matching_audio(pid: u32, socket: &Path) -> Option<Process> {
    let process = Process::pin(pid).ok()?;
    let marker = format!("--input-ipc-server={}", socket.display());
    let argv = fs::read(format!("/proc/{pid}/cmdline")).ok()?;
    if process.alive() && argv.split(|c| *c == 0).any(|arg| arg == marker.as_bytes()) {
        Some(process)
    } else {
        None
    }
}
pub fn reap_orphans(runtime: &Path) -> io::Result<()> {
    // Do this once at startup; steady playback never scans /proc.
    let prefix = format!("--input-ipc-server={}/sockets/", runtime.display());
    if let Ok(entries) = fs::read_dir("/proc") {
        for entry in entries.flatten() {
            let Some(pid) = entry
                .file_name()
                .to_str()
                .and_then(|s| s.parse::<u32>().ok())
            else {
                continue;
            };
            let Ok(argv) = fs::read(entry.path().join("cmdline")) else {
                continue;
            };
            for arg in argv.split(|c| *c == 0) {
                if arg.starts_with(prefix.as_bytes()) {
                    if let Some(socket) = std::str::from_utf8(arg)
                        .ok()
                        .and_then(|s| s.strip_prefix("--input-ipc-server="))
                    {
                        if let Some(process) = matching_audio(pid, Path::new(socket)) {
                            process.terminate_tree()?;
                        }
                    }
                    break;
                }
            }
        }
    }
    Ok(())
}

/// Retire only the exact Python services for this checkout and runtime. PID
/// marker contents alone never authorize signalling; foreign/decoy PIDs survive.
pub fn retire_legacy(root: &Path, runtime: &Path) {
    for (name, script, flag) in [
        ("volume", "lofi-player", Some("--watch")),
        ("mpris", "lofi-mpris", None),
        ("feed", "lofi-player", Some("--resolve-feed")),
    ] {
        let marker = runtime.join(format!("{name}.pid"));
        let Some(pid) = fs::read_to_string(&marker)
            .ok()
            .and_then(|s| s.trim().parse::<u32>().ok())
        else {
            continue;
        };
        let Ok(process) = Process::pin(pid) else {
            let _ = fs::remove_file(marker);
            continue;
        };
        let Ok(argv) = fs::read(format!("/proc/{pid}/cmdline")) else {
            continue;
        };
        let arguments: Vec<_> = argv.split(|c| *c == 0).collect();
        let target = root.join(script).to_string_lossy().into_owned();
        let script_matches = arguments.contains(&target.as_bytes());
        let flag_matches = flag.is_none_or(|flag| arguments.contains(&flag.as_bytes()));
        // XDG_RUNTIME_DIR is inherited by the old worker. Verify it before
        // retiring a process whose script may also serve another test runtime.
        let expected = runtime.parent().unwrap_or(runtime).to_string_lossy();
        let environment = fs::read(format!("/proc/{pid}/environ")).unwrap_or_default();
        let runtime_matches = environment
            .split(|c| *c == 0)
            .find_map(|entry| entry.strip_prefix(b"XDG_RUNTIME_DIR="))
            .map_or_else(
                || expected == format!("/run/user/{}", unsafe { libc::geteuid() }),
                |value| value == expected.as_bytes(),
            );
        if process.alive() && script_matches && flag_matches && runtime_matches {
            process.terminate();
            let _ = fs::remove_file(marker);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::{BufRead, BufReader},
        process::{Command, Stdio},
    };
    struct Kill(Process);
    impl Drop for Kill {
        fn drop(&mut self) {
            let _ = self.0.signal(libc::SIGKILL);
        }
    }
    fn state(process: &Process) -> Option<String> {
        fs::read_to_string(format!("/proc/{}/status", process.pid))
            .ok()
            .and_then(|text| {
                text.lines()
                    .find(|line| line.starts_with("State:"))
                    .and_then(|line| line.split_whitespace().nth(1))
                    .map(str::to_owned)
            })
    }
    #[test]
    fn failed_tree_capture_resumes_every_identity_without_killing() {
        let mut child = Command::new("sh")
            .args(["-c", "sleep 30 & echo $!; wait"])
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let root = Kill(Process::pin(child.id()).unwrap());
        let mut reader = BufReader::new(child.stdout.take().unwrap());
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        let descendant = Kill(Process::pin(line.trim().parse().unwrap()).unwrap());
        assert!(root.0.terminate_tree_with_budget(1).is_err());
        assert!(root.0.alive());
        assert!(descendant.0.alive());
        let deadline = Instant::now() + Duration::from_secs(1);
        while Instant::now() < deadline
            && [state(&root.0), state(&descendant.0)]
                .iter()
                .any(|state| matches!(state.as_deref(), Some("T" | "t")))
        {
            thread::sleep(Duration::from_millis(2));
        }
        assert!(!matches!(state(&root.0).as_deref(), Some("T" | "t")));
        assert!(!matches!(state(&descendant.0).as_deref(), Some("T" | "t")));
        root.0.terminate_tree().unwrap();
        assert!(!root.0.alive());
        assert!(descendant.0.wait(100));
        let _ = child.wait();
    }
    #[test]
    fn already_exited_identity_needs_no_cancellation() {
        let mut child = Command::new("sh")
            .args(["-c", "read ignored"])
            .stdin(Stdio::piped())
            .spawn()
            .unwrap();
        let process = Kill(Process::pin(child.id()).unwrap());
        drop(child.stdin.take());
        let _ = child.wait();
        assert!(!process.0.alive());
        assert!(process.0.terminate_tree().is_ok());
    }
}

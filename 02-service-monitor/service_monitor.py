import subprocess
import psutil
import datetime
import os

LOG_DIR = os.path.expanduser("~/service_logs")
LOG_FILE = os.path.join(LOG_DIR, f"services_{datetime.date.today()}.log")

SERVICES = ["cron", "ssh", "nginx", "apache2", "docker"]

os.makedirs(LOG_DIR, exist_ok=True)

def log(message):
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {message}"
    print(line)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def check_service(service):
    try:
        result = subprocess.run(
            ["systemctl", "is-active", service],
            capture_output=True, text=True
        )
        status = result.stdout.strip()
        if status == "active":
            log(f"[ OK ]  {service} is running")
        else:
            log(f"[WARN]  {service} is NOT running (status: {status})")
    except Exception as e:
        log(f"[ERROR] Could not check {service}: {e}")

def check_cpu_memory():
    cpu = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory()
    log(f"[ SYS]  CPU: {cpu}%  |  RAM: {mem.percent}%  ({mem.used // 1024 // 1024} MB used)")
    if cpu > 80:
        log(f"[WARN]  CPU usage high: {cpu}%")
    if mem.percent > 85:
        log(f"[WARN]  Memory usage high: {mem.percent}%")

def scan_logs():
    log_paths = ["/var/log/auth.log", "/var/log/syslog"]
    keywords = ["error", "failed", "critical"]
    for path in log_paths:
        if not os.path.exists(path):
            continue
        try:
            with open(path, "r", errors="ignore") as f:
                lines = f.readlines()[-50:]
            hits = [l.strip() for l in lines if any(k in l.lower() for k in keywords)]
            if hits:
                log(f"[WARN]  {len(hits)} issue(s) found in {path}")
                for h in hits[-3:]:
                    log(f"        {h}")
            else:
                log(f"[ OK ]  No issues in {path}")
        except PermissionError:
            log(f"[INFO]  Cannot read {path} (run as root for full access)")

def main():
    log("=" * 55)
    log("  SERVICE & SYSTEM MONITOR")
    log("=" * 55)

    log("-- Service Status --")
    for svc in SERVICES:
        check_service(svc)

    log("-- System Resources --")
    check_cpu_memory()

    log("-- Log Scan --")
    scan_logs()

    log("=" * 55)
    log(f"  Report saved to: {LOG_FILE}")
    log("=" * 55)

if __name__ == "__main__":
    main()


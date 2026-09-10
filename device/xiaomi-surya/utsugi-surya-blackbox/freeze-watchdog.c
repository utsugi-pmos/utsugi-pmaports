/*
 * Reboot the phone when its filesystem stops answering, and leave the reason in
 * RAM for the next boot to read.
 *
 * WHY THIS EXISTS
 * ---------------
 * On 2026-09-10 the surya sat frozen for seven hours. Nothing had crashed: the
 * ADSP went down, its recovery deadlocked, and behind it the encrypted root's
 * I/O stopped -- 51 requests parked in dm-0, nothing dispatched below,
 * /proc/pressure/io reporting 96% full stall, load average 114 with one task
 * running out of 757. Everything that writes was in D state: 55 journald, 45
 * timesyncd, the compositor. The screen was black and the only way out was
 * holding the power button.
 *
 * And that way out DESTROYS THE EVIDENCE. The kernel had detectors on the whole
 * time (DETECT_HUNG_TASK, WQ_WATCHDOG, SOFTLOCKUP_DETECTOR) and their splats
 * went to the ramoops console in RAM -- but journald could not write them to
 * disk, and a long press on the power button is a cold PMIC reset that clears
 * DDR. Seven hours of a frozen phone and not one line survived.
 *
 * HOW IT WORKS, AND WHY IT CAN WORK AT ALL
 * ----------------------------------------
 * Anything that touches the filesystem is stuck by definition, so this process
 * must not: every file it needs is opened at startup and kept open, the pages
 * are locked with mlockall(), and it never allocates, never forks, never execs
 * and never writes to disk. It reads /proc/pressure/io -- kernel counters, no
 * I/O -- and writes to /dev/kmsg and /proc/sysrq-trigger, both RAM.
 *
 * When the full stall stays above the threshold for the whole grace period it
 * asks SysRq for a task dump ('t') and the list of blocked tasks ('w'), waits
 * for printk to drain into the ramoops console, and then reboots with SysRq 'b'
 * -- emergency_restart(), which skips every notifier that would block on the
 * wedged filesystem. The boot line carries reboot=warm, so DDR survives and the
 * next boot finds the dump in /sys/fs/pstore. Read it with 'blackbox'.
 *
 * SysRq through /proc/sysrq-trigger is NOT gated by kernel.sysrq -- checked on
 * this phone with the mask at 16 (sync only): 'w' still printed "Show Blocked
 * State". So there is no sysctl to set, and if that ever changes the watchdog
 * says so in the log instead of spinning.
 *
 * The numbers are deliberately shy: a full stall above 90% sustained for ten
 * minutes is not a slow apk install, it is a phone that is not coming back.
 * Both are tunable in /etc/default/utsugi-surya-freeze-watchdog, and setting
 * FREEZE_REBOOT=0 turns the reboot off and leaves only the logging.
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define CHECK_SECONDS 10

static int fd_psi, fd_kmsg, fd_sysrq;

static void say(const char *msg)
{
	/* <4> is KERN_WARNING: above the console level 'quiet' leaves behind, so
	 * it reaches the ramoops console and not only the journal. */
	char line[256] = "<4>utsugi freeze-watchdog: ";
	size_t n = strlen(line);
	size_t m = strlen(msg);

	if (m > sizeof(line) - n - 2)
		m = sizeof(line) - n - 2;
	memcpy(line + n, msg, m);
	line[n + m] = '\n';
	(void)!write(fd_kmsg, line, n + m + 1);
}

static void sysrq(char c)
{
	(void)!write(fd_sysrq, &c, 1);
}

static void nap(long seconds)
{
	struct timespec t = { .tv_sec = seconds, .tv_nsec = 0 };

	while (nanosleep(&t, &t) == -1)
		;
}

/* full avg60, in hundredths, or -1 if it cannot be read. Parsed by hand: stdio
 * would allocate, and this has to run when nothing else can. */
static int full_avg60(void)
{
	char buf[512];
	ssize_t n = pread(fd_psi, buf, sizeof(buf) - 1, 0);
	char *p;

	if (n <= 0)
		return -1;
	buf[n] = '\0';

	p = strstr(buf, "full ");
	if (!p)
		return -1;
	p = strstr(p, "avg60=");
	if (!p)
		return -1;
	p += 6;

	return (int)(strtod(p, NULL) * 100.0);
}

static int env_int(const char *name, int fallback)
{
	const char *v = getenv(name);
	char *end;
	long n;

	if (!v || !*v)
		return fallback;
	n = strtol(v, &end, 10);
	if (*end || n < 0)
		return fallback;

	return (int)n;
}

int main(void)
{
	int threshold = env_int("FREEZE_THRESHOLD_PERCENT", 90) * 100;
	int grace = env_int("FREEZE_GRACE_SECONDS", 600);
	int do_reboot = env_int("FREEZE_REBOOT", 1);
	int stalled = 0;

	fd_psi = open("/proc/pressure/io", O_RDONLY | O_CLOEXEC);
	fd_kmsg = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
	fd_sysrq = open("/proc/sysrq-trigger", O_WRONLY | O_CLOEXEC);
	if (fd_psi < 0 || fd_kmsg < 0 || fd_sysrq < 0)
		return 1;

	/* Locked in memory before anything else: under a full stall, a page fault
	 * on this program's own text would be the end of it. */
	if (mlockall(MCL_CURRENT | MCL_FUTURE) != 0)
		say("mlockall failed: a page fault could silence this watchdog");

	say("watching /proc/pressure/io");

	for (;;) {
		int full = full_avg60();

		nap(CHECK_SECONDS);

		if (full < 0 || full < threshold) {
			if (stalled >= 60)
				say("the stall cleared on its own");
			stalled = 0;
			continue;
		}

		stalled += CHECK_SECONDS;

		/* Loud on the way up, so the ramoops console shows the ramp and
		 * not only the verdict. */
		if (stalled % 60 == 0)
			say("full I/O stall above the threshold, still counting");

		if (stalled < grace)
			continue;

		say("the filesystem has not answered for the whole grace period");
		if (!do_reboot) {
			say("FREEZE_REBOOT=0: dumping tasks, not rebooting");
			sysrq('t');
			sysrq('w');
			stalled = 0;
			continue;
		}

		say("dumping tasks and rebooting -- read /sys/fs/pstore next boot");
		sysrq('t');
		sysrq('w');
		/* Let printk drain into the ramoops console before the reset. */
		nap(3);
		sysrq('b');
		/* If SysRq is masked, at least do not spin silently. */
		nap(10);
		say("SysRq b did nothing: check kernel.sysrq");
		stalled = 0;
	}
}

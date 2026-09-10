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
 * for printk to drain, and then reboots with SysRq 'b' -- emergency_restart(),
 * which skips every notifier that would block on the wedged filesystem.
 *
 * WHAT IT DOES NOT DO, MEASURED ON 2026-09-10: leave the dump behind. The
 * ramoops region is configured and the console is registered in it
 * (console_size=1MB at 0x9d800000, pstore.compress=none, reboot=warm), and
 * /sys/fs/pstore comes up EMPTY all the same. Tested both ways on this phone --
 * SysRq 'b' and a normal systemctl reboot, each with a marker written to
 * /dev/kmsg and another to /dev/pmsg0 -- and neither the console nor the pmsg
 * record survived. On this device something in the boot chain does not preserve
 * that DDR, U-Boot being the obvious suspect, and the black box's premise does
 * not hold as written.
 *
 * SO THE DUMP GOES TO A RAW PARTITION, and this phone happens to ship one for
 * exactly that: 'logdump', 64 MiB, Qualcomm's own crash-log partition, which
 * postmarketOS never touches and whose contents are disposable by design.
 * ('minidump', 128 MiB, is the other candidate.) It is addressed BY LABEL --
 * /dev/disk/by-partlabel/logdump -- so there is no offset to compute and
 * nothing else can be hit by an arithmetic slip.
 *
 * That works precisely because of what the freeze looked like: dm-0 had 51
 * requests stuck while the disk underneath sat idle and healthy, so a write
 * that skips the filesystem, the page cache and dm-crypt still lands. O_DIRECT
 * with an aligned buffer, straight to the block device.
 *
 * What gets written: a magic header, the uptime, and the tail of /dev/kmsg --
 * which is RAM, so reading it needs no disk. Read it back after the reboot with
 * 'blackbox --freeze'.
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
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

/* The dump partition, by label. 64 MiB on this phone; we use one. */
#define DUMP_DEV  "/dev/disk/by-partlabel/logdump"
#define DUMP_SIZE (1024 * 1024)
#define DUMP_MAGIC "UTSUGI-FREEZE-DUMP\n"


#define CHECK_SECONDS 10

static int fd_psi, fd_kmsg, fd_sysrq, fd_dump = -1, fd_kmsg_r = -1;
static char *dump;   /* aligned, locked, allocated before mlockall */
static volatile sig_atomic_t asked_for_dump;

/* SIGUSR1 saves the log to the dump partition right now, without waiting for a
 * freeze. It is how the dump path gets tested on a healthy phone, and how you
 * grab the log by hand when something interesting is happening. */
static void on_usr1(int sig) { (void)sig; asked_for_dump = 1; }

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

/* Copy what /dev/kmsg holds into the dump partition. No allocation, no
 * filesystem, no page cache: the whole point is that this works while the
 * filesystem does not. */
static void save_dump(const char *why)
{
	size_t used;
	ssize_t n;
	char up[64] = "";
	int fd_up;

	if (fd_dump < 0 || !dump)
		return;

	memset(dump, 0, DUMP_SIZE);
	used = 0;
	used += (size_t)snprintf(dump, 256, "%s%s\n", DUMP_MAGIC, why);

	fd_up = open("/proc/uptime", O_RDONLY | O_CLOEXEC);
	if (fd_up >= 0) {
		n = read(fd_up, up, sizeof(up) - 1);
		close(fd_up);
		if (n > 0)
			used += (size_t)snprintf(dump + used, 128, "uptime %s", up);
	}

	/* From the oldest record the buffer still holds. A short read with
	 * EPIPE means printk overwrote where we were; skip and carry on. */
	if (fd_kmsg_r >= 0) {
		lseek(fd_kmsg_r, 0, SEEK_SET);
		while (used < DUMP_SIZE - 8192) {
			n = read(fd_kmsg_r, dump + used, 8192);
			if (n > 0) {
				used += (size_t)n;
				continue;
			}
			if (n < 0 && errno == EPIPE)
				continue;
			break;
		}
	}

	/* O_DIRECT: length and offset have to be block-aligned, so the whole
	 * buffer goes out. It is zeroed above, so the tail is clean. */
	if (pwrite(fd_dump, dump, DUMP_SIZE, 0) != DUMP_SIZE)
		say("could not write the dump partition");
	else
		say("dump written to " DUMP_DEV);
	fsync(fd_dump);
}

int main(void)
{
	int threshold = env_int("FREEZE_THRESHOLD_PERCENT", 90);

	/* A THRESHOLD BELOW 10 IS NOT A TEST, IT IS A REBOOT LOOP. Setting 0 to try
	 * the dump path on 2026-09-11 made this trip every ten seconds: each trip
	 * dumps hundreds of task stacks through SysRq to a console at level 7, PID 1
	 * missed its hardware watchdog ping, and the phone reset -- twice, because
	 * the setting is on disk and applies again at boot. Use SIGUSR1 to test. */
	if (threshold < 10) {
		threshold = 90;
	}
	threshold *= 100;
	int grace = env_int("FREEZE_GRACE_SECONDS", 600);
	int do_reboot = env_int("FREEZE_REBOOT", 1);
	int stalled = 0;

	/* Everything opened here, while the filesystem still answers. */
	fd_dump = open(DUMP_DEV, O_WRONLY | O_DIRECT | O_CLOEXEC);
	if (fd_dump < 0)
		fd_dump = open(DUMP_DEV, O_WRONLY | O_CLOEXEC);   /* no O_DIRECT: still better than nothing */
	fd_kmsg_r = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
	if (posix_memalign((void **)&dump, 4096, DUMP_SIZE) != 0)
		dump = NULL;

	fd_psi = open("/proc/pressure/io", O_RDONLY | O_CLOEXEC);
	fd_kmsg = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
	fd_sysrq = open("/proc/sysrq-trigger", O_WRONLY | O_CLOEXEC);
	if (fd_psi < 0 || fd_kmsg < 0 || fd_sysrq < 0)
		return 1;

	/* Locked in memory before anything else: under a full stall, a page fault
	 * on this program's own text would be the end of it. */
	signal(SIGUSR1, on_usr1);

	if (mlockall(MCL_CURRENT | MCL_FUTURE) != 0)
		say("mlockall failed: a page fault could silence this watchdog");

	say("watching /proc/pressure/io");

	for (;;) {
		int full = full_avg60();

		nap(CHECK_SECONDS);

		if (asked_for_dump) {
			asked_for_dump = 0;
			say("SIGUSR1: saving the log to the dump partition");
			save_dump("asked for by hand (SIGUSR1)");
		}

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
			say("FREEZE_REBOOT=0: dumping tasks and saving them, not rebooting");
			sysrq('t');
			sysrq('w');
			nap(3);
			save_dump("freeze-watchdog: FREEZE_REBOOT=0, no reboot");
			stalled = 0;
			continue;
		}

		say("dumping tasks and saving them to the dump partition");
		sysrq('t');
		sysrq('w');
		/* Let printk finish before reading /dev/kmsg back. */
		nap(3);
		save_dump("freeze-watchdog: full I/O stall over the grace period");
		sysrq('b');
		/* If SysRq is masked, at least do not spin silently. */
		nap(10);
		say("SysRq b did nothing: check kernel.sysrq");
		stalled = 0;
	}
}

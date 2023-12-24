/*
 *  linux/init/main.c
 *
 *  (C) 1991  Linus Torvalds
 */

#define __LIBRARY__
#include <unistd.h>
#include <time.h>

// 现在已经从 boot/head.s 跳转到了本文件的 main 函数里边
// 参数为三个 0，并且 main 函数永远都不应该返回（结束）

/*
 * we need this inline - forking from kernel space will result
 * in NO COPY ON WRITE (!!!), until an execve is executed. This
 * is no problem, but for the stack. This is handled by not letting
 * main() use the stack at all after fork(). Thus, no function
 * calls - which means inline code for fork too, as otherwise we
 * would use the stack upon exit from 'fork()'.
 *
 * Actually only pause and fork are needed inline, so that there
 * won't be any messing with the stack from main(), but we define
 * some others too.
 */
static inline _syscall0(int,fork);  // 宏定义见 include/unistd.h
static inline _syscall0(int,pause);
static inline _syscall1(int,setup,void *,BIOS);
static inline _syscall0(int,sync);
// 定义了几个内联函数，其实就是对 int $0x80 做了一个很简单的包装

// 其实我没读懂 Linus 的意思 23333
// TODO: 为什么这里需要 inline 呢

#include <linux/tty.h>
#include <linux/sched.h>
#include <linux/head.h>
#include <asm/system.h>
#include <asm/io.h>

#include <stddef.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>

#include <linux/fs.h>

static char printbuf[1024];
// 我不知道输出到这里有啥意义
// 仅仅只是在内存中存在，整个 Linux 0.11 的代码里边，也没有任何到这里的引用
// （当然，加个前提，除了本文件对其的几次引用）

// 下面这些函数分布在各种文件里边
extern int vsprintf();
extern void init(void);
extern void blk_dev_init(void);
extern void chr_dev_init(void);
extern void hd_init(void);
extern void floppy_init(void);
extern void mem_init(long start, long end);
extern long rd_init(long mem_start, int length);
extern long kernel_mktime(struct tm * tm);
extern long startup_time;

/*
 * This is set up by the setup-routine at boot-time
 */
// 这些数据是 boot/setup.s 给放那的，而且也还没被覆盖到，可以很方便地直接拿来用
#define EXT_MEM_K (*(unsigned short *)0x90002)
#define DRIVE_INFO (*(struct drive_info *)0x90080)
// 这个是主副设备号的信息，最开始由 tools/build 给放到镜像里，然后又被载入到内存中这个地址处
#define ORIG_ROOT_DEV (*(unsigned short *)0x901FC)

/*
 * Yeah, yeah, it's ugly, but I cannot find how to do this correctly
 * and this seems to work. I anybody has more info on the real-time
 * clock I'd be interested. Most of this was trial and error, and some
 * bios-listing reading. Urghh.
 */

#define CMOS_READ(addr) ({ \
outb_p(0x80|addr,0x70); \
inb_p(0x71); \
})

#define BCD_TO_BIN(val) ((val)=((val)&15) + ((val)>>4)*10)

// 初始化时间
// 仅仅是从 CMOS 读取时间信息，并存到 startup_time 变量里
static void time_init(void)
{
	struct tm time;

	do {
		time.tm_sec = CMOS_READ(0);
		time.tm_min = CMOS_READ(2);
		time.tm_hour = CMOS_READ(4);
		time.tm_mday = CMOS_READ(7);
		time.tm_mon = CMOS_READ(8);
		time.tm_year = CMOS_READ(9);
	} while (time.tm_sec != CMOS_READ(0));
	BCD_TO_BIN(time.tm_sec);
	BCD_TO_BIN(time.tm_min);
	BCD_TO_BIN(time.tm_hour);
	BCD_TO_BIN(time.tm_mday);
	BCD_TO_BIN(time.tm_mon);
	BCD_TO_BIN(time.tm_year);
	time.tm_mon--;
	startup_time = kernel_mktime(&time);
}

static long memory_end = 0;
static long buffer_memory_end = 0;
static long main_memory_start = 0;

struct drive_info { char dummy[32]; } drive_info;

// 从 boot/head.s 跳转而来
// 跳转到此的真实入口为其中 setup_paging 的 ret 语句

// 这里有个有趣的问题：boot/head.s 跟 main.c 最终是被链接到一起的
// 而众所周知，main 函数是 C 程序的入口，但最终为什么先执行的是 boot/head.s 呢？
// 因为平常我们写的 main 函数实际上被 libc 套了一层，程序的真实入口不是 main 函数
// 这里编译出来的目标文件很明显直接就是跑在裸机，外边不再有任何东西
// 加上 boot/setup.s 那边是直接 jmp 过来，所以就以首地址（boot/head.s 链接在了最前边）作为入口了
void main(void)		/* This really IS void, no error here. */
{					/* The startup routine assumes (well, ...) this */
// main 函数应该永远也不会返回
// 万一返回了，就回到 head.s 里边的 L6 标号处无限死循环了

/*
 * Interrupts are still disabled. Do necessary setups, then
 * enable them
 */
	ROOT_DEV = ORIG_ROOT_DEV;  // ROOT_DEV 在 fs/super.c 里，是一个全局变量
	drive_info = DRIVE_INFO;
	memory_end = (1<<20) + (EXT_MEM_K<<10);
	memory_end &= 0xfffff000;
	if (memory_end > 16*1024*1024)
		memory_end = 16*1024*1024;
	if (memory_end > 12*1024*1024) 
		buffer_memory_end = 4*1024*1024;
	else if (memory_end > 6*1024*1024)
		buffer_memory_end = 2*1024*1024;
	else
		buffer_memory_end = 1*1024*1024;
	main_memory_start = buffer_memory_end;
#ifdef RAMDISK
	main_memory_start += rd_init(main_memory_start, RAMDISK*1024);
#endif
	// 一系列的初始化工作
	mem_init(main_memory_start,memory_end);
	trap_init();
	blk_dev_init();
	chr_dev_init();
	tty_init();
	time_init();
	sched_init();
	buffer_init(buffer_memory_end);
	hd_init();
	floppy_init();
	sti();				// 一切准备就绪，开中断
	move_to_user_mode();
	if (!fork()) {		/* we count on this going ok */
	    // 在子进程里边进行 init (task 1)
		init();
	}
/*
 *   NOTE!!   For any other task 'pause()' would mean we have to get a
 * signal to awaken, but task0 is the sole exception (see 'schedule()')
 * as task 0 gets activated at every idle moment (when no other tasks
 * can run). For task0 'pause()' just means we go check if some other
 * task can run, and if not we return here.
 */
	for(;;) pause();
	// 父进程来到这里 (task 0)
}

static int printf(const char *fmt, ...)
{
	va_list args;
	int i;

	va_start(args, fmt);
	write(1,printbuf,i=vsprintf(printbuf, fmt, args));
	va_end(args);
	return i;
}

// 下边是两套参数/环境环境变量
// 分别用于执行 /etc/rc 跟启动 shell 的过程中

static char * argv_rc[] = { "/bin/sh", NULL };
static char * envp_rc[] = { "HOME=/", NULL };

static char * argv[] = { "-/bin/sh",NULL };
static char * envp[] = { "HOME=/usr/root", NULL };

// init 进程主函数 (pid=1)
void init(void)
{
	int pid,i;

	setup((void *) &drive_info);
	// setup 这个系统调用仅用于初始化期间
	// 函数定义在 kernel/blk_drv/hd.c

	(void) open("/dev/tty0",O_RDWR,0);	// stdin
	(void) dup(0);				// stdout
	(void) dup(0);				// stderr
	// Q: 不是很明白这里为什么要加上 (void) 对函数返回值进行强制类型转换
    // A: 估计是为了让编译器不要警告返回值未使用
	printf("%d buffers = %d bytes buffer space\n\r",NR_BUFFERS,
		NR_BUFFERS*BLOCK_SIZE);
	printf("Free mem: %d bytes\n\r",memory_end-main_memory_start);

	if (!(pid=fork())) {
        // 再次 fork，得到 pid 2，并执行用户配置的启动命令
		close(0);
		// 关闭 fd=0 然后立即打开 /etc/rc，stdin 就被重定向到这个文件了
		if (open("/etc/rc",O_RDONLY,0))
		    // 有个小 trick，因为此时，返回的 fd 应当为 0，就可以以此判断出错与否了…
			_exit(1);

		// 注意，stdin 指向 /etc/rc，所以下面这行会从 /etc/rc 读取内容并执行
		execve("/bin/sh",argv_rc,envp_rc);
        // 这行 exit 预期永远不会执行，execve 后当前进程就被直接替换掉了
		_exit(2);
	}
	// 子进程跑去执行 /etc/rc 了，父进程(pid=1)来到这里
	// 不做啥事，就是等子进程
	// 一旦子进程结束（/etc/rc 的内容执行完了），就进入到下边的 while(1)
	// 如果 fork 失败了，也直接进入下边的 while(1)
	if (pid>0)
		while (pid != wait(&i))
			/* nothing */;

	while (1) {
		if ((pid=fork())<0) {
			printf("Fork failed in init\r\n");
			continue;
		}
		if (!pid) {  // 子进程
			close(0);close(1);close(2);
			setsid();	// 创建一个新的会话
			// TODO: 不清楚“会话”在 Linux 里的作用
			(void) open("/dev/tty0",O_RDWR,0);
			(void) dup(0);
			(void) dup(0);
			_exit(execve("/bin/sh",argv,envp));
			// 注意这里用的环境变量跟启动参数跟上边 /etc/rc 那会不一样
		}

		// 注意只有父进程会执行到这里
		while (1)
			if (pid == wait(&i))
				break;

		printf("\n\rchild %d died with code %04x\n\r",pid,i);
		sync();		// 确保将缓存数据存入硬盘中
		// 然后父进程就又开始循环了…
		// 这个循环永远都不会退出= =
		// TODO: Linux 0.11 中，正常的关机流程是啥啊？
	}

	// 这行应该没啥用，只是防御性编程
	_exit(0);	/* NOTE! _exit, not exit() */
}

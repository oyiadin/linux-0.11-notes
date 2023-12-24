#ifndef _SCHED_H
#define _SCHED_H

// 最多只支持 64 个进程
#define NR_TASKS 64
#define HZ 100

#define FIRST_TASK task[0]
#define LAST_TASK task[NR_TASKS-1]
// trap: task[0~63] 共 64 个

#include <linux/head.h>
#include <linux/fs.h>
#include <linux/mm.h>
#include <signal.h>

#if (NR_OPEN > 32)
#error "Currently the close-on-exec-flags are in one word, max 32 files/proc"
#endif

#define TASK_RUNNING		0
#define TASK_INTERRUPTIBLE	1
#define TASK_UNINTERRUPTIBLE	2
#define TASK_ZOMBIE		3
#define TASK_STOPPED		4
// 这五个状态原来从一开始就有了

#ifndef NULL
#define NULL ((void *) 0)
#endif

extern int copy_page_tables(unsigned long from, unsigned long to, long size);
extern int free_page_tables(unsigned long from, unsigned long size);

extern void sched_init(void);
extern void schedule(void);
extern void trap_init(void);
extern void panic(const char * str);
extern int tty_write(unsigned minor,char * buf,int count);

typedef int (*fn_ptr)();

struct i387_struct {
	long	cwd;
	long	swd;
	long	twd;
	long	fip;
	long	fcs;
	long	foo;
	long	fos;
	long	st_space[20];	/* 8*10 bytes for each FP-reg = 80 bytes */
};

struct tss_struct {
	long	back_link;	/* 16 high bits zero */
	long	esp0;
	long	ss0;		/* 16 high bits zero */
	long	esp1;
	long	ss1;		/* 16 high bits zero */
	long	esp2;
	long	ss2;		/* 16 high bits zero */
	long	cr3;
	long	eip;
	long	eflags;
	long	eax,ecx,edx,ebx;
	long	esp;
	long	ebp;
	long	esi;
	long	edi;
	long	es;		/* 16 high bits zero */
	long	cs;		/* 16 high bits zero */
	long	ss;		/* 16 high bits zero */
	long	ds;		/* 16 high bits zero */
	long	fs;		/* 16 high bits zero */
	long	gs;		/* 16 high bits zero */
	long	ldt;		/* 16 high bits zero */
	long	trace_bitmap;	/* bits: trace 0, bitmap 16-31 */
	struct i387_struct i387;
};

struct task_struct {
/* these are hardcoded - don't touch */
	long state;	/* -1 unrunnable, 0 runnable, >0 stopped */
    // 在进程占用 CPU 的期间，其对应的 counter 会随着定时中断的触发而逐渐减少
    // 可以类比为各个进程剩下的 CPU 配额
    long counter;
	long priority;	// 值越小，优先级越高
	long signal;
	struct sigaction sigaction[32];
	long blocked;	/* bitmap of masked signals */
	// 现在的 sigmask
/* various fields */
	int exit_code;
	unsigned long start_code,end_code,end_data,brk,start_stack;
	long pid,father,pgrp,session,leader;
    // uid：用户的真实 ID
    // euid：effective uid，用以鉴权的 ID。有时候由于 sudo 等原因可能临时提权
	unsigned short uid,euid,suid;
	unsigned short gid,egid,sgid;
	long alarm;
	long utime,stime,cutime,cstime,start_time;
	unsigned short used_math;
/* file system info */
	int tty;		/* -1 if no tty, so it must be signed */
    // umask 中为 1 的 bit 代表该位应当被关闭
    // umask 应该理解为类似于“un mask bits”
	unsigned short umask;  // 用作新建文件的默认权限
	struct m_inode * pwd;
	struct m_inode * root;
	struct m_inode * executable;
    // exec 后是否自动关闭对应的 fd（这个字段是一个 bitmap）
	unsigned long close_on_exec;
	struct file * filp[NR_OPEN];
/* ldt for this task 0 - zero 1 - cs 2 - ds&ss */
	struct desc_struct ldt[3];
/* tss for this task */
	struct tss_struct tss;
};

/*
 *  INIT_TASK is used to set up the first task table, touch at
 * your own risk!. Base=0, limit=0x9ffff (=640kB)
 */
#define INIT_TASK { \
	.state=0, \
	.counter=15, \
	.priority=15, \
	.signal=0, \
	.sigaction={{},}, \
	.blocked=0, \
	.exit_code=0, \
	.start_code=0, \
	.end_code=0, \
	.end_data=0, \
	.brk=0, \
	.start_stack=0, \
	.pid=0, \
	.father=-1, \
	.pgrp=0, \
	.session=0, \
	.leader=0, \
	.uid=0, \
	.euid=0, \
	.suid=0, \
	.gid=0, \
	.egid=0, \
	.sgid=0, \
	.alarm=0, \
	.utime=0, \
	.stime=0, \
	.cutime=0, \
	.cstime=0, \
	.start_time=0, \
	.used_math=0, \
	.tty=-1, \
	.umask=0022, \
	.pwd=NULL, \
	.root=NULL, \
	.executable=NULL, \
	.close_on_exec=0, \
	.filp={NULL,}, \
	.ldt={ \
		{0,0}, \
		{0x9f,0xc0fa00}, \
		{0x9f,0xc0f200}, \
	}, \
	.tss={ \
		.back_link=0, \
		.esp0=PAGE_SIZE+(long)&init_task, \
		.ss0=0x10, \
		.esp1=0, \
		.ss1=0, \
		.esp2=0, \
		.ss2=0, \
		.cr3=(long)&pg_dir, \
		.eip=0, \
		.eflags=0, \
		.eax=0, \
		.ecx=0, \
		.edx=0, \
		.ebx=0, \
		.esp=0, \
		.ebp=0, \
		.esi=0, \
		.edi=0, \
		.es=0x17, \
		.cs=0x17, \
		.ss=0x17, \
		.ds=0x17, \
		.fs=0x17, \
		.gs=0x17, \
		.ldt=_LDT(0), \
		.trace_bitmap=0x80000000, \
		.i387={}, \
	}, \
}

extern struct task_struct *task[NR_TASKS];
extern struct task_struct *last_task_used_math;
extern struct task_struct *current;
extern long volatile jiffies;
extern long startup_time;

#define CURRENT_TIME (startup_time+jiffies/HZ)

extern void add_timer(long jiffies, void (*fn)(void));
extern void sleep_on(struct task_struct ** p);
extern void interruptible_sleep_on(struct task_struct ** p);
extern void wake_up(struct task_struct ** p);

/*
 * Entry into gdt where to find first TSS. 0-nul, 1-cs, 2-ds, 3-syscall
 * 4-TSS0, 5-LDT0, 6-TSS1 etc ...
 */
#define FIRST_TSS_ENTRY 4
#define FIRST_LDT_ENTRY (FIRST_TSS_ENTRY+1)
#define _TSS(n) ((((unsigned long) n)<<4)+(FIRST_TSS_ENTRY<<3))
#define _LDT(n) ((((unsigned long) n)<<4)+(FIRST_LDT_ENTRY<<3))
#define ltr(n) __asm__("ltr %%ax"::"a" (_TSS(n)))
#define lldt(n) __asm__("lldt %%ax"::"a" (_LDT(n)))
#define str(n) \
__asm__("str %%ax\n\t" \
	"subl %2,%%eax\n\t" \
	"shrl $4,%%eax" \
	:"=a" (n) \
	:"a" (0),"i" (FIRST_TSS_ENTRY<<3))
/*
 *	switch_to(n) should switch tasks to task nr n, first
 * checking that n isn't the current task, in which case it does nothing.
 * This also clears the TS-flag if the task we switched to has used
 * tha math co-processor latest.
 */
#define switch_to(n) /* n是对应进程的下标，不是pid */ {\
struct {long a,b;} __tmp; \
__asm__( \
    "cmpl %%ecx,_current\n\t" \
	"je 1f\n\t" /* 如果目标进程已经是当前进程，就啥都不做直接跳出 */ \
	"movw %%dx,%1\n\t" \
	"xchgl %%ecx,_current\n\t" /* 原来 current 变量是在这里改的 */ \
	"ljmp %0\n\t" /* TODO: 这里应该就跳到新任务去了，不过没咋看懂，等我了解一番 TSS */ \
	"cmpl %%ecx,_last_task_used_math\n\t" \
	"jne 1f\n\t" \
	"clts\n" \
	"1:" \
	::"m" (*&__tmp.a),"m" (*&__tmp.b), \
	"d" (_TSS(n)),"c" ((long) task[n])); \
}

#define PAGE_ALIGN(n) (((n)+0xfff)&0xfffff000)

#define _set_base(addr,base) \
__asm__("movw %%dx,%0\n\t" \
	"rorl $16,%%edx\n\t" \
	"movb %%dl,%1\n\t" \
	"movb %%dh,%2" \
	::"m" (*((addr)+2)), \
	  "m" (*((addr)+4)), \
	  "m" (*((addr)+7)), \
	  "d" (base) \
	:"dx")

#define _set_limit(addr,limit) \
__asm__("movw %%dx,%0\n\t" \
	"rorl $16,%%edx\n\t" \
	"movb %1,%%dh\n\t" \
	"andb $0xf0,%%dh\n\t" \
	"orb %%dh,%%dl\n\t" \
	"movb %%dl,%1" \
	::"m" (*(addr)), \
	  "m" (*((addr)+6)), \
	  "d" (limit) \
	:"dx")

#define set_base(ldt,base) _set_base( ((char *)&(ldt)) , base )
#define set_limit(ldt,limit) _set_limit( ((char *)&(ldt)) , (limit-1)>>12 )

#define _get_base(addr) ({\
unsigned long __base; \
__asm__("movb %3,%%dh\n\t" \
	"movb %2,%%dl\n\t" \
	"shll $16,%%edx\n\t" \
	"movw %1,%%dx" \
	:"=d" (__base) \
	:"m" (*((addr)+2)), \
	 "m" (*((addr)+4)), \
	 "m" (*((addr)+7))); \
__base;})

#define get_base(ldt) _get_base( ((char *)&(ldt)) )

#define get_limit(segment) ({ \
unsigned long __limit; \
__asm__("lsll %1,%0\n\tincl %0":"=r" (__limit):"r" (segment)); \
__limit;})

#endif

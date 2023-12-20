/*
 *  linux/boot/head.s
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 *  head.s contains the 32-bit startup code.
 *
 * NOTE!!! Startup happens at absolute address 0x00000000, which is also where
 * the page directory will exist. The startup code will be overwritten by
 * the page directory.
 */
.text
.globl _idt,_gdt,_pg_dir,_tmp_floppy_area
_pg_dir:
startup_32:
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	mov %ax,%gs
	# 注意现在已经处于保护模式之下了，0x10 不是一个单纯的立即数，应将其视为一个段选择子
	# 即 0000000000010 0   00
	#        Index    GDT RPL
	# 对应着 GDT 中的第二个段描述符，即那个可读可写的数据段，段基址为 0x0000
	lss _stack_start,%esp
	# 将 ss:esp 设为 _stack_start
	# TODO: 在 kernel/sched.c#L72 找到了 stack_start 的定义，但是没看懂为什么要设置在那
	#       随便找一块内存放着不就行了？
	call setup_idt	# 覆盖掉 setup 中临时的 IDT/GDT，所有中断都由 ignore_int 来处理
	call setup_gdt

	# 由于缓存的缘故，当段寄存器在"load"的时候，新 GDT 才会发生作用
	# 因此这里将几个寄存器都刷新一遍
	# 见 https://stackoverflow.com/questions/30932302/i-am-confusing-some-assembly-code-about-enable-pe-within-boot-setup-s-file-in-linux-0-11
	movl $0x10,%eax		# reload all the segment registers
	mov %ax,%ds		# after changing gdt. CS was already
	mov %ax,%es		# reloaded in 'setup_gdt'
	mov %ax,%fs
	mov %ax,%gs
	lss _stack_start,%esp

# 下边这部分代码跳过吧，感觉都是了解了也没用的细节
	xorl %eax,%eax 		# 清空
1:	incl %eax			# check that A20 really IS enabled
	movl %eax,0x000000	# loop forever if it isn't
	cmpl %eax,0x100000
	je 1b

/*
 * NOTE! 486 should set bit 16, to check for write-protect in supervisor
 * mode. Then it would be unnecessary with the "verify_area()"-calls.
 * 486 users probably want to set the NE (#5) bit also, so as to use
 * int 16 for math errors.
 */
	movl %cr0,%eax		# check math chip
	andl $0x80000011,%eax	# Save PG,PE,ET
/* "orl $0x10020,%eax" here for 486 might be good */
	orl $2,%eax		# set MP
	movl %eax,%cr0
	call check_x87
	jmp after_page_tables 	# 注意这里跳走了
	# 跳走了之后，就可以（用页表）覆盖这段内存空间了
	# after_page_tables 处在页表后边，不会受到影响

/*
 * We depend on ET to be correct. This checks for 287/387.
 */
check_x87:
	fninit
	fstsw %ax
	cmpb $0,%al
	je 1f			/* no coprocessor: have to set bits */
	movl %cr0,%eax
	xorl $6,%eax		/* reset MP, set EM */
	movl %eax,%cr0
	ret
.align 2
1:	.byte 0xDB,0xE4		/* fsetpm for 287, ignored by 387 */
	ret

/*
 *  setup_idt
 *
 *  sets up a idt with 256 entries pointing to
 *  ignore_int, interrupt gates. It then loads
 *  idt. Everything that wants to install itself
 *  in the idt-table may do so themselves. Interrupts
 *  are enabled elsewhere, when we can be relatively
 *  sure everything is ok. This routine will be over-
 *  written by the page tables.
 */

/*  IDT 描述符结构

 *  |31                           16|15                            0|
 *  +---------------------------------------------------------------+
 *  |            Selector           |          Offset 15~0          |
 *  +---------------------------------------------------------------+
 *  
 *  |31                           16| 15|14 13| 12|11   8|7        0|
 *  +-------------------------------|-------------------------------+
 *  |          Offset 31~16         | P | DPL | S | TYPE | RESERVED |
 *  +---------------------------------------------------------------+
 */

setup_idt:
	lea ignore_int,%edx
	# 汇编知识不牢固，这里标注一下 mov 跟 lea 的区别：
	# lea 只计算地址，mov 则是计算地址后解了引用

	movl $0x00080000,%eax
	# 段选择子为 0x0008
	movw %dx,%ax		/* selector = 0x0008 = cs */
	# ignore_int 的有效地址作为偏移量
	# eax 存放中断描述符的前 4Bytes

	movw $0x8E00,%dx	/* interrupt gate - dpl=0, present */
	# 1 00 0 1110 00000000
	# edx 存放中断描述符的后 4Bytes

	lea _idt,%edi		# 目标地址
	mov $256,%ecx		# 计数器
rp_sidt:
	movl %eax,(%edi)
	movl %edx,4(%edi)
	addl $8,%edi		# 一个中断描述符占用 8 Bytes
	dec %ecx
	jne rp_sidt
	lidt idt_descr
	ret

/*
 *  setup_gdt
 *
 *  This routines sets up a new gdt and loads it.
 *  Only two entries are currently built, the same
 *  ones that were built in init.s. The routine
 *  is VERY complicated at two whole lines, so this
 *  rather long comment is certainly needed :-).
 *  This routine will beoverwritten by the page tables.
 */
setup_gdt:
	lgdt gdt_descr
	ret

/*
 * I put the kernel page tables right after the page directory,
 * using 4 of them to span 16 Mb of physical memory. People with
 * more than 16MB will have to expand this.
 */
.org 0x1000 		# 此处的偏移量为 0x1000 的意思，因此会在这上边腾出空缺
pg0:

.org 0x2000
pg1:

.org 0x3000
pg2:

.org 0x4000
pg3:

# 0x1000~0x4fff 这块内存共放置了四个页表

.org 0x5000
/*
 * tmp_floppy_area is used by the floppy-driver when DMA cannot
 * reach to a buffer-block. It needs to be aligned, so that it isn't
 * on a 64kB border.
 */
_tmp_floppy_area:
	.fill 1024,1,0

after_page_tables:
	pushl $0		# These are the parameters to main :-)
	pushl $0
	pushl $0
	pushl $L6		# return address for main, if it decides to.
	pushl $_main 		# init/main.c 里边的 main 函数地址
	# 上文是一个很典型的 cdecl 调用约定的结构
	# https://en.wikipedia.org/wiki/X86_calling_conventions#cdecl
	# 也就是： 参数3 参数2 参数1 返回地址
	# 除了最后一个 _main 的值不属于 cdecl 约定
	# 正常来说入栈了返回地址后应该就可以 jmp 过去了，详见下边的解释说明
	jmp setup_paging
	# 注意这里是 jmp，
	# 配合上边手动 push 的地址
	# 在 setup_paging 结束后，可以用 ret 替代 call（跳转到 main）
	# 如果看不懂…先去熟悉一下函数调用过程中栈内数据的变化，以及 call, ret 的作用

	# - 为什么要这么做？
	# - 因为要手动指定返回地址（也即是下边的 L6）
	#   注意这里已经在页表后边了，这段代码（暂时？）不会被覆盖掉
	#   所以可以作为 main 的返回地址（虽然预期中永远都不能回到这里来）
L6:
	jmp L6			# main should never return here, but
				# just in case, we know what happens.

/* This is the default interrupt "handler" :-) */
int_msg:
	.asciz "Unknown interrupt\n\r"
.align 2
ignore_int:
	# CPU 会为我们保存 cs, eip
	# 其他都需要自己保存
	pushl %eax
	# - 为什么不保存 ebx?
	# - 我也很奇怪…
	#   可能是因为 printk 写死了只用到 eax, ecx, edx 吧（见 kernel/printk.c）
	pushl %ecx
	pushl %edx
	push %ds
	push %es
	push %fs
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	pushl $int_msg
	call _printk 		# 函数定义在 kernel/printk.c 里
	popl %eax
	pop %fs
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret 			# 注意是 iret，现在正在处理中断，不是普通的函数调用


/*
 * Setup_paging
 *
 * This routine sets up paging by setting the page bit
 * in cr0. The page tables are set up, identity-mapping
 * the first 16MB. The pager assumes that no illegal
 * addresses are produced (ie >4Mb on a 4Mb machine).
 *
 * NOTE! Although all physical memory should be identity
 * mapped by this routine, only the kernel page functions
 * use the >1Mb addresses directly. All "normal" functions
 * use just the lower 1Mb, or the local data space, which
 * will be mapped to some other place - mm keeps track of
 * that.
 *
 * For those with more memory than 16 Mb - tough luck. I've
 * not got it, why should you :-) The source is here. Change
 * it. (Seriously - it shouldn't be too difficult. Mostly
 * change some constants etc. I left it at 16Mb, as my machine
 * even cannot be extended past that (ok, but it was cheap :-)
 * I've tried to show which constants to change by having
 * some kind of marker at them (search for "16Mb"), but I
 * won't guarantee that's all :-( )
 */
.align 2
# 设置页表，这部分暂时先跳过了
# 读到内存管理再来回顾吧
setup_paging:
	movl $1024*5,%ecx		/* 5 pages - pg_dir+4 page tables */
	xorl %eax,%eax
	xorl %edi,%edi			/* pg_dir is at 0x000 */
	cld;rep;stosl
	movl $pg0+7,_pg_dir		/* set present bit/user r/w */
	movl $pg1+7,_pg_dir+4		/*  --------- " " --------- */
	movl $pg2+7,_pg_dir+8		/*  --------- " " --------- */
	movl $pg3+7,_pg_dir+12		/*  --------- " " --------- */
	movl $pg3+4092,%edi
	movl $0xfff007,%eax		/*  16Mb - 4096 + 7 (r/w user,p) */
	std
1:	stosl			/* fill pages backwards - more efficient :-) */
	subl $0x1000,%eax
	jge 1b
	xorl %eax,%eax		/* pg_dir is at 0x0000 */
	movl %eax,%cr3		/* cr3 - page directory start */
	movl %cr0,%eax
	orl $0x80000000,%eax
	movl %eax,%cr0		/* set paging (PG) bit */
	ret			/* this also flushes prefetch-queue */
	# 这里 ret 跳到了 init/main.c 里边 的 main
	# 而非返回本文件跳过来的地方

.align 2
.word 0
idt_descr:
	.word 256*8-1		# idt contains 256 entries
	# 注意 lidt 跟 lgdt 的参数都是一个地址，地址指向一个 6bytes 的结构
	# 然后里边的前两字节是 limits，是实际数量-1
	.long _idt
.align 2
.word 0
gdt_descr:
	.word 256*8-1		# so does gdt (not that that's any
	.long _gdt		# magic number, but it works for me :^)

	.align 3
_idt:	.fill 256,8,0		# idt is uninitialized
# 现在的 IDT 表跟 GDT 表就混杂在代码中间
# 当然，本文件这段从 0x00000 开始的代码早晚肯定会被覆盖掉的

_gdt:	.quad 0x0000000000000000	/* NULL descriptor */
	.quad 0x00c09a0000000fff	/* 16Mb */
	.quad 0x00c0920000000fff	/* 16Mb */
	.quad 0x0000000000000000	/* TEMPORARY - don't use */
	.fill 252,8,0			/* space for LDT's and TSS's etc */
# 这个表似乎就一直用着了？
# 反正 head.s 其实就是内存的头部

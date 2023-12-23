# 
# 	setup.s		(C) 1991 Linus Torvalds
# 
# setup.s is responsible for getting the system data from the BIOS,
# and putting them into the appropriate places in system memory.
# both setup.s and system has been loaded by the bootblock.
# 
# This code asks the bios for memory/disk/other parameters, and
# puts them in a "safe" place: 0x90000-0x901FF, ie where the
# boot-block used to be. It is then up to the protected mode
# system to read them from there before the area is overwritten
# for buffer-blocks.
# 

# 从 bootsec 跳转而来
# 此文件此时已经被载入到内存里的 0x90200 处
# 同时，system 模块已经被载入到 0x10000 处
# 此文件中将向 BIOS 查询一些硬件信息，并存储到 0x90000-0x901FF
# 这块区域曾经放置着 bootsect，但现在 bootsect 的使命已经结束了，可以拿来复用，直接覆盖

# NOTE! These had better be the same as in bootsect.s!

# we move boot here - out of the way
INITSEG  = 0x9000
# system loaded at 0x10000 (65536).
SYSSEG   = 0x1000
# this is the current segment
SETUPSEG = 0x9020

.globl begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

entry start
start:

# 下边这一系列类似的代码，作用是将一些硬件信息放到 0x90000～0x901ff 里边
# 嗯…毫不留情地将 bootsec 给覆盖掉了
# 具体细节就无需读了，都是各种 BIOS 提供的服务
# 各个地址上边放的啥我就懒得记了，见《Linux内核完全注释》P44 表3-3

# ok, the read went well so we get current cursor position and save it for
# posterity.

	# this is done in bootsect already, but...
	mov	ax,#INITSEG
	mov	ds,ax
	# read cursor pos
	mov	ah,#0x03
	xor	bh,bh
	# save it in known place, con_init fetches
	int	0x10
	# it from 0x90000.
	mov	[0],dx

# Get memory size (extended mem, kB)

	mov	ah,#0x88
	int	0x15
	mov	[2],ax

# Get video-card data:

	mov	ah,#0x0f
	int	0x10
	# bh = display page
	mov	[4],bx
	# al = video mode, ah = window width
	mov	[6],ax

# check for EGA/VGA and some config parameters

	mov	ah,#0x12
	mov	bl,#0x10
	int	0x10
	mov	[8],ax
	mov	[10],bx
	mov	[12],cx

# Get hd0 data

	mov	ax,#0x0000
	mov	ds,ax
	lds	si,[4*0x41]
	mov	ax,#INITSEG
	mov	es,ax
	mov	di,#0x0080
	mov	cx,#0x10
	rep
	movsb

# Get hd1 data

	mov	ax,#0x0000
	mov	ds,ax
	lds	si,[4*0x46]
	mov	ax,#INITSEG
	mov	es,ax
	mov	di,#0x0090
	mov	cx,#0x10
	rep
	movsb

# Check that there IS a hd1 :-)

	mov	ax,#0x01500
	mov	dl,#0x81
	int	0x13
	jc	no_disk1
	cmp	ah,#3
	je	is_disk1
no_disk1:
	mov	ax,#INITSEG
	mov	es,ax
	mov	di,#0x0090
	mov	cx,#0x10
	mov	ax,#0x00
	rep
	stosb
is_disk1:

# now we want to move to protected mode ...

	# no interrupts allowed !
	cli
	# 关中断

# first we move the system to it's rightful place

# 先将 system 模块从 0x10000 挪到 0x00000 处
# 这样 system 模块里边的绝对地址就能直接对得上内存地址了

# Q: 为什么不从一开始就在 bootsect 里把 system 载入到 0x00000 处呢？
# A: 因为在实模式中，内存起始处的 1KiB 空间会用来存放中断向量表
#    所以刚开始不能对其进行覆盖

# Q: 那为什么现在就可以覆盖到 0x00000 处呢？
# A: 1. 这里已经关了中断响应，覆盖掉也没关系
#    2. IDTR 在这期间也已经通过 lidt 指令完成了（暂时的）修改
#       不过因为 IDTR 还没准备好，所以还不能开中断

	mov	ax,#0x0000
	# 'direction'=0, movs moves forward
	cld
	# TODO: 不清楚 cld 指令在这的具体用途
do_move:
	# destination segment
	mov	es,ax
	# 目标段为 0x0000~0x8000，步进 0x1000
	add	ax,#0x1000
	cmp	ax,#0x9000
	jz	end_move
	# source segment
	mov	ds,ax
	sub	di,di
	sub	si,si
	mov 	cx,#0x8000
	rep
	movsw
	# 一次移动一个字，所以一个循环就是移动了 0x10000 字节，刚好符合段长的步进值
	jmp	do_move

# then we load the segment descriptors

end_move:
	# right, forgot this at first. didn't work :-)
	mov	ax,#SETUPSEG
	mov	ds,ax
	# load idt with 0,0
	lidt	idt_48
	# load gdt with whatever appropriate
	lgdt	gdt_48
	# 现在还在实模式下，但是这俩指令在实模式下也是可以执行的
	# 注意前文挪动的是 system 模块，setup 模块还在原地(0x90200)

# that was painless, now we enable A20

	call	empty_8042
	# command write
	mov	al,#0xD1
	out	#0x64,al
	call	empty_8042
	# A20 on
	mov	al,#0xDF
	out	#0x60,al
	call	empty_8042

# well, that went ok, I hope. Now we have to reprogram the interrupts :-(
# we put them right after the intel-reserved hardware interrupts, at
# int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
# messed this up with the original PC, and they haven't been able to
# rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
# which is used for the internal hardware interrupts as well. We just
# have to reprogram the 8259's, and it isn't fun.

# 不想读，这段弄懂了应该也没啥帮助，跟中断有关，应该是老设备的历史包袱，跳过
    # initialization sequence
	mov	al,#0x11
	# send it to 8259A-1
	out	#0x20,al
	# jmp $+2, jmp $+2
	.word	0x00eb,0x00eb
	# and to 8259A-2
	out	#0xA0,al
	.word	0x00eb,0x00eb
	# start of hardware int's (0x20)
	mov	al,#0x20
	out	#0x21,al
	.word	0x00eb,0x00eb
	# start of hardware int's 2 (0x28)
	mov	al,#0x28
	out	#0xA1,al
	.word	0x00eb,0x00eb
	# 8259-1 is master
	mov	al,#0x04
	out	#0x21,al
	.word	0x00eb,0x00eb
	# 8259-2 is slave
	mov	al,#0x02
	out	#0xA1,al
	.word	0x00eb,0x00eb
	# 8086 mode for both
	mov	al,#0x01
	out	#0x21,al
	.word	0x00eb,0x00eb
	out	#0xA1,al
	.word	0x00eb,0x00eb
	# mask off all interrupts for now
	mov	al,#0xFF
	out	#0x21,al
	.word	0x00eb,0x00eb
	out	#0xA1,al

# well, that certainly wasn't fun :-(. Hopefully it works, and we don't
# need no steenking BIOS anyway (except for the initial loading :-).
# The BIOS-routine wants lots of unnecessary data, and it's less
# "interesting" anyway. This is how REAL programmers do it.
# 
# Well, now's the time to actually move into protected mode. To make
# things as simple as possible, we do no register set-up or anything,
# we let the gnu-compiled 32-bit programs do that. We just jump to
# absolute address 0x00000, in 32-bit protected mode.
# 这里要准备进入保护模式了

    # protected mode (PE) bit
	mov	ax,#0x0001
	# This is it!
	lmsw	ax
	# load machine status word
	# 这条指令可被 "mov cr0, eax" 所（类似地）替代

	# 这里有一个很好的问题：
	# 既然在这条指令之后，CPU 就已经进入了保护模式，
	# 那此时的 CS:EIP 就会因为 GDT 还没为此准备好，而指向错误的地址，
	# 无法指向下一条指令，即 "jmpi 0, 8"
	# 但是，事实上，这件事并不会发生，为什么？

	# 因为当段寄存器被"载入"(即存入数据)时，CPU 才会去读取相应的段描述符
	# 平时则是直接使用缓存

	# 来源：https://stackoverflow.com/questions/30932302/i-am-confusing-some-assembly-code-about-enable-pe-within-boot-setup-s-file-in-linux-0-11
	# jmp offset 0 of segment 8 (cs)
	jmpi	0,8

	# 针对上边这条指令，我再补一些补充说明，不翻译了，反正不难懂
	# 来源：http://www.oldlinux.org/Linux.old/study/eclk-03-boot.pdf

	# As we have moved the system module begin at the absolute address 0x0000, the jump
	# instruction above will pass the CPU controls to the head.s code at the begin of
	# system module. The segment selector ( 8 ) is used to select a segment descripter
	# in an identified descripter table. Segment selector has 16 bits, bit 0-1 represents
	# requested privilege level (RPL), bit 2 is a table indicator used to specify the
	# refered descriptor table ( 0 - GDT, 1- LDT), bit 3-15 is INDEX field used to index
	# a descripter in the talbe. A sepecified descripter address is:
	# Table Base Address + INDEX * 8
	# So segment selector 8 (0b0000,0000,0000,1000) means RPL=0, selects item 1 (INDEX=1)
	# within globle descripter table (GDT). This specified descripter indicates that the
	# segment base address is 0 (see L209), so the instruction of L193 will jump to the
	# beginning of system module.

	# 大体意思就是，这个 8 是一个段选择子，最终效果是跳到 GDT 第一项对应的内存空间（且 offset=0）
	# 且 GDT 的第一项描述符，其基址被设置为了 0
	# 加上 system 模块已经被挪到了 0x00000 处
	# 最终效果就是跳到 system 模块去啦（入口是 boot/head.s）

	# 关于段选择子：

	# |15    3|  2  |1 0|
	# +-----------------+
	# | Index | G/L |RPL|
	# +-----------------+

	# G/L: 0 - GDT, 1 - LDT

# This routine checks that the keyboard command queue is empty
# No timeout is used - if this hangs there is something wrong with
# the machine, and we probably couldn't proceed anyway.
empty_8042:
	.word	0x00eb,0x00eb
	# 8042 status port
	in	al,#0x64
	# is input buffer full?
	test	al,#2
	# yes - loop
	jnz	empty_8042
	ret

# GDT 描述符结构：

# |31                                          16|15                              0|
# +----------------------------------------------+---------------------------------+
# |                   Base 15~0                  |            Limit 15~0           |
# +--------------------------------------------------------------------------------+

# |31        24| 23|  22 | 21|  20 |19         16| 15|14 13| 12|11   8|7          0|
# +--------------------------------------------------------------------------------+
# | Base 31~24 | G | D/B | L | AVL | Limit 19~16 | P | DPL | S | TYPE | Base 23~16 |
# +--------------------------------------------------------------------------------+

# G: 	粒度
# D/B:	默认的操作数大小
# L:	标示处理器类型(32/64位)
# AVL:	供操作系统使用

# P:	存在位
# DPL:	特权级
# S:	描述符类型
# 		S=0: 这是一个系统段
# 		S=1: 这是一个代码段/数据段
# TYPE: X E W A (X=0, 数据)
# 		X C R A (X=1, 代码)

gdt:
	# dummy
	.word	0,0,0,0
	# 第一个描述符必须是全零 (CPU 的特殊规定)

	# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x07FF
	# base address=0
	.word	0x0000
	# code read/exec,  "1 00 1 1010 00000000"
	.word	0x9A00
	# granularity=4096, 386
	.word	0x00C0

	# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x07FF
	# base address=0
	.word	0x0000
	# data read/write, "1 00 1 0010 00000000"
	.word	0x9200
	# granularity=4096, 386
	.word	0x00C0


idt_48:
	# idt limit=0
	.word	0
	# idt base=0L
	.word	0,0
# lidt 指令的操作数

gdt_48:
	# gdt limit=2048, 256 GDT entries
	.word	0x800
	# gdt base = 0x9XXXX
	.word	512+gdt,0x9
# lgdt 指令的操作数
	
.text
endtext:
.data
enddata:
.bss
endbss:

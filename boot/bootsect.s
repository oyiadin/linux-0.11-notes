# bootsec 到时候是镜像中最打头的部分

#
# SYS_SIZE is the number of clicks (16 bytes) to be loaded.
# 0x3000 is 0x30000 bytes = 196kB, more than enough for current
# versions of linux
#
SYSSIZE = 0x3000
#
#	bootsect.s		(C) 1991 Linus Torvalds
#
# bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
# itself out of the way to address 0x90000, and jumps there.
#
# It then loads 'setup' directly after itself (0x90200), and the system
# at 0x10000, using BIOS interrupts. 
#
# NOTE! currently system is at most 8*65536 bytes long. This should be no
# problem, even in the future. I want to keep it simple. This 512 kB
# kernel size should be enough, especially as this doesn't contain the
# buffer cache as in minix
#
# The loader has been made as simple as possible, and continuos
# read errors will result in a unbreakable loop. Reboot by hand. It
# loads pretty fast by getting whole sectors at a time whenever possible.

# BIOS 会将这份文件载入到 0x7c00 处
# 首先将自身挪到 0x90000，然后跳转过去，接着将 setup 载入到 0x90200 处
# 载入完成后就跳转到 setup 的入口

.globl begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

# nr of setup-sectors
SETUPLEN = 4
# 下列数值是段值，所以要 <<4，得到 0x7c00
# original address of boot-sector
BOOTSEG  = 0x07c0
# we move boot here - out of the way
INITSEG  = 0x9000
# setup starts here
SETUPSEG = 0x9020
# system loaded at 0x10000 (65536).
SYSSEG   = 0x1000
# where to stop loading
ENDSEG   = SYSSEG + SYSSIZE

# ROOT_DEV:	0x000 - same type of floppy as boot.
#		0x301 - first partition on first drive etc
ROOT_DEV = 0x306
# 会被放到本文件末尾的 root_dev 里

entry start
start:
	mov	ax,#BOOTSEG
	mov	ds,ax
	mov	ax,#INITSEG
	mov	es,ax
	mov	cx,#256
	# ds:si = 0x07c0:0x0000
	sub	si,si
	# es:di = 0x9000:0x0000
	sub	di,di
	rep
	# 移动1个字，重复256次（512 Bytes）
	movw
	# 跳到移动后的 go 标号处（0x90000+go）
	jmpi	go,INITSEG
# 重设段寄存器 ds,es,ss，重设到当前代码所在段即 0x9000
go:	mov	ax,cs
	mov	ds,ax
	mov	es,ax
# put stack at 0x9ff00.
	mov	ss,ax
	# arbitrary value >>512
	mov	sp,#0xFF00
# 栈随便放，不碍着地就行，Linus选了个 0x9ff00（注意栈往低处增长）

# load the setup-sectors directly after the bootblock.
# Note that 'es' is already set up.

# 注意此时 es 段寄存器是 0x9000

load_setup:
	# drive 0, head 0
	mov	dx,#0x0000
	# sector 2, track 0
	mov	cx,#0x0002
	# address = 512, in INITSEG
	mov	bx,#0x0200
	# service 2, nr of sectors
	mov	ax,#0x0200+SETUPLEN
	# read it
	int	0x13
	# 读取 setup 的数据，放到 es:bx 即 0x9000:0x0200 处
	# 总共读取 4 个扇区 (SETUPLEN)
	# int 0x13 是 BIOS 提供的服务，可以读磁盘
	# ok - continue
	jnc	ok_load_setup
	mov	dx,#0x0000
	# reset the diskette
	mov	ax,#0x0000
	# 如果不成功就重设一些参数后重新尝试
	int	0x13
	j	load_setup

ok_load_setup:

# Get disk drive parameters, specifically nr of sectors/track

	mov	dl,#0x00
	# AH=8 is get drive parameters
	mov	ax,#0x0800
	# 该中断服务程序会将磁盘参数表置于 es:di 处
	int	0x13
	mov	ch,#0x00
	seg cs
	# 保存每磁道最大扇区数到 sectors (见本文件末)
	mov	sectors,cx
	# 因为 sectors 就在本文件末，所以是 cs:sectors
	mov	ax,#INITSEG
	# int 0x13 似乎会破坏 es 的值，重新改正
	mov	es,ax

# Print some inane message

    # read cursor pos
	mov	ah,#0x03
	xor	bh,bh
	int	0x10
	
	mov	cx,#24
	# page 0, attribute 7 (normal)
	mov	bx,#0x0007
	mov	bp,#msg1
	# write string, move cursor
	mov	ax,#0x1301
	int	0x10

# ok, we've written the message, now
# we want to load the system (at 0x10000)

# 将 system 模块载入到 0x10000 处
# system 模块其实就是 boot/head.s 跟 init/main.c
# 具体可以看 /Makefile 文件

	mov	ax,#SYSSEG
	# segment of 0x010000
	mov	es,ax
	call	read_it
	# TODO: 关闭软驱的电机，不过我不清楚为什么要有这一步
	call	kill_motor

# After that we check which root-device to use. If the device is
# defined (!= 0), nothing is done and the given device is used.
# Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
# on the number of sectors that the BIOS reports currently.

	seg cs
	mov	ax,root_dev
	cmp	ax,#0
	# root_dev 定义过了，不作处理
	jne	root_defined
	# 否则根据每磁道扇区数判断是啥类型的磁盘
	seg cs
	mov	bx,sectors
	# /dev/ps0 - 1.2Mb
	mov	ax,#0x0208
	cmp	bx,#15
	je	root_defined
	# /dev/PS0 - 1.44Mb
	mov	ax,#0x021c
	cmp	bx,#18
	je	root_defined
# 找不到就死循环
undef_root:
	jmp undef_root
root_defined:
	seg cs
	mov	root_dev,ax

# after that (everyting loaded), we jump to
# the setup-routine loaded directly after
# the bootblock:

	jmpi	0,SETUPSEG
	# 跳到 setup 起始处
	# 此时 setup 已经被载入到 0x10000～0x30000 处了

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in:	es - starting address segment (normally 0x1000)
#
# sectors read of current track
sread:	.word 1+SETUPLEN
# current head
head:	.word 0
# current track
track:	.word 0

read_it:
	mov ax,es
	test ax,#0x0fff
die:
	# es must be at 64kB boundary
	jne die
	# 0x1000 & 0x0fff = 0, ZF=1
	# 所以这里不会进入死循环 (ZF=0 才会死循环)
	# 以这种方式检查 es 是否与 64KiB 对齐
	# TODO: 不清楚为什么一定要对齐
	# bx is starting address within segment
	xor bx,bx
	# 下边就懒得读了，意义不大，就是利用 int 0x13 读数据而已
rp_read:
	mov ax,es
	# have we loaded all yet?
	cmp ax,#ENDSEG
	jb ok1_read
	ret
ok1_read:
	seg cs
	mov ax,sectors
	sub ax,sread
	mov cx,ax
	shl cx,#9
	add cx,bx
	jnc ok2_read
	je ok2_read
	xor ax,ax
	sub ax,bx
	shr ax,#9
ok2_read:
	call read_track
	mov cx,ax
	add ax,sread
	seg cs
	cmp ax,sectors
	jne ok3_read
	mov ax,#1
	sub ax,head
	jne ok4_read
	inc track
ok4_read:
	mov head,ax
	xor ax,ax
ok3_read:
	mov sread,ax
	shl cx,#9
	add bx,cx
	jnc rp_read
	mov ax,es
	add ax,#0x1000
	mov es,ax
	xor bx,bx
	jmp rp_read

read_track:
	push ax
	push bx
	push cx
	push dx
	mov dx,track
	mov cx,sread
	inc cx
	mov ch,dl
	mov dx,head
	mov dh,dl
	mov dl,#0
	and dx,#0x0100
	mov ah,#2
	int 0x13
	jc bad_rt
	pop dx
	pop cx
	pop bx
	pop ax
	ret
bad_rt:	mov ax,#0
	mov dx,#0
	int 0x13
	pop dx
	pop cx
	pop bx
	pop ax
	jmp read_track

/*
 * This procedure turns off the floppy drive motor, so
 * that we enter the kernel in a known state, and
 * don't have to worry about it later.
 */
kill_motor:
	push dx
	mov dx,#0x3f2
	mov al,#0
	outb
	pop dx
	ret

sectors:
	.word 0

msg1:
	.byte 13,10
	.ascii "Loading system ..."
	.byte 13,10,13,10

.org 508
# 会被 tools/build.c 填充进真实的设备号
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xAA55

.text
endtext:
.data
enddata:
.bss
endbss:

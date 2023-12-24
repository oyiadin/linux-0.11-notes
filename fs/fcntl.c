/*
 *  linux/fs/fcntl.c
 *
 *  (C) 1991  Linus Torvalds
 */

#include <string.h>
#include <errno.h>
#include <linux/sched.h>
#include <linux/kernel.h>
#include <asm/segment.h>

#include <fcntl.h>
#include <sys/stat.h>

extern int sys_close(int fd);

// current 在 include/linux/sched.h 里

// fd 是已有的 fd
// arg 是目标 fd（实际上不保证新 fd 一定在这）
// 其只是开始寻找的“下标”，最终返回的是最小的可用 fd 值
static int dupfd(unsigned int fd, unsigned int arg)
{
	if (fd >= NR_OPEN || !current->filp[fd])
		return -EBADF;
	if (arg >= NR_OPEN)
		return -EINVAL;
	while (arg < NR_OPEN) 	// 递增寻找最小的可用 fd 值
		if (current->filp[arg])
			arg++;
		else
			break;
	if (arg >= NR_OPEN) 	// 打开的文件过多，fd 列表不够用了
		return -EMFILE;
    // 新 fd 的 close-on-exec 标志会被清除，也就是不会自动关闭
    // 这是个很有用的特性，因为典型场景下，dup 基本会配合 exec 一起使用
	current->close_on_exec &= ~(1<<arg);
    // 可以看到只是在 filp 中拷贝了一个指针，背后的 file 结构体还是共享同一个
    // 这也就意味着，dup 产生的多个 fd，将共享偏移量、mode、flags 等信息
	(current->filp[arg] = current->filp[fd])->f_count++;
	return arg;
}

int sys_dup2(unsigned int oldfd, unsigned int newfd)
{
	sys_close(newfd);
    // 由于先关闭了 newfd，可以保证新 fd 是在预期的位置上
	return dupfd(oldfd,newfd);
}

int sys_dup(unsigned int fildes)
{
	return dupfd(fildes,0);
}

int sys_fcntl(unsigned int fd, unsigned int cmd, unsigned long arg)
{	
	struct file * filp;

	if (fd >= NR_OPEN || !(filp = current->filp[fd]))
		return -EBADF;
	switch (cmd) {
		case F_DUPFD:
			return dupfd(fd,arg);
		case F_GETFD:
			return (current->close_on_exec>>fd)&1;
		case F_SETFD:
			if (arg&1)
				current->close_on_exec |= (1<<fd);
			else
				current->close_on_exec &= ~(1<<fd);
			return 0;
		case F_GETFL:
			return filp->f_flags;
		case F_SETFL:
			filp->f_flags &= ~(O_APPEND | O_NONBLOCK);
			filp->f_flags |= arg & (O_APPEND | O_NONBLOCK);
			return 0;
		case F_GETLK:	case F_SETLK:	case F_SETLKW:
			return -1;
		default:
			return -1;
	}
}

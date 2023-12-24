/*
 *  linux/lib/errno.c
 *
 *  (C) 1991  Linus Torvalds
 */

// 这里有一个很微妙的细节
// errno 不存在于内核中，而是由用户的程序将此文件链接到一起
// 实际上每个程序都有自己的一个 errno
// 内核只通过 int 0x80 来接收系统调用
// 实际上设置 errno 的是将系统调用封装为函数的那一部分宏（在 unistd.h 中）
// 而依靠这个宏，将系统调用封装为函数的代码，并不在 linux 项目里（也就是现在的 libc）
int errno;

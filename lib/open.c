/*
 *  linux/lib/open.c
 *
 *  (C) 1991  Linus Torvalds
 */

#define __LIBRARY__
#include <unistd.h>
#include <stdarg.h>

int open(const char * filename, int flag, ...)
{
	register int res;
	va_list arg;

	va_start(arg,flag);
	__asm__("int $0x80"
		:"=a" (res)
		:"0" (__NR_open),"b" (filename),"c" (flag),
		"d" (va_arg(arg,int)));
	// 第三个参数是“mode”
	// TODO: 但是如果用户程序没有传入第三个参数该咋办…
	if (res>=0)
		return res;
	errno = -res;
	return -1;
}

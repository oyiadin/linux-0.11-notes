#ifndef _STDARG_H
#define _STDARG_H

typedef char *va_list;

/* Amount of space required in an argument list for an arg of type TYPE.
   TYPE may alternatively be an expression whose type is used.  */

#define __va_rounded_size(TYPE)  \
  (((sizeof (TYPE) + sizeof (int) - 1) / sizeof (int)) * sizeof (int))
// 看懂了，就是向上取整，即整数倍 sizeof(int)

// 下边这个宏函数，就是在 LASTARG 的基础上，往高处挪
// 根据调用约定，参数从右往左入栈，又由于栈往低处增长
// 所以“往高处挪动”就能获取到下一个参数
#ifndef __sparc__
#define va_start(AP, LASTARG) 						\
 (AP = ((char *) &(LASTARG) + __va_rounded_size (LASTARG)))
#else
#define va_start(AP, LASTARG) 						\
 (__builtin_saveregs (),						\
  AP = ((char *) &(LASTARG) + __va_rounded_size (LASTARG)))
#endif

void va_end (va_list);		/* Defined in gnulib */
// TODO: 这个声明干嘛用的

#define va_end(AP)

#define va_arg(AP, TYPE)						\
 (AP += __va_rounded_size (TYPE),					\
  *((TYPE *) (AP - __va_rounded_size (TYPE))))
// 逗号运算符返回最后一个对象
// 先让 AP 往后挪动
// 再借助逗号运算符返回“上一个参数”的值（因为已经挪动过了，所以是“上一个”）

#endif /* _STDARG_H */

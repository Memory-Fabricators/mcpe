

#if defined(_WIN32)
#include <conio.h> /* getche() */

#else
#include <stdio.h>
#include <termios.h>
#include <unistd.h>
char getche();
#endif

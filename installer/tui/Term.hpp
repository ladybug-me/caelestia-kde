#pragma once
#include <termios.h>

namespace Term {
    extern termios initial_settings;
    extern bool initialized;
    extern bool raw_mode;

    void get_size();
    void restore();
    void init();
}

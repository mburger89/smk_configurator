// Homebrew's hidapi.pc points -I directly inside the hidapi/ dir, so
// <hidapi.h> resolves there; Ubuntu's libhidapi-dev installs to the
// standard /usr/include/hidapi/hidapi.h (no matching pkg-config module
// pointing inside it), so <hidapi.h> alone won't resolve there. Try both.
#if __has_include(<hidapi.h>)
#include <hidapi.h>
#else
#include <hidapi/hidapi.h>
#endif

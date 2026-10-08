#include "../common/shimlog.h"
#include <stdlib.h>
void hades_swiftui_mac_trap(void)
{
    SHIM_LOG("SwiftUI NSHostingController used (bug reporter UI) - not available on iOS");
    abort();
}

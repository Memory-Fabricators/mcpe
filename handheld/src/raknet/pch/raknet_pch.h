// Precompiled header for RakNet — headers included by the majority of TUs.
// Meson compiles this once and reuses it across all 94 .cpp files.
#pragma once

// C standard headers (included by ~25+ TUs each)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

// C++ standard headers
#include <string>
#include <vector>
#include <map>

// RakNet near-universal headers
#include "NativeFeatureIncludes.h"
#include "Export.h"
#include "RakMemoryOverride.h"
#include "RakAssert.h"
#include "RakNetTypes.h"
#include "GetTime.h"

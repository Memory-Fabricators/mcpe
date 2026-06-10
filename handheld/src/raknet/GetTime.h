/// \file GetTime.h
/// \brief Returns the value from QueryPerformanceCounter.  This is the function
/// RakNet uses to represent time. This time won't match the time returned by
/// GetTimeCount(). See
/// http://www.jenkinssoftware.com/forum/index.php?topic=2798.0
///
/// This file is part of RakNet Copyright 2003 Jenkins Software LLC
///
/// Usage of RakNet is subject to the appropriate license agreement.

#ifndef __GET_TIME_H
#define __GET_TIME_H

#include "Export.h"
#include "RakNetTime.h" // For RakNet::TimeMS

extern "C" uint64_t rust_get_time_ms(void);

namespace RakNet {
/// Same as GetTimeMS
/// Holds the time in either a 32 or 64 bit variable, depending on
/// __GET_TIME_64BIT
inline RakNet::Time GetTime(void) {
    return (RakNet::Time)rust_get_time_ms();
}

/// Return the time as 32 bit
/// \note The maximum delta between returned calls is 1 second - however, RakNet
/// calls this constantly anyway. See NormalizeTime() in the cpp.
inline RakNet::TimeMS GetTimeMS(void) {
    return (RakNet::TimeMS)rust_get_time_ms();
}

/// Return the time as 64 bit
/// \note The maximum delta between returned calls is 1 second - however, RakNet
/// calls this constantly anyway. See NormalizeTime() in the cpp.
inline RakNet::TimeUS GetTimeUS(void) {
    return (RakNet::TimeUS)(rust_get_time_ms() * 1000);
}

/// a > b?
inline bool GreaterThan(RakNet::Time a, RakNet::Time b) {
  const RakNet::Time halfSpan =
      (RakNet::Time)(((RakNet::Time)(const RakNet::Time)-1) / (RakNet::Time)2);
  return b != a && b - a > halfSpan;
}
/// a < b?
inline bool LessThan(RakNet::Time a, RakNet::Time b) {
  const RakNet::Time halfSpan =
      ((RakNet::Time)(const RakNet::Time)-1) / (RakNet::Time)2;
  return b != a && b - a < halfSpan;
}
} // namespace RakNet

#endif

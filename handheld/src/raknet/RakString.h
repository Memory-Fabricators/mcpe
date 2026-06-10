#ifndef __RAK_STRING_H
#define __RAK_STRING_H

#include "Export.h"
#include <string>
#include <stdint.h>

namespace RakNet {
class BitStream;

class RAK_DLL_EXPORT RakString : public std::string {
public:
  using std::string::string;
  
  RakString(const std::string &s) : std::string(s) {}
  RakString(const char *format, ...);
  RakString(const unsigned char *format, ...);

  const char *C_String(void) const { return c_str(); }
  size_t GetLength(void) const { return length(); }
  RakString SubStr(unsigned int index, unsigned int count) const;
  int StrCmp(const RakString &rhs) const { return compare(rhs); }

  static RakNet::RakString NonVariadic(const char *str) { return RakString(str); }
  static void FreeMemory(void) {}
  static void FreeMemoryNoMutex(void) {}

  void Serialize(BitStream *bs) const;
  static void Serialize(const char *str, BitStream *bs);
  void SerializeCompressed(BitStream *bs, uint8_t languageId = 0, bool writeLanguageId = false) const;
  static void SerializeCompressed(const char *str, BitStream *bs, uint8_t languageId = 0, bool writeLanguageId = false);

  bool Deserialize(BitStream *bs);
  static bool Deserialize(char *str, BitStream *bs);
  bool DeserializeCompressed(BitStream *bs, bool readLanguageId = false);
  static bool DeserializeCompressed(char *str, BitStream *bs, bool readLanguageId = false);
};

} // namespace RakNet

#endif

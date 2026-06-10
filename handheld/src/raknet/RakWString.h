#ifndef __RAK_W_STRING_H
#define __RAK_W_STRING_H

#include <string>

namespace RakNet {
class BitStream;

class RakWString : public std::wstring {
public:
  using std::wstring::wstring;
  
  void Serialize(BitStream *bs) const {}
  static void Serialize(const wchar_t *str, BitStream *bs) {}
  
  bool Deserialize(BitStream *bs) { return false; }
  static bool Deserialize(wchar_t *str, BitStream *bs) { return false; }
};
}

#endif

#ifndef NET_MINECRAFT_CLIENT_RENDERER__RenderChunkHandler_H__
#define NET_MINECRAFT_CLIENT_RENDERER__RenderChunkHandler_H__

#include "RenderChunk.h"
#include <vector>

typedef std::vector<RenderChunk> ChunkList;

class RenderChunkHandler {
public:
  int vboCount;
  ChunkList chunks;

  RenderChunkHandler() { vboCount = Tesselator::getVboCount(); }

  void render() {}
};

#endif /*NET_MINECRAFT_CLIENT_RENDERER__RenderChunkHandler_H__*/

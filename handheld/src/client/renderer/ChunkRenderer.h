#ifndef CHUNKRENDERER_H__
#define CHUNKRENDERER_H__

#include "../../world/level/Region.h"
#include "gles.h"

class ChunkRenderer {
public:
  ChunkRenderer(const Region &region) : r(region) {}

  void render() {
    // glTranslate(r.xc1,
  }

private:
  const Region &r;
};

#endif /*CHUNKRENDERER_H__*/

#ifndef NET_MINECRAFT_WORLD_LEVEL_BIOME__RainforestBiome_H__
#define NET_MINECRAFT_WORLD_LEVEL_BIOME__RainforestBiome_H__

// package net.minecraft.world.level.biome;

#include "../../../util/Random.h"
#include "../levelgen/feature/TreeFeature.h"
#include "Biome.h"

class RainforestBiome : public Biome {
public:
  Feature *getTreeFeature(Random *random) {
    if (random->nextInt(3) == 0) {
      // return new BasicTree();
    }
    return new TreeFeature(false);
  }
};

#endif /*NET_MINECRAFT_WORLD_LEVEL_BIOME__RainforestBiome_H__*/

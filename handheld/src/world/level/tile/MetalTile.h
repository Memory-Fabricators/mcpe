#ifndef NET_MINECRAFT_WORLD_LEVEL_TILE__MetalTile_H__
#define NET_MINECRAFT_WORLD_LEVEL_TILE__MetalTile_H__

// package net.minecraft.world.level.tile;

#include "../material/Material.h"
#include "Tile.h"

class MetalTile : public Tile {
public:
  MetalTile(int id, int tex) : Tile(id, Material::metal) { this->tex = tex; }

  int getTexture(int face) { return tex; }
};

#endif /*NET_MINECRAFT_WORLD_LEVEL_TILE__MetalTile_H__*/

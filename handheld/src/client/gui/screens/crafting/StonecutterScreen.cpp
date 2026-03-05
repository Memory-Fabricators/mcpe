#include "StonecutterScreen.h"
#include "../../../../world/item/ItemCategory.h"
#include "../../../../world/level/material/Material.h"
#include "CraftingFilters.h"

StonecutterScreen::StonecutterScreen() : super(Recipe::SIZE_3X3) {
  setSingleCategoryAndIcon(ItemCategory::Structures, 5);
}

StonecutterScreen::~StonecutterScreen() {}

bool StonecutterScreen::filterRecipe(const Recipe &r) {
  return CraftingFilters::isStonecutterItem(r.getResultItem());
}

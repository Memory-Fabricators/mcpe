#include "WorkbenchScreen.h"
#include "../../../../world/level/material/Material.h"
#include "CraftingFilters.h"

WorkbenchScreen::WorkbenchScreen(int craftingSize) : super(craftingSize) {}

WorkbenchScreen::~WorkbenchScreen() {}

bool WorkbenchScreen::filterRecipe(const Recipe &r) {
  return !CraftingFilters::isStonecutterItem(r.getResultItem());
}

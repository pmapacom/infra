enum GoodsView { grid, list, map }

class SheetOption<T> {
  const SheetOption({required String label, required T value});
}

class Picked<T> {
  const Picked(T value); // отличает выбранный null от закрытия шита
}

class GoodsRegionBar extends StatelessWidget {
  const GoodsRegionBar({Key? key, required String label, required VoidCallback onTap});
}

class Facet { // это данные, не виджет
  const Facet({required IconData icon, required String label,
               required bool selected, required VoidCallback onTap});
}

class FacetChip extends StatelessWidget {
  const FacetChip({Key? key, required IconData icon, required String label,
                   required bool selected, required VoidCallback onTap});
}

class IconToggle extends StatelessWidget {
  const IconToggle({Key? key, required IconData icon, required VoidCallback onTap,
                    bool filled = false, bool selected = false});
}

class ViewSwitch extends StatelessWidget {
  const ViewSwitch({Key? key, required GoodsView view,
                    required ValueChanged<GoodsView> onChanged});
}

class RecentChip extends StatelessWidget {
  const RecentChip({Key? key, required String label,
                    required VoidCallback onTap, required VoidCallback onRemove});
}

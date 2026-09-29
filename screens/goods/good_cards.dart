class GoodCard extends StatelessWidget {      // grid-вариант
  const GoodCard({Key? key, required Good good, required VoidCallback onTap,
                  required bool saved, required VoidCallback onToggleSave});
}

class GoodListCard extends StatelessWidget {  // list-вариант, тот же API
  const GoodListCard({Key? key, required Good good, required VoidCallback onTap,
                      required bool saved, required VoidCallback onToggleSave});
}

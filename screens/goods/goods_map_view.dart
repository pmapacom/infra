class GoodsMap extends StatelessWidget {
  const GoodsMap({Key? key, required List<Good> goods,
                  required ValueChanged<Good> onTap});
  // строит pins из g.lng!/g.lat! → Offset(lng, lat); _MiniGoodCard приватная
}

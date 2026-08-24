import 'order.dart';
import 'product.dart';
import 'catalog_master_item.dart';

class OrderSelection {
  OrderSelection._(this._primary);

  factory OrderSelection.fromPrimary(Product product) =>
      OrderSelection._(_itemFromProduct(product, OrderItemType.primary));

  final OrderItemDraft _primary;
  final Map<String, OrderItemDraft> _complementaries = {};
  final Map<String, OrderItemDraft> _others = {};

  OrderItemDraft get primary => _primary;
  List<OrderItemDraft> get complementaries =>
      List.unmodifiable(_complementaries.values);
  List<OrderItemDraft> get others => List.unmodifiable(_others.values);
  List<OrderItemDraft> get items => List.unmodifiable([
    _primary,
    ..._complementaries.values,
    ..._others.values,
  ]);

  bool containsComplementary(String productId) =>
      _complementaries.containsKey(productId);

  void addComplementary(Product product, {required String relationId}) {
    if (relationId.trim().isEmpty) {
      throw ArgumentError(
        'El complementario requiere una relación verificable.',
      );
    }
    if (product.id == _primary.productId) {
      throw ArgumentError(
        'El producto principal no puede complementarse consigo mismo.',
      );
    }
    if (product.isSuggestedKit) {
      throw ArgumentError(
        'Un kit sugerido no puede venderse como kit oficial.',
      );
    }
    if (!product.available || !product.eligible) {
      throw ArgumentError('El producto complementario no está disponible.');
    }
    if (!_complementaries.containsKey(product.id) &&
        _complementaries.length >= 2) {
      throw StateError('Solo se permiten dos complementarios.');
    }
    _complementaries[product.id] = _itemFromProduct(
      product,
      OrderItemType.complementary,
      relationId: relationId,
    );
  }

  void removeComplementary(String productId) {
    _complementaries.remove(productId);
  }

  bool containsOther(String code) => _others.containsKey(code);

  bool containsAlternative(String productId) =>
      _others.values.any((item) => item.productId == productId);

  void addAlternative(Product product) {
    if (product.id == _primary.productId) {
      throw ArgumentError('El producto ya es la selección principal.');
    }
    if (!product.available || !product.eligible || product.isSuggestedKit) {
      throw ArgumentError('La alternativa no está disponible.');
    }
    if (_complementaries.containsKey(product.id)) {
      throw ArgumentError('El producto ya fue agregado como complementario.');
    }
    if (_others.values.any((item) => item.productId != product.id)) {
      throw StateError('Solo se permite una alternativa recomendada.');
    }
    _others[product.code] = _itemFromProduct(product, OrderItemType.other);
  }

  void removeAlternative(String productId) {
    _others.removeWhere((_, item) => item.productId == productId);
  }

  void addOther(CatalogMasterItem product) {
    if (!product.canRequest) {
      throw ArgumentError('Este producto no puede solicitarse en esta fase.');
    }
    if (product.code == _primary.productCode ||
        _complementaries.values.any(
          (item) => item.productCode == product.code,
        )) {
      throw ArgumentError('Este producto ya hace parte de la solicitud.');
    }
    if (!_others.containsKey(product.code) && _others.length >= 3) {
      throw StateError('Solo se permiten tres productos adicionales.');
    }
    _others[product.code] = OrderItemDraft(
      productId: 'CAT-${product.code}',
      productCode: product.code,
      productName: product.name,
      itemType: OrderItemType.other,
      quantity: 1,
      originalUnitPriceCop: product.priceCop,
    );
  }

  void removeOther(String code) {
    _others.remove(code);
  }

  OrderAmounts get amounts => OrderAmounts.fromItems(items);

  static OrderItemDraft _itemFromProduct(
    Product product,
    OrderItemType type, {
    String? relationId,
  }) => OrderItemDraft(
    productId: product.id,
    productCode: product.code,
    productName: product.name,
    itemType: type,
    quantity: 1,
    originalUnitPriceCop: product.priceCop,
    crossSellRelationId: relationId,
  );
}
